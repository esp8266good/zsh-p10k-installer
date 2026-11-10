#!/usr/bin/env bash
# tests/windows-smoke.sh：在 Windows 的 Git Bash 上用暫存 HOME 測安裝腳本，不碰真的 home。
#
#   bash tests/windows-smoke.sh              跑全部情境
#   bash tests/windows-smoke.sh clean rerun  只跑指定的情境
#
# 字型的登錄檔寫在測試專用的機碼（ZSH_P10K_WIN_FONT_KEY），字型檔寫在暫存的 LOCALAPPDATA，
# 跑完都會清掉。要測的腳本預設是 dist/install-zsh-p10k.sh，可以用 ZSH_P10K_INSTALLER 換掉。

# RC、h 這些變數是在 check 的 eval 字串裡用的，shellcheck 看不到。
# shellcheck disable=SC2034
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
INSTALLER="${ZSH_P10K_INSTALLER:-$HERE/../dist/install-zsh-p10k.sh}"
[ -f "$INSTALLER" ] || { echo "找不到 $INSTALLER，先跑 ./build.sh" >&2; exit 2; }
case "$(uname -s)" in
  MINGW*|MSYS*) ;;
  *) echo "這支測試只能在 Windows 的 Git Bash 上跑。" >&2; exit 2 ;;
esac

PASS=0
FAIL=0
ok()   { printf '  \033[32mPASS\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
DUMPED=0
bad()  {
  printf '  \033[31mFAIL\033[0m %s\n' "$1"; FAIL=$((FAIL+1))
  if [ "$DUMPED" -eq 0 ] && [ -s "${OUT:-}" ]; then
    DUMPED=1
    printf '    ---- 安裝腳本的 WARN / FAIL ----\n'
    grep -aE '\[(WARN|FAIL)\]|curl: ' "$OUT" | sed 's/^/    | /'
    printf '    ---- 安裝腳本最後 10 行 ----\n'
    tail -10 "$OUT" | sed 's/^/    | /'
  fi
}
check(){ if eval "$2"; then ok "$1"; else bad "$1"; fi; }
banner() { DUMPED=0; printf '\n\033[1m=== Windows 情境：%s ===\033[0m\n' "$1"; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/zsh-p10k-winsmoke.XXXXXX")"
FONT_KEY="HKCU\\Software\\zsh-p10k-smoke-$$"
cleanup() {
  MSYS_NO_PATHCONV=1 reg delete "$FONT_KEY" /f >/dev/null 2>&1
  rm -rf "$WORK"
}
trap cleanup EXIT

OUT="$WORK/out.txt"
RC=0
SUDO_LOG="$WORK/sudo.log"

# Win11 內建 sudo.exe，安裝腳本一次都不該叫它（會跳 UAC 視窗）。
mkdir -p "$WORK/bin"
cat > "$WORK/bin/sudo" <<EOF
#!/bin/sh
echo "sudo \$*" >> "$SUDO_LOG"
exit 1
EOF
chmod +x "$WORK/bin/sudo"

# Git for Windows 出廠的 core.autocrlf 是 true。用獨立的 global 設定把它固定住，
# 這樣不管哪台機器都測得到換行被轉掉的情況。
cat > "$WORK/gitconfig" <<EOF
[core]
	autocrlf = true
EOF

new_home() { mktemp -d "$WORK/home.XXXXXX"; }

# run_gb <home> [安裝腳本參數]...：沒有 tty 的跑法，跟 ssh host command 一樣。
run_gb() {
  local home="$1"; shift
  : > "$SUDO_LOG"
  RC=0
  env HOME="$home" LOCALAPPDATA="$(cygpath -w "$home/appdata")" \
    GIT_CONFIG_GLOBAL="$WORK/gitconfig" ZSH_P10K_WIN_FONT_KEY="${RUN_FONT_KEY:-$FONT_KEY}" \
    PATH="$WORK/bin:$PATH" bash "${RUN_TOOL:-$INSTALLER}" "$@" < /dev/null > "$OUT" 2>&1 || RC=$?
}

out_has() { grep -qaF -- "$1" "$OUT"; }
no_sudo_called() { [ ! -s "$SUDO_LOG" ]; }
sha_of() { sha256sum "$1" | cut -d' ' -f1; }
fonts_dir() { printf '%s/appdata/Microsoft/Windows/Fonts' "$1"; }
fonts_count() { find "$(fonts_dir "$1")" -maxdepth 1 -name 'MesloLGS NF *.ttf' 2>/dev/null | wc -l | tr -d ' '; }
font_values() { MSYS_NO_PATHCONV=1 reg query "$FONT_KEY" 2>/dev/null | grep -c 'MesloLGS NF .*(TrueType)'; }
zsh_exe() { printf '%s/.local/zsh-msys/usr/bin/zsh.exe' "$1"; }
wt_fragment() { printf '%s/appdata/Microsoft/Windows Terminal/Fragments/zsh-p10k-install/zsh-p10k.json' "$1"; }
# wt_field <home> <PowerShell 運算式>：用 PowerShell 的 JSON 解析器讀 fragment，WT 讀不懂的 JSON 它也讀不懂。
wt_field() {
  local f; f="$(cygpath -w "$(wt_fragment "$1")")"
  powershell.exe -NoProfile -Command "\$j = [IO.File]::ReadAllText('$f', [Text.Encoding]::UTF8) | ConvertFrom-Json; $2" 2>/dev/null | tr -d '\r'
}
# 把 fragment 裡的 commandline 原封不動放進 .bat 執行，跟 Windows Terminal 開分頁一樣交給 CreateProcess。
# stdin 餵指令進去，zsh 沒有 tty 時會從 stdin 讀指令。
wt_launch() {
  local h="$1" bat="$WORK/wt-launch.bat"
  { printf '@echo off\r\n'; wt_field "$h" '$j.profiles[0].commandline'; printf '\r\n'; } > "$bat"
  printf '%s\n' "$2" | HOME="$h" cmd.exe //c "$(cygpath -w "$bat")" 2>&1 | tr -d '\r'
}
# 用裝好的 zsh 在暫存 HOME 跑一段指令，只留 stdout。
in_zsh() { local h="$1"; shift; HOME="$h" TERM=xterm-256color "$(zsh_exe "$h")" "$@" 2>/dev/null; }
crlf_files() {
  # 裝進去的 zsh 腳本只要有 CR 就會整個壞掉，grep 出有 CR 的檔。
  find "$1/.oh-my-zsh" -type f \( -name '*.zsh' -o -name '*.zsh-theme' \) -not -path '*/.git/*' -print0 \
    | xargs -0 grep -lU "$(printf '\r')" 2>/dev/null | wc -l | tr -d ' '
}

CLEAN_HOME=""
ensure_clean_home() {
  [ -n "$CLEAN_HOME" ] && return 0
  CLEAN_HOME="$(new_home)"
  run_gb "$CLEAN_HOME"
}

# ---------------------------------------------------------------------------
# 情境
# ---------------------------------------------------------------------------

t_dry_run() {
  banner "dry-run"
  local h; h="$(new_home)"
  run_gb "$h" --dry-run
  check "exit 0" '[ "$RC" -eq 0 ]'
  check "報告認得 Git Bash" 'out_has "Git Bash"'
  check "報告講 zsh 會裝在使用者目錄" 'out_has ".local/zsh-msys"'
  check "沒有動到 HOME" '[ -z "$(find "$h" -mindepth 1 | head -1)" ]'
  check "沒有呼叫 sudo" 'no_sudo_called'
}

t_clean() {
  banner "clean"
  ensure_clean_home
  local h="$CLEAN_HOME" err
  check "exit 0" '[ "$RC" -eq 0 ]'
  check "zsh.exe 裝好了" '[ -x "$(zsh_exe "$h")" ]'
  check "沒有呼叫 sudo" 'no_sudo_called'
  check "zsh 的動態模組載得起來" '[ "$(in_zsh "$h" -c "zmodload zsh/datetime && print ok")" = ok ]'
  check "zsh 的內建函式找得到" '[ "$(in_zsh "$h" -c "autoload -Uz is-at-least && is-at-least 5.0 && print ok")" = ok ]'
  check "裝進去的 zsh 腳本沒有被轉成 CRLF" '[ "$(crlf_files "$h")" = 0 ]'
  check "四個字型在使用者字型目錄" '[ "$(fonts_count "$h")" = 4 ]'
  check "四個字型都登錄了" '[ "$(font_values)" = 4 ]'
  check ".bash_profile 有 auto-start hook" 'grep -q "zsh-p10k-install auto start" "$h/.bash_profile"'
  err="$(HOME="$h" TERM=xterm-256color "$(zsh_exe "$h")" -i -c exit 2>&1 >/dev/null)"
  check "zsh -i 啟動沒有錯誤輸出" '[ -z "$err" ]'
  check "p10k 真的有載入" '[ "$(in_zsh "$h" -i -c "print -r -- \${+functions[p10k]}" | tail -1)" = 1 ]'
  check "字型目錄沒有留下 .part" '[ -z "$(find "$(fonts_dir "$h")" -name "*.part" | head -1)" ]'
  check "沒有留下 zsh-msys.new" '[ ! -e "$h/.local/zsh-msys.new" ]'
  check "報告沒有叫人跑不存在的 chsh" '! out_has "chsh -s"'
}

# 使用者名稱有空白的帳號，HOME 就長這樣。
t_spaced_home() {
  banner "spaced-home"
  local h="$WORK/te st home" err
  mkdir -p "$h"
  run_gb "$h"
  check "exit 0" '[ "$RC" -eq 0 ]'
  check "zsh.exe 裝好了" '[ -x "$(zsh_exe "$h")" ]'
  check "四個字型都在" '[ "$(fonts_count "$h")" = 4 ]'
  err="$(HOME="$h" TERM=xterm-256color "$(zsh_exe "$h")" -i -c exit 2>&1 >/dev/null)"
  check "zsh -i 啟動沒有錯誤輸出" '[ -z "$err" ]'
  [ -z "$err" ] || printf '%s\n' "$err" | head -8 | sed 's/^/    | /'
  check "沒有多餘的路徑警告" '! out_has "非 ASCII"'
}

# 中文帳號：zsh 的 zcompile、sysopen 用絕對路徑寫不了這種目錄，MSYS2 版的 autoload -R
# 也會壞，p10k 和 compinit 每開一次視窗就印一串錯誤。安裝腳本要把這些都處理掉。
# 路徑混了中文和泰文：不管這台 Windows 用哪個字碼頁，都一定有字元不在字碼頁裡。
t_nonascii_home() {
  banner "nonascii-home"
  local h="$WORK/使用者ผู้ใช้" err
  mkdir -p "$h"
  run_gb "$h"
  check "exit 0" '[ "$RC" -eq 0 ]'
  check "事前有提醒" 'out_has "非 ASCII"'
  check "zsh.exe 裝好了" '[ -x "$(zsh_exe "$h")" ]'
  check "四個字型都在" '[ "$(fonts_count "$h")" = 4 ]'
  check "p10k 還是載得起來" '[ "$(in_zsh "$h" -i -c "print -r -- \${+functions[p10k]}" | tail -1)" = 1 ]'
  err="$(HOME="$h" TERM=xterm-256color "$(zsh_exe "$h")" -i -c exit 2>&1 >/dev/null)"
  check "zsh -i 啟動沒有錯誤輸出" '[ -z "$err" ]'
  [ -z "$err" ] || printf '%s\n' "$err" | head -5 | sed 's/^/    | /'
  # 沒有 tty 時 p10k 不會自己跑 prompt 之後的 dump，這裡直接叫那兩個函式。
  err="$(HOME="$h" TERM=xterm-256color "$(zsh_exe "$h")" -i -c '_p9k_dump_instant_prompt; _p9k_dump_state' 2>&1 >/dev/null)"
  check "p10k 寫 cache 時沒有錯誤輸出" '[ -z "$err" ]'
  [ -z "$err" ] || printf '%s\n' "$err" | head -5 | sed 's/^/    | /'
  check "Windows Terminal 的 commandline 開得起 zsh" 'wt_launch "$h" "print -r -- ZV=\$ZSH_VERSION" | grep -q "^ZV=5\."'
}

# zsh 套件的內容被換掉：要停下來，不能留下裝一半的 zsh。
t_bad_zsh_hash() {
  banner "bad-zsh-hash"
  local h d real_curl; h="$(new_home)"; d="$WORK/badzsh"; mkdir -p "$d"
  real_curl="$(command -v curl)"
  cat > "$d/curl" <<EOF
#!/bin/sh
url=""; out=""; prev=""
for a in "\$@"; do
  [ "\$prev" = "-o" ] && out="\$a"
  case "\$a" in http*msys/x86_64/zsh-*) url="\$a" ;; esac
  prev="\$a"
done
if [ -n "\$url" ]; then printf 'not a package' > "\$out"; exit 0; fi
exec "$real_curl" "\$@"
EOF
  chmod +x "$d/curl"
  mkdir -p "$WORK/badzsh-tmp"
  TMPDIR="$WORK/badzsh-tmp" PATH="$d:$PATH" run_gb "$h"
  check "停下來（不是 exit 0）" '[ "$RC" -ne 0 ]'
  check "輸出提到 sha256" 'out_has "sha256"'
  check "沒有裝半套 zsh" '[ ! -e "$h/.local/zsh-msys" ] && [ ! -e "$h/.local/zsh-msys.new" ]'
  check "下載的暫存檔有清掉" '[ -z "$(find "$WORK/badzsh-tmp" -name "zstd.zip*" -o -name "zsh.tar.zst*" | head -1)" ]'
}

# MSYS2 把寫死的那個 zsh 版本下架了：兩個網址都 404。要講清楚怎麼辦，不能只說下載失敗。
t_zsh_pkg_gone() {
  banner "zsh-pkg-gone"
  local h d real_curl; h="$(new_home)"; d="$WORK/gonezsh"; mkdir -p "$d"
  real_curl="$(command -v curl)"
  cat > "$d/curl" <<EOF
#!/bin/sh
for a in "\$@"; do
  case "\$a" in http*msys/x86_64/zsh-*) echo "curl: (22) The requested URL returned error: 404" >&2; exit 22 ;; esac
done
exec "$real_curl" "\$@"
EOF
  chmod +x "$d/curl"
  PATH="$d:$PATH" run_gb "$h" --no-fonts
  check "停下來（不是 exit 0）" '[ "$RC" -ne 0 ]'
  check "講可能是版本被下架" 'out_has "下架"'
  check "給最新版安裝腳本的網址" 'out_has "releases/latest"'
  check "沒有裝半套 zsh" '[ ! -e "$h/.local/zsh-msys" ] && [ ! -e "$h/.local/zsh-msys.new" ]'
}

# 防毒軟體剛掃完 zsh.exe 還鎖著，換上新 zsh 的 mv 第一次失敗：要等一下重試，不能留下沒有 zsh 的狀態。
t_zsh_mv_retry() {
  banner "zsh-mv-retry"
  local h d; h="$(new_home)"; d="$WORK/lockmv"; mkdir -p "$d"
  cat > "$d/mv" <<EOF
#!/bin/sh
case "\$1" in
  *zsh-msys.new)
    if [ ! -e "$d/failed" ]; then : > "$d/failed"; echo "mv: Permission denied" >&2; exit 1; fi ;;
esac
exec /usr/bin/mv "\$@"
EOF
  chmod +x "$d/mv"
  PATH="$d:$PATH" run_gb "$h" --no-fonts
  check "mv 真的失敗過一次" '[ -e "$d/failed" ]'
  check "exit 0" '[ "$RC" -eq 0 ]'
  check "zsh.exe 裝好了" '[ -x "$(zsh_exe "$h")" ]'
  check "沒有留下 zsh-msys.new" '[ ! -e "$h/.local/zsh-msys.new" ]'
}

# 字型檔在、但登錄失敗：字型清單看不到，不能說裝好了。
t_reg_fail() {
  banner "reg-fail"
  ensure_clean_home
  local h="$CLEAN_HOME"
  RUN_FONT_KEY='HKXX\Software\nope' run_gb "$h"
  check "exit 0" '[ "$RC" -eq 0 ]'
  check "結尾講 4 個字型沒裝到" 'out_has "4 個字型沒裝到"'
  check "結尾沒有說字型已經裝好" '! out_has "已經裝在這個 Windows 帳號"'
}

# 明講不裝字型：結尾不能說裝好了。
t_no_fonts_claim() {
  banner "no-fonts-claim"
  ensure_clean_home
  run_gb "$CLEAN_HOME" --no-fonts
  check "exit 0" '[ "$RC" -eq 0 ]'
  check "結尾沒有說字型已經裝好" '! out_has "已經裝在這個 Windows 帳號"'
  check "結尾講是 --no-fonts 略過的" 'out_has "--no-fonts"'
}

# --no-chsh 不裝 hook，zsh 又不在 PATH，要告訴人怎麼進 zsh。
t_no_chsh_hint() {
  banner "no-chsh-hint"
  ensure_clean_home
  run_gb "$CLEAN_HOME" --no-chsh
  check "exit 0" '[ "$RC" -eq 0 ]'
  check "結尾有教手動進 zsh" 'out_has "手動進 zsh"'
}

# 使用者本來就有 .bash_profile：裝完、重跑、解除安裝之後要跟原檔每個 byte 都一樣。
t_profile_restored() {
  banner "profile-restored"
  local h; h="$(new_home)"
  printf 'export MINE=1\n\n# keep\n' > "$h/.bash_profile"
  cp "$h/.bash_profile" "$WORK/profile.orig"
  run_gb "$h"
  run_gb "$h"
  check "裝好有 hook" 'grep -q "zsh-p10k-install auto start" "$h/.bash_profile"'
  run_gb "$h" --uninstall
  check "解除安裝後與原檔相同" 'cmp -s "$WORK/profile.orig" "$h/.bash_profile"'
}

# Git Bash 的 login shell 優先讀 .bash_profile。只有 .bash_login 時，
# 新生的 .bash_profile 會讓它失效。
t_keep_bash_login() {
  banner "keep-bash-login"
  local h; h="$(new_home)"
  printf 'export FROM_LOGIN=yes\n' > "$h/.bash_login"
  run_gb "$h"
  check "exit 0" '[ "$RC" -eq 0 ]'
  check "login bash 還讀得到 .bash_login" \
    '[ "$(HOME="$h" bash -lc "echo \$FROM_LOGIN" 2>/dev/null | tail -1)" = yes ]'
}

t_rerun() {
  banner "rerun"
  ensure_clean_home
  local h="$CLEAN_HOME" a b p
  a="$(sha_of "$h/.zshrc")"; b="$(sha_of "$h/.zshenv")"; p="$(sha_of "$h/.bash_profile")"
  run_gb "$h"
  check "第二次 exit 0" '[ "$RC" -eq 0 ]'
  check ".bash_profile 沒變" '[ "$(sha_of "$h/.bash_profile")" = "$p" ]'
  check ".zshrc 沒變" '[ "$(sha_of "$h/.zshrc")" = "$a" ]'
  check ".zshenv 沒變" '[ "$(sha_of "$h/.zshenv")" = "$b" ]'
  check "用既有的 zsh，不重新下載" 'out_has "使用既有的 zsh"'
  check "hook 只有一份" '[ "$(grep -c "BEGIN zsh-p10k-install auto start" "$h/.bash_profile")" = 1 ]'
  check "Windows Terminal 設定檔沒有重寫" '! out_has "已寫入 Windows Terminal"'
  # hook 一樣就不要拆掉重寫，不然每重跑一次就多一份 .bash_profile 備份。
  check "沒有再備份 .bash_profile" '! grep -qaE "已備份 .*\.bash_profile" "$OUT"'
  check "沒有印「已移除 hook」" '! out_has "已移除 ~/.bash_profile"'
}

# Git Bash 的 login shell 只讀 .bash_profile。使用者只有 .bashrc 時，
# 憑空生一個 .bash_profile 會讓 .bashrc 再也讀不到。
t_keep_bashrc() {
  banner "keep-bashrc"
  local h; h="$(new_home)"
  printf 'export FROM_BASHRC=yes\n' > "$h/.bashrc"
  run_gb "$h"
  check "exit 0" '[ "$RC" -eq 0 ]'
  # 這條要在跑 login bash 之前：Git Bash 的 /etc/profile.d 可能會自己補一個 .bash_profile。
  check "新的 .bash_profile 有 source .bashrc" 'grep -q "\.bashrc" "$h/.bash_profile"'
  check "login bash 還讀得到 .bashrc" \
    '[ "$(HOME="$h" bash -lc "echo \$FROM_BASHRC" 2>/dev/null | tail -1)" = yes ]'
}

# Git 目錄裡已經有 zsh（有人照網路教學手動裝過）：不要再裝一份。
t_existing_zsh() {
  banner "existing-zsh"
  local h d; h="$(new_home)"; d="$WORK/hasz"; mkdir -p "$d"
  printf '#!/bin/sh\necho "zsh 5.9"\n' > "$d/zsh"; chmod +x "$d/zsh"
  PATH="$d:$PATH" run_gb "$h" --dry-run
  check "exit 0" '[ "$RC" -eq 0 ]'
  check "報告不說要裝到使用者目錄" '! out_has ".local/zsh-msys"'
}

# 字型全部下載失敗：要講實話，也不能登錄不存在的檔案。
t_font_fail() {
  banner "font-fail"
  local h d; h="$(new_home)"; d="$WORK/failcurl"; mkdir -p "$d"
  local real_curl; real_curl="$(command -v curl)"
  cat > "$d/curl" <<EOF
#!/bin/sh
for a in "\$@"; do
  case "\$a" in
    http*MesloLGS*) echo "curl: (56) simulated failure" >&2; exit 56 ;;
  esac
done
exec "$real_curl" "\$@"
EOF
  chmod +x "$d/curl"
  MSYS_NO_PATHCONV=1 reg delete "$FONT_KEY" /f >/dev/null 2>&1
  PATH="$d:$PATH" run_gb "$h"
  check "exit 0" '[ "$RC" -eq 0 ]'
  check "結尾講 4 個字型沒裝到" 'out_has "4 個字型沒裝到"'
  check "沒有登錄不存在的字型" '[ "$(font_values)" = 0 ]'
}

t_uninstall() {
  banner "uninstall"
  ensure_clean_home
  local h="$CLEAN_HOME"
  run_gb "$h" --uninstall
  check "exit 0" '[ "$RC" -eq 0 ]'
  check ".zshrc 區段已移除" '! grep -q "zsh-p10k-install:" "$h/.zshrc"'
  check ".zshenv 區段已移除" '! grep -q "zsh-p10k-install:" "$h/.zshenv"'
  check "hook 已移除" '! grep -q "zsh-p10k-install auto start" "$h/.bash_profile"'
  check "有教怎麼刪 zsh" 'out_has "rm -rf ~/.local/zsh-msys"'
  check "有提醒本來就有的字型要保留" 'out_has "之前就有"'
  check "沒有教 chsh（Git Bash 沒有這個指令）" '! out_has "chsh"'
  check "Windows Terminal 設定檔已移除" '[ ! -e "$(wt_fragment "$h")" ] && [ ! -d "$(dirname "$(wt_fragment "$h")")" ]'
  check "zsh-p10k 指令已移除" '[ ! -e "$h/.local/bin/zsh-p10k" ]'
}

# Windows Terminal 多一個「Git Bash (zsh)」設定檔，字型是 MesloLGS NF。用 fragment，不碰 settings.json。
t_wt_profile() {
  banner "wt-profile"
  ensure_clean_home
  local h="$CLEAN_HOME" f; f="$(wt_fragment "$h")"
  check "fragment 檔在" '[ -f "$f" ]'
  check "沒有 BOM" '[ "$(head -c 3 "$f" | od -An -tx1 | tr -d " ")" != "efbbbf" ]'
  check "名稱是 Git Bash (zsh)" '[ "$(wt_field "$h" "\$j.profiles[0].name")" = "Git Bash (zsh)" ]'
  check "GUID 是固定的那個" '[ "$(wt_field "$h" "\$j.profiles[0].guid")" = "{ad4e1882-2152-55a3-950c-b935933e73df}" ]'
  check "字型是 MesloLGS NF" '[ "$(wt_field "$h" "\$j.profiles[0].font.face")" = "MesloLGS NF" ]'
  local icon; icon="$(wt_field "$h" "\$j.profiles[0].icon")"
  check "icon 指到 Git 真的有的圖示檔" '[ -n "$icon" ] && [ -f "$(cygpath -u "$icon")" ]'
  check "commandline 開得起 zsh" 'wt_launch "$h" "print -r -- ZV=\$ZSH_VERSION" | grep -q "^ZV=5\."'
  check "SHELL 指向 zsh" 'wt_launch "$h" "print -r -- SH=\$SHELL" | grep -q "^SH=.*zsh.exe$"'
  check "結尾有講 Windows Terminal 的設定檔" 'out_has "Git Bash (zsh)"'
  local h2; h2="$(new_home)"
  run_gb "$h2" --no-fonts
  check "--no-fonts 時不指定字型（不然 WT 會跳找不到字型）" \
    '[ "$(wt_field "$h2" "\$j.profiles[0].name")" = "Git Bash (zsh)" ] && [ -z "$(wt_field "$h2" "\$j.profiles[0].font.face")" ]'
  check "--dry-run 不寫 fragment" 'h3="$(new_home)"; run_gb "$h3" --dry-run; [ ! -e "$(wt_fragment "$h3")" ]'
}

# 本來就有 .bash_profile：裝完馬上 --rollback，hook 也要跟著還原掉。
t_rollback_hook() {
  banner "rollback-hook"
  local h; h="$(new_home)"
  printf 'export MINE=1\n# keep\n' > "$h/.bash_profile"
  cp "$h/.bash_profile" "$WORK/profile.rb"
  run_gb "$h" --no-fonts
  check "裝好有 hook" 'grep -q "zsh-p10k-install auto start" "$h/.bash_profile"'
  run_gb "$h" --rollback -y
  check "rollback exit 0" '[ "$RC" -eq 0 ]'
  check "rollback 後 .bash_profile 回到裝之前" 'cmp -s "$WORK/profile.rb" "$h/.bash_profile"'
}

# zsh-p10k update：從 release 下載最新的腳本，核對 SHA256SUMS 再重跑。用 file:// 的假 release。
t_self_update() {
  banner "self-update"
  ensure_clean_home
  local h="$CLEAN_HOME" rel="$WORK/rel" bad="$WORK/relbad"
  mkdir -p "$rel" "$bad"
  cp "$INSTALLER" "$rel/install-zsh-p10k.sh"; (cd "$rel" && sha256sum install-zsh-p10k.sh > SHA256SUMS)
  cp "$INSTALLER" "$bad/install-zsh-p10k.sh"; printf '%064d  install-zsh-p10k.sh\n' 0 > "$bad/SHA256SUMS"
  check "zsh-p10k 指令裝好了" '[ -f "$h/.local/bin/zsh-p10k" ]'
  RUN_TOOL="$h/.local/bin/zsh-p10k" ZSH_P10K_RELEASE_URL="file:///$(cygpath -m "$rel")" run_gb "$h" update -y
  check "update exit 0" '[ "$RC" -eq 0 ]'
  check "update 有核對 sha256" 'out_has "sha256 核對通過"'
  check "update 有重跑安裝" 'out_has "使用既有的 zsh"'
  RUN_TOOL="$h/.local/bin/zsh-p10k" ZSH_P10K_RELEASE_URL="file:///$(cygpath -m "$bad")" run_gb "$h" update -y
  check "sha256 對不上就停" '[ "$RC" -ne 0 ] && out_has "sha256 對不上"'
  check "zsh 裡打得到 zsh-p10k" '[ "$(in_zsh "$h" -c "command -v zsh-p10k")" = "$h/.local/bin/zsh-p10k" ]'
}

ALL_SCENARIOS="dry-run clean rerun wt-profile self-update reg-fail no-fonts-claim no-chsh-hint uninstall
rollback-hook profile-restored keep-bashrc keep-bash-login existing-zsh font-fail bad-zsh-hash zsh-pkg-gone zsh-mv-retry spaced-home nonascii-home"

run_scenario() {
  case "$1" in
    dry-run)      t_dry_run ;;
    clean)        t_clean ;;
    rerun)        t_rerun ;;
    keep-bashrc)  t_keep_bashrc ;;
    existing-zsh) t_existing_zsh ;;
    uninstall)    t_uninstall ;;
    font-fail)    t_font_fail ;;
    reg-fail)     t_reg_fail ;;
    no-fonts-claim) t_no_fonts_claim ;;
    no-chsh-hint) t_no_chsh_hint ;;
    keep-bash-login) t_keep_bash_login ;;
    profile-restored) t_profile_restored ;;
    bad-zsh-hash) t_bad_zsh_hash ;;
    zsh-mv-retry) t_zsh_mv_retry ;;
    zsh-pkg-gone) t_zsh_pkg_gone ;;
    spaced-home)  t_spaced_home ;;
    nonascii-home) t_nonascii_home ;;
    wt-profile)   t_wt_profile ;;
    rollback-hook) t_rollback_hook ;;
    self-update)  t_self_update ;;
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

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
