#!/usr/bin/env bash
#
# 把 install-zsh-p10k.sh.in 的邏輯，加上壓縮過的 .p10k.zsh template，
# 組成一支可以直接 curl | bash 的單檔腳本。
#
#   ./build.sh
#
set -euo pipefail

cd "$(dirname "$0")"

SRC="install-zsh-p10k.sh.in"
TEMPLATE="template_basic-admin_.p10.zsh.sh"
OUT="dist/install-zsh-p10k.sh"

[ -f "$SRC" ] || { echo "找不到 $SRC" >&2; exit 1; }
[ -f "$TEMPLATE" ] || { echo "找不到 $TEMPLATE" >&2; exit 1; }

# awk 程式裡不准出現 POSIX 字元類別。
#
# mawk 1.3.3（1996 年版，Raspbian buster 到現在還在出貨）不認得 [[:space:]]，
# 而且是靜默不匹配：不報錯、不警告，regex 就是永遠不成立。
# 樹莓派上 ~/.zshrc.local 一直產不出來就是這麼來的，查了很久才查到。
#
# grep -E 不在此限（所有實作都支援），所以只掃 awk 程式本體：
# 從 `awk … '` 開始，到只有一個單引號的那一行為止。
awk_posix_class_check() {
  awk '
    /awk( -[^ ]+ [^ ]*)* .$/ && /awk/ { inawk = 1; next }
    inawk && /^[ \t]*.[ \t]*[^ \t]*$/ && !/\[\[:/ { inawk = 0 }
    inawk && /\[\[:/ {
      printf("%s:%d: awk 程式裡不能用 POSIX 字元類別（mawk 1.3.3 不認得）：%s\n",
             FILENAME, FNR, $0) > "/dev/stderr"
      bad = 1
    }
    END { exit bad }
  ' "$1"
}

if ! awk_posix_class_check "$SRC"; then
  echo "" >&2
  echo "改用 [ \\t] 之類的寫法。grep -E 要匹配空白請用腳本裡的 \$SP 變數。" >&2
  exit 1
fi
echo "awk 相容性  OK（沒有 POSIX 字元類別）"

payload="$(gzip -9nc "$TEMPLATE" | base64 -w0)"

mkdir -p "$(dirname "$OUT")"
awk -v p="$payload" '{ gsub(/@@P10K_TEMPLATE_B64@@/, p); print }' "$SRC" > "$OUT"
chmod +x "$OUT"

bash -n "$OUT" || { echo "語法檢查失敗" >&2; exit 1; }

printf 'template  %8d bytes\n' "$(wc -c < "$TEMPLATE")"
printf 'payload   %8d bytes (gzip + base64)\n' "${#payload}"
printf '%-9s %8d bytes\n' "$OUT" "$(wc -c < "$OUT")"

# 驗證內嵌的 payload 解得回原檔
embedded="$(grep -o "^P10K_TEMPLATE_B64='[^']*'" "$OUT" | sed "s/^P10K_TEMPLATE_B64='//; s/'$//")"
if printf '%s' "$embedded" | base64 -d | gzip -dc | cmp -s - "$TEMPLATE"; then
  echo "round-trip  OK"
else
  echo "round-trip  FAILED" >&2
  exit 1
fi
