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
    PATH="$WORK/bin:$PATH" bash "$INSTALLER" "$@" < /dev/null > "$OUT" 2>&1 || RC=$?
}

out_has() { grep -qaF -- "$1" "$OUT"; }
no_sudo_called() { [ ! -s "$SUDO_LOG" ]; }
sha_of() { sha256sum "$1" | cut -d' ' -f1; }
fonts_dir() { printf '%s/appdata/Microsoft/Windows/Fonts' "$1"; }
fonts_count() { find "$(fonts_dir "$1")" -maxdepth 1 -name 'MesloLGS NF *.ttf' 2>/dev/null | wc -l | tr -d ' '; }
font_values() { MSYS_NO_PATHCONV=1 reg query "$FONT_KEY" 2>/dev/null | grep -c 'MesloLGS NF .*(TrueType)'; }
zsh_exe() { printf '%s/.local/zsh-msys/usr/bin/zsh.exe' "$1"; }
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

# 中文帳號：MSYS2 版 zsh 的 zcompile 寫不了這種路徑，p10k 會印錯誤。
# 要驗的是事前有講，而且 zsh 和 p10k 還是能用。
t_nonascii_home() {
  banner "nonascii-home"
  local h="$WORK/使用者"
  mkdir -p "$h"
  run_gb "$h"
  check "exit 0" '[ "$RC" -eq 0 ]'
  check "事前有警告" 'out_has "非 ASCII"'
  check "zsh.exe 裝好了" '[ -x "$(zsh_exe "$h")" ]'
  check "四個字型都在" '[ "$(fonts_count "$h")" = 4 ]'
  check "p10k 還是載得起來" '[ "$(in_zsh "$h" -i -c "print -r -- \${+functions[p10k]}" | tail -1)" = 1 ]'
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
  PATH="$d:$PATH" run_gb "$h"
  check "停下來（不是 exit 0）" '[ "$RC" -ne 0 ]'
  check "輸出提到 sha256" 'out_has "sha256"'
  check "沒有裝半套 zsh" '[ ! -e "$h/.local/zsh-msys" ] && [ ! -e "$h/.local/zsh-msys.new" ]'
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
  local h="$CLEAN_HOME" a b
  a="$(sha_of "$h/.zshrc")"; b="$(sha_of "$h/.zshenv")"
  run_gb "$h"
  check "第二次 exit 0" '[ "$RC" -eq 0 ]'
  check ".zshrc 沒變" '[ "$(sha_of "$h/.zshrc")" = "$a" ]'
  check ".zshenv 沒變" '[ "$(sha_of "$h/.zshenv")" = "$b" ]'
  check "用既有的 zsh，不重新下載" 'out_has "使用既有的 zsh"'
  check "hook 只有一份" '[ "$(grep -c "BEGIN zsh-p10k-install auto start" "$h/.bash_profile")" = 1 ]'
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
}

ALL_SCENARIOS="dry-run clean rerun reg-fail no-fonts-claim no-chsh-hint uninstall
keep-bashrc keep-bash-login existing-zsh font-fail bad-zsh-hash spaced-home nonascii-home"

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
    bad-zsh-hash) t_bad_zsh_hash ;;
    spaced-home)  t_spaced_home ;;
    nonascii-home) t_nonascii_home ;;
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
