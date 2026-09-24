#!/usr/bin/env bash
# 在每種初始狀態各開一個容器跑 dist/install-zsh-p10k.sh。
#   ./tests/run-fixtures.sh            全部跑
#   ./tests/run-fixtures.sh native-omz 只跑一個
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

IMAGE="zsh-p10k-fixture:latest"
IMAGE_BUSTER="zsh-p10k-fixture-buster:latest"
INSTALLER="dist/install-zsh-p10k.sh"

[ -f "$INSTALLER" ] || { echo "找不到 $INSTALLER，先跑 ./build.sh" >&2; exit 1; }

FIXTURES=("$@")
[ "${#FIXTURES[@]}" -eq 0 ] && FIXTURES=(
  fresh-bash zsh-no-omz v2-installed native-omz
  v2-with-user-edits has-desktop forwarded-display hook-fallback ancient-awk
  dotfiles-symlink sticky-options
)

# ancient-awk 要跑在 mawk 1.3.3 的映像上，那個映像只有它用得到。
need_buster=0
for f in "${FIXTURES[@]}"; do
  [ "$f" = "ancient-awk" ] && need_buster=1
done

echo "==> 建置測試映像"
docker build -q -t "$IMAGE" tests/ >/dev/null || exit 1
if [ "$need_buster" -eq 1 ]; then
  echo "==> 建置 buster 映像（mawk 1.3.3）"
  docker build -q -t "$IMAGE_BUSTER" -f tests/Dockerfile.buster tests/ >/dev/null || exit 1
fi

declare -a RESULTS=()
OVERALL=0

for f in "${FIXTURES[@]}"; do
  img="$IMAGE"
  [ "$f" = "ancient-awk" ] && img="$IMAGE_BUSTER"
  if docker run --rm \
      -v "$PWD/$INSTALLER:/tmp/installer.sh:ro" \
      -v "$PWD/tests/incontainer.sh:/tmp/incontainer.sh:ro" \
      "$img" bash /tmp/incontainer.sh "$f" /tmp/installer.sh
  then
    RESULTS+=("PASS  $f")
  else
    RESULTS+=("FAIL  $f")
    OVERALL=1
  fi
done

printf '\n\033[1m========== 總結 ==========\033[0m\n'
for r in "${RESULTS[@]}"; do
  case "$r" in
    PASS*) printf '\033[32m%s\033[0m\n' "$r" ;;
    *)     printf '\033[31m%s\033[0m\n' "$r" ;;
  esac
done
exit "$OVERALL"
