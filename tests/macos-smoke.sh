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
bad()  { printf '  \033[31mFAIL\033[0m %s\n' "$1"; FAIL=$((FAIL+1)); }
skip() { printf '  \033[33mSKIP\033[0m %s\n' "$1"; SKIP=$((SKIP+1)); }
check(){ if eval "$2"; then ok "$1"; else bad "$1"; fi; }
banner() { printf '\n\033[1m=== macOS 情境：%s ===\033[0m\n' "$1"; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/zsh-p10k-smoke.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

OUT="$WORK/out.txt"
RC=0
XS_LOG="$WORK/xcode-select.log"

# 假的 xcode-select：-p 轉給真的那個，--install 只記一筆，不真的跳視窗。
mkdir -p "$WORK/bin"
cat > "$WORK/bin/xcode-select" <<EOF
#!/bin/sh
case "\${1:-}" in
  --install) echo "install" >> "$XS_LOG"; exit 1 ;;
  *) exec /usr/bin/xcode-select "\$@" ;;
esac
EOF
chmod +x "$WORK/bin/xcode-select"

has_clt() { /usr/bin/xcode-select -p >/dev/null 2>&1; }

new_home() { mktemp -d "$WORK/home.XXXXXX"; }

home_is_empty() { [ -z "$(find "$1" -mindepth 1 2>/dev/null | head -1)" ]; }

# 沒有 tty 的跑法：用 perl 的 setsid 拿掉 controlling terminal，
# 這樣在終端機裡直接跑測試，也跟「ssh host command」一樣打不開 /dev/tty。
run_notty() {
  local home="$1"; shift
  : > "$XS_LOG"
  RC=0
  env HOME="$home" PATH="$WORK/bin:$PATH" \
    perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV or die "exec: $!"' \
    bash "$INSTALLER" "$@" < /dev/null > "$OUT" 2>&1 || RC=$?
}

# 有 tty 的跑法：用 script 開一個 pty，input 依序餵進去。
run_tty() {
  local input="$1" home="$2"; shift 2
  : > "$XS_LOG"
  RC=0
  printf '%b' "$input" | env HOME="$home" PATH="$WORK/bin:$PATH" \
    script -q /dev/null bash "$INSTALLER" "$@" > "$OUT" 2>&1 || RC=$?
}

out_has() { grep -qF -- "$1" "$OUT"; }

# ---------------------------------------------------------------------------
# 情境
# ---------------------------------------------------------------------------

t_no_clt_notty() {
  banner "no-clt-notty"
  has_clt && { skip "這台有 Command Line Tools"; return; }
  local h; h="$(new_home)"
  run_notty "$h"
  check "exit code 不是 0" '[ "$RC" -ne 0 ]'
  check "輸出提到 xcode-select --install" 'out_has "xcode-select --install"'
  check "HOME 底下沒有任何檔案" 'home_is_empty "$h"'
  check "沒有執行 xcode-select --install" '[ ! -s "$XS_LOG" ]'
}

t_no_clt_tty_no() {
  banner "no-clt-tty-no"
  has_clt && { skip "這台有 Command Line Tools"; return; }
  local h; h="$(new_home)"
  run_tty 'n\n' "$h"
  check "有問要不要叫出安裝視窗" 'out_has "要幫你叫出安裝視窗嗎"'
  check "exit code 不是 0" '[ "$RC" -ne 0 ]'
  check "HOME 底下沒有任何檔案" 'home_is_empty "$h"'
  check "沒有執行 xcode-select --install" '[ ! -s "$XS_LOG" ]'
}

t_dry_run_report() {
  banner "dry-run-report"
  local h; h="$(new_home)"
  run_notty "$h" --dry-run
  if has_clt; then
    check "exit 0" '[ "$RC" -eq 0 ]'
    check "報告有 macOS" 'out_has "macOS"'
    check "報告有系統版本" 'out_has "$(sw_vers -productVersion)"'
    check "報告有架構" 'out_has "$(uname -m)"'
  else
    check "沒有 Command Line Tools 時提到 xcode-select --install" 'out_has "xcode-select --install"'
  fi
  check "沒有判定成不支援" '! out_has "不支援這台機器"'
  check "HOME 底下沒有任何檔案" 'home_is_empty "$h"'
}

ALL_SCENARIOS="no-clt-notty no-clt-tty-no dry-run-report"

run_scenario() {
  case "$1" in
    no-clt-notty)   t_no_clt_notty ;;
    no-clt-tty-no)  t_no_clt_tty_no ;;
    dry-run-report) t_dry_run_report ;;
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
