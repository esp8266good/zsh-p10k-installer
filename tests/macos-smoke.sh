#!/usr/bin/env bash
# tests/macos-smoke.sh：在 Mac 上用暫存 HOME 測安裝腳本，不碰真的 home。
#
#   ./tests/macos-smoke.sh                 跑全部情境
#   ./tests/macos-smoke.sh clean rerun     只跑指定的情境
#
# 要測的腳本預設是 dist/install-zsh-p10k.sh，可以用 ZSH_P10K_INSTALLER 換掉。
# 要能在 macOS 內建的 bash 3.2 下跑，所以不用 mapfile、關聯陣列這類語法。

# RC、h 這些變數是在 check 的 eval 字串裡用的，shellcheck 看不到。
# shellcheck disable=SC2034
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
INSTALLER="${ZSH_P10K_INSTALLER:-$HERE/../dist/install-zsh-p10k.sh}"
[ -f "$INSTALLER" ] || { echo "找不到 $INSTALLER，先跑 ./build.sh" >&2; exit 2; }
[ "$(uname -s)" = "Darwin" ] || { echo "這支測試只能在 macOS 上跑。" >&2; exit 2; }

PASS=0
FAIL=0
SKIP=0
ok()   { printf '  \033[32mPASS\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
# 每個情境第一次失敗時，把安裝腳本的 WARN / FAIL 行和最後 10 行輸出印出來，
# CI 上才看得出是哪一步壞。
DUMPED=0
bad()  {
  printf '  \033[31mFAIL\033[0m %s\n' "$1"; FAIL=$((FAIL+1))
  if [ "$DUMPED" -eq 0 ] && [ -s "${OUT:-}" ]; then
    DUMPED=1
    printf '    ---- 安裝腳本的 WARN / FAIL ----\n'
    grep -aE '\[(WARN|FAIL)\]|curl: |wget: ' "$OUT" | sed 's/^/    | /'
    printf '    ---- 安裝腳本最後 10 行 ----\n'
    tail -10 "$OUT" | sed 's/^/    | /'
  fi
}
skip() { printf '  \033[33mSKIP\033[0m %s\n' "$1"; SKIP=$((SKIP+1)); }
check(){ if eval "$2"; then ok "$1"; else bad "$1"; fi; }
banner() { DUMPED=0; printf '\n\033[1m=== macOS 情境：%s ===\033[0m\n' "$1"; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/zsh-p10k-smoke.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

OUT="$WORK/out.txt"
RC=0
XS_LOG="$WORK/xcode-select.log"

SUDO_LOG="$WORK/sudo.log"

# 假的 xcode-select：--install 只記一筆，不真的跳視窗。
# FAKE_NO_CLT=1 時 -p 假裝失敗，這樣有裝 Command Line Tools 的機器（含 CI）也測得到那條路。
mkdir -p "$WORK/bin"
cat > "$WORK/bin/xcode-select" <<EOF
#!/bin/sh
case "\${1:-}" in
  --install) echo "install" >> "$XS_LOG"; echo "xcode-select: error: 假裝被 MDM 擋掉" >&2; exit 1 ;;
  -p) [ "\${FAKE_NO_CLT:-0}" = 1 ] && { echo "xcode-select: error: unable to get active developer directory" >&2; exit 2; }
      exec /usr/bin/xcode-select -p ;;
  *) exec /usr/bin/xcode-select "\$@" ;;
esac
EOF
chmod +x "$WORK/bin/xcode-select"

# 假的 sudo：只記錄有沒有被呼叫。macOS 上安裝腳本一次都不該叫它。
cat > "$WORK/bin/sudo" <<EOF
#!/bin/sh
echo "sudo \$*" >> "$SUDO_LOG"
exit 1
EOF
chmod +x "$WORK/bin/sudo"

# 假的 mdfind：FAKE_MDFIND 有值就回報它，否則什麼都沒找到。結果才不受這台機器的 Spotlight 影響。
cat > "$WORK/bin/mdfind" <<'EOF'
#!/bin/sh
[ -n "${FAKE_MDFIND:-}" ] && printf '%s\n' "$FAKE_MDFIND"
exit 0
EOF
chmod +x "$WORK/bin/mdfind"

no_sudo_called() { [ ! -s "$SUDO_LOG" ]; }

new_home() { mktemp -d "$WORK/home.XXXXXX"; }

home_is_empty() { [ -z "$(find "$1" -mindepth 1 2>/dev/null | head -1)" ]; }

# 沒有 tty 的跑法：用 perl 的 setsid 拿掉 controlling terminal，
# 這樣在終端機裡直接跑測試，也跟「ssh host command」一樣打不開 /dev/tty。
run_notty() {
  local home="$1"; shift
  : > "$XS_LOG"; : > "$SUDO_LOG"
  RC=0
  env HOME="$home" PATH="$WORK/bin:$PATH" \
    perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV or die "exec: $!"' \
    bash "$INSTALLER" "$@" < /dev/null > "$OUT" 2>&1 || RC=$?
}

# 有 tty 的跑法：用 expect 開一個 pty，每出現一個提示就依序送一個答案。
# 不用 `printf ... | script`：macOS 的 script 讀到 stdin 的 EOF 會往 pty 送 ^D，
# 而且比前面的輸入還早被處理，read 讀到的會是空字串。
# 比對只用 ASCII：每個 y/N 問題都以「[y/N] 」結尾，按 Enter 那一步有「Ctrl-C」。
# macOS 內建的 expect 5.45 遇到中文的比對字串會 segfault（實測 3/3），
# 所以問題內容改在跑完之後 grep 輸出檔檢查。
cat > "$WORK/drive.exp" <<'EOF'
set timeout 900
set sep [lsearch -exact $argv --]
set answers [lrange $argv 0 [expr {$sep - 1}]]
set cmd [lrange $argv [expr {$sep + 1}] end]
spawn {*}$cmd
foreach ans $answers {
  expect {
    -ex {[y/N] } { send -- "$ans\r" }
    -ex {Ctrl-C} { send -- "$ans\r" }
    timeout { puts "\nexpect: timeout waiting for prompt"; exit 98 }
    eof { puts "\nexpect: program exited before prompt"; catch wait r; exit [lindex $r 3] }
  }
}
expect {
  -ex {[y/N] } { puts "\nexpect: unexpected y/N prompt"; exit 96 }
  eof {}
  timeout { puts "\nexpect: timeout waiting for exit"; exit 97 }
}
catch wait result
exit [lindex $result 3]
EOF

# run_tty <home> [答案]... -- [安裝腳本參數]...
# 答案依提示出現的順序給；按 Enter 繼續那一步給空字串。
run_tty() {
  local home="$1"; shift
  : > "$XS_LOG"; : > "$SUDO_LOG"
  RC=0
  local pairs=()
  while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do pairs+=("$1"); shift; done
  [ "$#" -gt 0 ] && shift
  env HOME="$home" PATH="$WORK/bin:$PATH" \
    expect "$WORK/drive.exp" ${pairs[@]+"${pairs[@]}"} -- bash "$INSTALLER" "$@" > "$OUT" 2>&1 || RC=$?
}

out_has() { grep -qF -- "$1" "$OUT"; }

# ---------------------------------------------------------------------------
# 情境
# ---------------------------------------------------------------------------

# 「沒有 Command Line Tools」都用假的 xcode-select -p 模擬（FAKE_NO_CLT=1）。

t_no_clt_notty() {
  banner "no-clt-notty"
  local h; h="$(new_home)"
  FAKE_NO_CLT=1 run_notty "$h"
  check "exit code 不是 0" '[ "$RC" -ne 0 ]'
  check "輸出提到 xcode-select --install" 'out_has "xcode-select --install"'
  check "HOME 底下沒有任何檔案" 'home_is_empty "$h"'
  check "沒有執行 xcode-select --install" '[ ! -s "$XS_LOG" ]'
}

t_no_clt_tty_no() {
  banner "no-clt-tty-no"
  local h; h="$(new_home)"
  FAKE_NO_CLT=1 run_tty "$h" "n" --
  check "有問要不要叫出安裝視窗" 'out_has "要幫你叫出安裝視窗嗎"'
  check "exit code 不是 0" '[ "$RC" -ne 0 ]'
  check "HOME 底下沒有任何檔案" 'home_is_empty "$h"'
  check "沒有執行 xcode-select --install" '[ ! -s "$XS_LOG" ]'
}

# --dry-run 承諾不改東西，所以就算有 tty 也不能提議安裝 Command Line Tools。
t_no_clt_dryrun_tty() {
  banner "no-clt-dryrun-tty"
  local h; h="$(new_home)"
  FAKE_NO_CLT=1 run_tty "$h" -- --dry-run
  check "沒有問要不要叫出安裝視窗" '! out_has "要幫你叫出安裝視窗嗎"'
  check "有說缺 Command Line Tools、要先跑 xcode-select --install" 'out_has "xcode-select --install"'
  check "照樣印出事前報告" 'out_has "事前報告"'
  check "沒有執行 xcode-select --install" '[ ! -s "$XS_LOG" ]'
  check "HOME 底下沒有任何檔案" 'home_is_empty "$h"'
}

# 安裝視窗叫不出來（例如被 MDM 擋掉）時要馬上講，不能安靜地等 30 分鐘。
t_no_clt_install_fails() {
  banner "no-clt-install-fails"
  local h start; h="$(new_home)"; start="$(date +%s)"
  FAKE_NO_CLT=1 run_tty "$h" "y" --
  check "exit code 不是 0" '[ "$RC" -ne 0 ]'
  check "有試著叫出安裝視窗" '[ -s "$XS_LOG" ]'
  check "60 秒內就結束，沒有乾等" '[ $(( $(date +%s) - start )) -lt 60 ]'
  check "有說叫不出安裝視窗" 'out_has "叫不出"'
  check "HOME 底下沒有任何檔案" 'home_is_empty "$h"'
}

t_dry_run_report() {
  banner "dry-run-report"
  local h; h="$(new_home)"
  run_notty "$h" --dry-run
  check "exit 0" '[ "$RC" -eq 0 ]'
  check "報告有 macOS" 'out_has "macOS"'
  check "報告有系統版本" 'out_has "$(sw_vers -productVersion)"'
  check "報告有架構" 'out_has "$(uname -m)"'
  check "沒有判定成不支援" '! out_has "不支援這台機器"'
  check "HOME 底下沒有任何檔案" 'home_is_empty "$h"'
  check "沒有呼叫 sudo" 'no_sudo_called'
}

sha_of() { shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1; }

# 去掉腳本管理的區塊，剩下的就是使用者自己的內容。
strip_blocks() {
  awk '/^# >>> zsh-p10k-install: /{skip=1; next} /^# <<< zsh-p10k-install: /{skip=0; next} !skip' "$1"
}

fonts_count() { find "$1/Library/Fonts" -maxdepth 1 -name 'MesloLGS NF *.ttf' 2>/dev/null | wc -l | tr -d ' '; }

# clean 與 rerun 共用同一個 HOME，rerun 單獨跑時會自己先裝一次。
CLEAN_HOME=""
ensure_clean_home() {
  [ -n "$CLEAN_HOME" ] && return 0
  CLEAN_HOME="$(new_home)"
  run_notty "$CLEAN_HOME" --no-chsh
  CLEAN_RC="$RC"
  cp "$OUT" "$WORK/clean-out.txt"
}

t_clean() {
  banner "clean"
  ensure_clean_home
  local h="$CLEAN_HOME"
  RC="$CLEAN_RC"
  check "exit 0" '[ "$RC" -eq 0 ]'
  check "oh-my-zsh 裝好了" '[ -f "$h/.oh-my-zsh/oh-my-zsh.sh" ]'
  check "powerlevel10k 裝好了" '[ -d "$h/.oh-my-zsh/custom/themes/powerlevel10k" ]'
  local p
  for p in zsh-autosuggestions fast-syntax-highlighting zsh-completions; do
    check "外掛 $p 裝好了" '[ -d "$h/.oh-my-zsh/custom/plugins/$p" ]'
  done
  check "~/.p10k.zsh 寫好了" '[ -s "$h/.p10k.zsh" ]'
  check "四個字型在 ~/Library/Fonts" '[ "$(fonts_count "$h")" = 4 ]'
  check "沒有寫到 ~/.local/share/fonts" '[ ! -e "$h/.local/share/fonts" ]'
  check "沒有呼叫 sudo" 'no_sudo_called'
  check "zsh -i 啟動沒有錯誤輸出" \
    '[ -z "$(HOME="$h" TERM=xterm-256color zsh -i -c exit 2>&1 >/dev/null)" ]'
}

t_rerun() {
  banner "rerun"
  ensure_clean_home
  local h="$CLEAN_HOME" a b c
  a="$(sha_of "$h/.zshrc")"; b="$(sha_of "$h/.zshenv")"; c="$(sha_of "$h/.p10k.zsh")"
  run_notty "$h" --no-chsh
  check "第二次 exit 0" '[ "$RC" -eq 0 ]'
  check ".zshrc 沒變" '[ "$(sha_of "$h/.zshrc")" = "$a" ]'
  check ".zshenv 沒變" '[ "$(sha_of "$h/.zshenv")" = "$b" ]'
  check ".p10k.zsh 沒變" '[ "$(sha_of "$h/.p10k.zsh")" = "$c" ]'
}

t_existing_setup() {
  banner "existing-setup"
  local h; h="$(new_home)"
  git clone -q --depth 1 https://github.com/ohmyzsh/ohmyzsh.git "$h/.oh-my-zsh" || { bad "clone oh-my-zsh 失敗"; return; }
  cat > "$h/.zshrc" <<'EOF'
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"
plugins=(git)
source $ZSH/oh-my-zsh.sh
alias mine=true
EOF
  printf '# my p10k\n' > "$h/.p10k.zsh"
  mkdir -p "$h/Library/Fonts"
  printf 'fake' > "$h/Library/Fonts/MesloLGS NF Regular.ttf"
  cp "$h/.zshrc" "$WORK/zshrc.orig"
  local p10k_sha; p10k_sha="$(sha_of "$h/.p10k.zsh")"

  run_notty "$h" --no-chsh
  check "exit 0" '[ "$RC" -eq 0 ]'
  check "報告是附加模式" 'out_has "附加模式"'
  check "~/.p10k.zsh 沒被覆蓋" '[ "$(sha_of "$h/.p10k.zsh")" = "$p10k_sha" ]'
  # 區塊前後會多一行空行當分隔，所以忽略空行再比。
  check ".zshrc 使用者內容沒變（忽略空行）" 'strip_blocks "$h/.zshrc" | diff -qB - "$WORK/zshrc.orig" >/dev/null'
  check "原本的字型檔沒被覆蓋" '[ "$(cat "$h/Library/Fonts/MesloLGS NF Regular.ttf")" = fake ]'
  check "缺的三個字型補上了" '[ "$(fonts_count "$h")" = 4 ]'
}

# 網路不穩：每個字型的第一次下載都失敗，第二次才成功。腳本要自己重試，四個字型都要裝到。
t_font_retry() {
  banner "font-retry"
  local h; h="$(new_home)"
  local flaky="$WORK/flaky"
  mkdir -p "$flaky/seen"
  cat > "$flaky/curl" <<EOF
#!/bin/sh
for a in "\$@"; do
  case "\$a" in
    http*MesloLGS*)
      key="\$(printf '%s' "\$a" | shasum | cut -c1-12)"
      if [ ! -e "$flaky/seen/\$key" ]; then
        : > "$flaky/seen/\$key"
        echo "curl: (56) Failure when receiving data from the peer（假裝斷線）" >&2
        exit 56
      fi ;;
  esac
done
exec /usr/bin/curl "\$@"
EOF
  chmod +x "$flaky/curl"
  PATH="$flaky:$PATH" run_notty "$h" --no-chsh
  check "exit 0" '[ "$RC" -eq 0 ]'
  check "假的 curl 真的讓四個字型各失敗過一次" '[ "$(ls "$flaky/seen" | wc -l | tr -d " ")" = 4 ]'
  check "重試之後四個字型都裝到了" '[ "$(fonts_count "$h")" = 4 ]'
  check "沒有留下 .part" '[ -z "$(find "$h/Library/Fonts" -name "*.part" 2>/dev/null | head -1)" ]'
  check "有說在重試" 'out_has "重試"'
}

# 做一支假的 curl：網址符合 pattern 的一律失敗，其他照常。印出放它的目錄。
failing_font_curl() {
  local d; d="$(mktemp -d "$WORK/failcurl.XXXXXX")"
  cat > "$d/curl" <<EOF
#!/bin/sh
for a in "\$@"; do
  case "\$a" in
    http*$1*) echo "curl: (56) Failure when receiving data from the peer（假裝斷線）" >&2; exit 56 ;;
  esac
done
exec /usr/bin/curl "\$@"
EOF
  chmod +x "$d/curl"
  printf '%s' "$d"
}

# 下載「成功」但內容被換掉：sha256 對不上就不能裝。
t_font_bad_hash() {
  banner "font-bad-hash"
  local h d; h="$(new_home)"; d="$(mktemp -d "$WORK/badcurl.XXXXXX")"
  cat > "$d/curl" <<'EOF'
#!/bin/sh
url=""; out=""; prev=""
for a in "$@"; do
  [ "$prev" = "-o" ] && out="$a"
  case "$a" in http*MesloLGS*) url="$a" ;; esac
  prev="$a"
done
if [ -n "$url" ]; then printf 'not a font' > "$out"; exit 0; fi
exec /usr/bin/curl "$@"
EOF
  chmod +x "$d/curl"
  PATH="$d:$PATH" run_notty "$h" --no-chsh
  check "exit 0" '[ "$RC" -eq 0 ]'
  check "假的字型沒有被裝上" '[ "$(fonts_count "$h")" = 0 ]'
  check "輸出提到 sha256" 'out_has "sha256"'
  check "結尾講 4 個字型沒裝到" 'out_has "4 個字型沒裝到"'
}

# 下載到一半按 Ctrl-C：不能留下 .part。真的 Ctrl-C 時，前景的 curl 和腳本會一起收到 SIGINT。
t_ctrl_c_part() {
  banner "ctrl-c-part"
  local h d; h="$(new_home)"; d="$(mktemp -d "$WORK/intcurl.XXXXXX")"
  cat > "$d/curl" <<'EOF'
#!/bin/sh
url=""; out=""; prev=""
for a in "$@"; do
  [ "$prev" = "-o" ] && out="$a"
  case "$a" in http*MesloLGS*) url="$a" ;; esac
  prev="$a"
done
if [ -n "$url" ]; then
  printf 'half' > "$out"
  kill -INT "$PPID"
  kill -INT $$
  exit 130
fi
exec /usr/bin/curl "$@"
EOF
  chmod +x "$d/curl"
  PATH="$d:$PATH" run_notty "$h" --no-chsh
  check "腳本中斷了（不是 exit 0）" '[ "$RC" -ne 0 ]'
  check "沒有留下 .part" '[ -z "$(find "$h/Library/Fonts" -name "*.part" 2>/dev/null | head -1)" ]'
}

# iTerm2 被 MDM 裝在非標準位置：要靠 Spotlight 找到，不要再問要不要裝一份。
t_iterm2_mdfind() {
  banner "iterm2-mdfind"
  if [ -d /Applications/iTerm.app ]; then skip "這台的 /Applications 已有 iTerm2，測不到 Spotlight 那條路"; return; fi
  local h; h="$(new_home)"; mkdir -p "$h/mdm/iTerm.app" "$h/apps"
  FAKE_MDFIND="$h/mdm/iTerm.app" run_notty "$h" --dry-run
  check "exit 0" '[ "$RC" -eq 0 ]'
  check "報告認得 Spotlight 找到的 iTerm2" 'out_has "$h/mdm/iTerm.app"'
  FAKE_MDFIND="$h/mdm/iTerm.app" ZSH_P10K_APPS_DIR="$h/apps" run_notty "$h" --dry-run
  check "ZSH_P10K_APPS_DIR 有設時不看 Spotlight" '! out_has "mdm/iTerm.app"'
}

# 重試用完還是失敗：結尾不能說字型裝好了，要講幾個沒裝到。
t_font_all_fail() {
  banner "font-all-fail"
  local h d; h="$(new_home)"; d="$(failing_font_curl MesloLGS)"
  PATH="$d:$PATH" run_notty "$h" --no-chsh
  check "exit 0（字型失敗不讓整支腳本失敗）" '[ "$RC" -eq 0 ]'
  check "一個字型都沒裝到" '[ "$(fonts_count "$h")" = 0 ]'
  check "結尾講 4 個字型沒裝到" 'out_has "4 個字型沒裝到"'
  check "結尾沒有說字型已經裝好" '! out_has "已經裝在這台 Mac"'
}

# 只有一個失敗：數字要對，而且照提示重跑一次真的會補上。
t_font_partial_rerun() {
  banner "font-partial-rerun"
  local h d; h="$(new_home)"; d="$(failing_font_curl 'Bold%20Italic')"
  PATH="$d:$PATH" run_notty "$h" --no-chsh
  check "exit 0" '[ "$RC" -eq 0 ]'
  check "裝到三個" '[ "$(fonts_count "$h")" = 3 ]'
  check "結尾講 1 個字型沒裝到" 'out_has "1 個字型沒裝到"'
  run_notty "$h" --no-chsh
  check "重跑 exit 0" '[ "$RC" -eq 0 ]'
  check "重跑後四個都在" '[ "$(fonts_count "$h")" = 4 ]'
  check "重跑後不再說沒裝到" '! out_has "個字型沒裝到"'
  check "重跑後說字型已經裝好" 'out_has "已經裝在這台 Mac"'
}

# 寫一個假的 Homebrew p10k：被 source 時留下記號，才驗得到它真的有載入。
seed_external_p10k() {
  mkdir -p "$1/brew"
  printf 'typeset -g EXTERNAL_P10K=1\n' > "$1/brew/powerlevel10k.zsh-theme"
}

# 已有 oh-my-zsh 設定、p10k 由 Homebrew 載入（附加模式）：不該再 clone 一份用不到的。
t_brew_p10k_append() {
  banner "brew-p10k-append"
  local h; h="$(new_home)"; seed_external_p10k "$h"
  cat > "$h/.zshrc" <<'EOF'
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"
plugins=(git)
source $ZSH/oh-my-zsh.sh
source "$HOME/brew/powerlevel10k.zsh-theme"
EOF
  run_notty "$h" --no-chsh
  check "exit 0" '[ "$RC" -eq 0 ]'
  check "報告是附加模式" 'out_has "附加模式"'
  check "報告說不另外 clone" 'out_has "不另外 clone"'
  check "沒有多 clone 一份 p10k" '[ ! -e "$h/.oh-my-zsh/custom/themes/powerlevel10k" ]'
  check "外部的 p10k 真的有載入" \
    '[ "$(HOME="$h" TERM=xterm-256color zsh -i -c "print -r -- \$EXTERNAL_P10K" 2>/dev/null | tail -1)" = 1 ]'
}

# 沒有 oh-my-zsh、只有 source 外部 p10k（完整模式）：oh-my-zsh 不能再去找不存在的主題。
t_brew_p10k_full() {
  banner "brew-p10k-full"
  local h err; h="$(new_home)"; seed_external_p10k "$h"
  printf 'source "$HOME/brew/powerlevel10k.zsh-theme"\n' > "$h/.zshrc"
  run_notty "$h" --no-chsh
  check "exit 0" '[ "$RC" -eq 0 ]'
  check "報告是完整模式" 'out_has "完整模式"'
  check "沒有多 clone 一份 p10k" '[ ! -e "$h/.oh-my-zsh/custom/themes/powerlevel10k" ]'
  err="$(HOME="$h" TERM=xterm-256color zsh -i -c exit 2>&1 >/dev/null)"
  check "oh-my-zsh 沒抱怨找不到主題" '! printf "%s" "$err" | grep -q "not found"'
  check "外部的 p10k 真的有載入" \
    '[ "$(HOME="$h" TERM=xterm-256color zsh -i -c "print -r -- \$EXTERNAL_P10K" 2>/dev/null | tail -1)" = 1 ]'
}

# 這兩種看起來像外部載入，其實不是，p10k 還是要 clone。dry-run 看報告就夠了。
t_brew_p10k_not_really() {
  banner "brew-p10k-not-really"
  local h; h="$(new_home)"
  printf '# source /opt/homebrew/share/powerlevel10k/powerlevel10k.zsh-theme\n' > "$h/.zshrc"
  run_notty "$h" --dry-run
  check "註解掉的 source 不算" '! out_has "不另外 clone"'
  h="$(new_home)"
  cat > "$h/.zshrc" <<'EOF'
ZSH_THEME="powerlevel10k/powerlevel10k"
source /opt/homebrew/share/powerlevel10k/powerlevel10k.zsh-theme
EOF
  run_notty "$h" --dry-run
  check "ZSH_THEME 還指著 clone 的路徑就要 clone" '! out_has "不另外 clone"'
  # 跨機器共用的 dotfiles：這台沒有 Homebrew，那行 source 根本不會生效。
  h="$(new_home)"
  printf '[[ -r /opt/nowhere/powerlevel10k.zsh-theme ]] && source /opt/nowhere/powerlevel10k.zsh-theme\n' > "$h/.zshrc"
  run_notty "$h" --dry-run
  check "source 的檔案不存在就要 clone" '! out_has "不另外 clone"'
  # 路徑要跑指令才知道：沒辦法判斷，相信使用者寫的。
  h="$(new_home)"
  printf 'source $(brew --prefix)/share/powerlevel10k/powerlevel10k.zsh-theme\n' > "$h/.zshrc"
  run_notty "$h" --dry-run
  check "路徑解析不了時相信使用者" 'out_has "不另外 clone"'
}

t_uninstall_hint() {
  banner "uninstall-hint"
  local h; h="$(new_home)"
  run_notty "$h" --uninstall
  check "exit 0" '[ "$RC" -eq 0 ]'
  check "沒有叫人 rm -rf ~/Library/Fonts" '! grep -qE "rm -rf .*Library/Fonts" "$OUT"'
  check "字型那行指名 MesloLGS NF" 'grep -E "Library/Fonts" "$OUT" | grep -q "MesloLGS"'
  check "有提醒本來就有的字型要保留" 'out_has "之前就有"'
  check "沒有 getent 的錯誤" '! out_has "getent"'
  check "login shell 有值" 'grep -E "login shell 目前是 /" "$OUT" >/dev/null'
  check "刻意保留清單有 iTerm2 profile" 'out_has "zsh-p10k.json"'
}

# ---------------------------------------------------------------------------
# iTerm2 profile：用一個假的 iTerm.app 目錄假裝有裝，不用真的下載
# ---------------------------------------------------------------------------

PROFILE_REL="Library/Application Support/iTerm2/DynamicProfiles/zsh-p10k.json"
EXPECTED_GUID="$(grep -o '^ITERM2_PROFILE_GUID="[^"]*"' "$INSTALLER" | cut -d'"' -f2)"

fake_iterm_home() {
  local h; h="$(new_home)"
  mkdir -p "$h/apps/iTerm.app"
  printf '%s\n' "$h"
}

plist_get() { plutil -extract "$2" raw -o - "$1" 2>/dev/null; }

t_profile_yes() {
  banner "profile-yes"
  local h; h="$(fake_iterm_home)"
  ZSH_P10K_APPS_DIR="$h/apps" run_notty "$h" --iterm2-profile --no-chsh
  local f="$h/$PROFILE_REL"
  check "exit 0" '[ "$RC" -eq 0 ]'
  check "profile 檔存在" '[ -f "$f" ]'
  # plutil -lint 不吃 JSON，用 -convert 驗證 iTerm2 讀得懂這份 property list。
  check "plutil 解析得了" 'plutil -convert xml1 -o /dev/null "$f"'
  check "Name 正確" '[ "$(plist_get "$f" Profiles.0.Name)" = "zsh-p10k (MesloLGS NF)" ]'
  check "字型是 MesloLGS-NF-Regular 13" '[ "$(plist_get "$f" "Profiles.0.Normal Font")" = "MesloLGS-NF-Regular 13" ]'
  check "Guid 是腳本裡的常數" '[ -n "$EXPECTED_GUID" ] && [ "$(plist_get "$f" Profiles.0.Guid)" = "$EXPECTED_GUID" ]'
  check "有教怎麼 Set as Default" 'out_has "Set as Default"'
}

t_profile_keep() {
  banner "profile-keep"
  local h; h="$(fake_iterm_home)"
  mkdir -p "$(dirname "$h/$PROFILE_REL")"
  printf '{"Profiles":[{"Name":"mine","Guid":"x"}]}\n' > "$h/$PROFILE_REL"
  local before; before="$(sha_of "$h/$PROFILE_REL")"
  ZSH_P10K_APPS_DIR="$h/apps" run_notty "$h" --iterm2-profile --no-chsh
  check "exit 0" '[ "$RC" -eq 0 ]'
  check "既有 profile 檔沒被改" '[ "$(sha_of "$h/$PROFILE_REL")" = "$before" ]'
  check "有說已存在" 'grep -F "zsh-p10k.json" "$OUT" | grep -qF "已存在"'
}

t_profile_notty() {
  banner "profile-notty"
  local h; h="$(fake_iterm_home)"
  ZSH_P10K_APPS_DIR="$h/apps" run_notty "$h" --no-chsh
  check "exit 0" '[ "$RC" -eq 0 ]'
  check "沒 tty 時不建立 profile" '[ ! -e "$h/$PROFILE_REL" ]'
  check "報告有教 --iterm2-profile" 'out_has "--iterm2-profile"'
}

t_profile_tty_yes() {
  banner "profile-tty-yes"
  local h; h="$(fake_iterm_home)"
  # 先回答 profile 那題 y，再按 Enter 讓 confirm_or_exit 繼續。
  ZSH_P10K_APPS_DIR="$h/apps" run_tty "$h" "y" "" -- --no-chsh
  check "exit 0" '[ "$RC" -eq 0 ]'
  check "有問 profile 那題" 'out_has "要幫你在 iTerm2 加一個"'
  check "答 y 之後 profile 檔存在" '[ -f "$h/$PROFILE_REL" ]'
}

# ---------------------------------------------------------------------------
# iTerm2 安裝：真的下載官方 zip，但裝到暫存目錄，不碰 /Applications
# ---------------------------------------------------------------------------

t_iterm2_install() {
  banner "iterm2-install"
  local h; h="$(new_home)"; mkdir -p "$h/apps"
  ZSH_P10K_APPS_DIR="$h/apps" run_notty "$h" --iterm2 --no-iterm2-profile --no-chsh
  local app="$h/apps/iTerm.app"
  check "exit 0" '[ "$RC" -eq 0 ]'
  check "iTerm.app 裝好了" '[ -d "$app" ]'
  check "codesign 驗證通過" 'codesign --verify --deep --strict "$app" 2>/dev/null'
  check "版本是 3.7.7" '[ "$(defaults read "$app/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null)" = 3.7.7 ]'
  check "沒有留下 zip" '[ -z "$(find "$h" "${TMPDIR:-/tmp}" -maxdepth 2 -name "iTerm2-*.zip" 2>/dev/null | head -1)" ]'
}

t_bad_hash() {
  banner "bad-hash"
  local h; h="$(new_home)"; mkdir -p "$h/apps"
  ZSH_P10K_ITERM2_SHA256_OVERRIDE="$(printf '0%.0s' $(seq 64))" ZSH_P10K_APPS_DIR="$h/apps" \
    run_notty "$h" --iterm2 --no-chsh
  check "exit 0（不讓整支腳本失敗）" '[ "$RC" -eq 0 ]'
  check "輸出提到 sha256" 'out_has "sha256"'
  check "沒有裝上 iTerm.app" '[ ! -e "$h/apps/iTerm.app" ]'
  check "oh-my-zsh 照樣裝好" '[ -f "$h/.oh-my-zsh/oh-my-zsh.sh" ]'
}

t_iterm2_notty() {
  banner "iterm2-notty"
  local h; h="$(new_home)"; mkdir -p "$h/apps"
  ZSH_P10K_APPS_DIR="$h/apps" run_notty "$h" --no-chsh
  check "exit 0" '[ "$RC" -eq 0 ]'
  check "沒 tty 時不裝 iTerm2" '[ ! -e "$h/apps/iTerm.app" ]'
  check "報告有教 --iterm2" 'grep -E -- "--iterm2([^-]|$)" "$OUT" >/dev/null'
}

ALL_SCENARIOS="no-clt-notty no-clt-tty-no no-clt-dryrun-tty no-clt-install-fails dry-run-report
clean rerun existing-setup uninstall-hint font-retry font-all-fail font-partial-rerun
font-bad-hash ctrl-c-part iterm2-mdfind
brew-p10k-append brew-p10k-full brew-p10k-not-really
profile-yes profile-keep profile-notty profile-tty-yes iterm2-install bad-hash iterm2-notty"

run_scenario() {
  case "$1" in
    no-clt-notty)   t_no_clt_notty ;;
    no-clt-tty-no)  t_no_clt_tty_no ;;
    no-clt-dryrun-tty) t_no_clt_dryrun_tty ;;
    no-clt-install-fails) t_no_clt_install_fails ;;
    dry-run-report) t_dry_run_report ;;
    clean)          t_clean ;;
    rerun)          t_rerun ;;
    existing-setup) t_existing_setup ;;
    uninstall-hint) t_uninstall_hint ;;
    font-retry)     t_font_retry ;;
    font-all-fail)  t_font_all_fail ;;
    font-bad-hash)  t_font_bad_hash ;;
    ctrl-c-part)    t_ctrl_c_part ;;
    iterm2-mdfind)  t_iterm2_mdfind ;;
    font-partial-rerun) t_font_partial_rerun ;;
    brew-p10k-append) t_brew_p10k_append ;;
    brew-p10k-full) t_brew_p10k_full ;;
    brew-p10k-not-really) t_brew_p10k_not_really ;;
    profile-yes)    t_profile_yes ;;
    profile-keep)   t_profile_keep ;;
    profile-notty)  t_profile_notty ;;
    profile-tty-yes) t_profile_tty_yes ;;
    iterm2-install) t_iterm2_install ;;
    bad-hash)       t_bad_hash ;;
    iterm2-notty)   t_iterm2_notty ;;
    *) echo "不認得的情境：$1" >&2; FAIL=$((FAIL+1)) ;;
  esac
}

if [ "$#" -eq 0 ]; then
  # shellcheck disable=SC2086
  set -- $ALL_SCENARIOS
fi
for s in "$@"; do
  run_scenario "$s"
done

printf '\n%d passed, %d failed, %d skipped\n' "$PASS" "$FAIL" "$SKIP"
[ "$FAIL" -eq 0 ]
