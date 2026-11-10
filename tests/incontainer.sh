#!/usr/bin/env bash
# 在容器裡跑一個 fixture：佈置初始狀態 → 安裝 → 驗證 → 重跑確認沒有變動 → 解除安裝驗證還原。
# 用法： incontainer.sh <fixture-name> <installer-path>
# check() 用 eval 跑字串，shellcheck 看不到字串裡用到的變數。
# shellcheck disable=SC2034
set -uo pipefail

FIXTURE="$1"
INSTALLER="$2"
SENTINEL="export FIXTURE_SENTINEL=keepme"

PASS=0
FAIL=0

ok()   { printf '  \033[32mPASS\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf '  \033[31mFAIL\033[0m %s\n' "$1"; FAIL=$((FAIL+1)); }
check(){ if eval "$2"; then ok "$1"; else bad "$1"; fi; }

banner() { printf '\n\033[1m=== fixture: %s ===\033[0m\n' "$1"; }

# ---------------------------------------------------------------- 佈置

seed_omz() {
  cp -r /opt/seed/oh-my-zsh "$HOME/.oh-my-zsh"
}

seed_pyenv() {
  mkdir -p "$HOME/.pyenv/bin"
  cat > "$HOME/.pyenv/bin/pyenv" <<'EOF'
#!/bin/sh
[ "$1" = "init" ] && { echo '# fake pyenv init'; exit 0; }
exit 0
EOF
  chmod +x "$HOME/.pyenv/bin/pyenv"
  cat >> "$HOME/.bashrc" <<'EOF'

export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"
EOF
}

seed_nvm() {
  mkdir -p "$HOME/.nvm"
  echo '# fake nvm' > "$HOME/.nvm/nvm.sh"
  cat >> "$HOME/.bashrc" <<'EOF'

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
EOF
}

seed_bash_aliases() {
  cat > "$HOME/.bash_aliases" <<'EOF'
alias watchh='watch -c -n 1 '
export MONITOR_SCRIPT=~/scripts/monitor.sh
EOF
}

seed_extra_bashrc() {
  cat >> "$HOME/.bashrc" <<'EOF'

export MY_CUSTOM_VAR=hello
alias ll='ls -alF'
PS1='\u@\h:\w\$ '
shopt -s histappend
EOF
}

# v2 原封不動寫出來的 .zshrc。
#
# 必須逐字照抄：v3.1 的 v2 骨架判定要求這 40 行全中且順序一致，少一行註解就判不出來。
# 之前這裡是「大意相同」的簡化版，結果新判定把它當成非 v2 產物，測不到 --clean-v2。
v2_template() {
  cat <<'EOF'
# Keep non-interactive zsh clean for agents, scripts, scp, rsync, CI, and command wrappers.
[[ -o interactive ]] || return

# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# User-local binaries, useful for no-sudo zsh installations.
typeset -U path PATH

if [[ -d "$HOME/.local/bin" ]]; then
  path=("$HOME/.local/bin" $path)
fi

export PATH

# oh-my-zsh base path.
export ZSH="${ZSH:-$HOME/.oh-my-zsh}"

# Powerlevel10k theme.
ZSH_THEME="powerlevel10k/powerlevel10k"

# oh-my-zsh plugins.
plugins=(
  git
  zsh-autosuggestions
  fast-syntax-highlighting
)

# zsh-completions must be added to fpath before oh-my-zsh initializes compinit.
fpath+=${ZSH_CUSTOM:-${ZSH:-~/.oh-my-zsh}/custom}/plugins/zsh-completions/src

# Load oh-my-zsh.
source "$ZSH/oh-my-zsh.sh"

# Load Powerlevel10k configuration if present.
[[ -f "$HOME/.p10k.zsh" ]] && source "$HOME/.p10k.zsh"
EOF
}

seed_v2_zshrc() {
  v2_template > "$HOME/.zshrc"
  echo "$SENTINEL" >> "$HOME/.zshrc"
}

# 重現樹莓派：v2 骨架 + 使用者自己插在「骨架中間」的行。
#
# 關鍵是最後那個 `if [ -f ~/.bash_aliases ]; then … fi`，它的 fi 跟骨架裡的 fi
# 一字不差。按文字刪 v2 的行會刪掉它，留下孤兒 if,zsh -n 就會炸。
seed_v2_with_user_edits() {
  v2_template \
    | sed '/^export PATH$/a\
\
# If you come from bash you might have to change your $PATH.\
export PATH=$HOME/bin:$HOME/.local/bin:/usr/local/bin:$PATH' \
    > "$HOME/.zshrc"
  cat >> "$HOME/.zshrc" <<'EOF'

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init - zsh)"

if [ -f ~/.bash_aliases ]; then
    . ~/.bash_aliases
fi
EOF
  echo "$SENTINEL" >> "$HOME/.zshrc"
}

# 有桌面的機器：xsessions 裡真的有 session 檔。
seed_desktop() {
  sudo mkdir -p /usr/share/xsessions
  echo '[Desktop Entry]' | sudo tee /usr/share/xsessions/LXDE.desktop >/dev/null
}

# 沒有桌面，但 ssh 帶了 X11 forwarding，所以 DISPLAY 有值。
# 重現工作站被誤判成「有圖形介面」的那個情境。
seed_forwarded_display() {
  sudo rm -rf /usr/share/xsessions /usr/share/wayland-sessions
  export DISPLAY=localhost:10.0
  export SSH_CONNECTION="10.0.0.1 51234 10.0.0.2 22"
}

# 工作站上那種手寫的完整 omz .zshrc
seed_native_zshrc() {
  cat > "$HOME/.zshrc" <<'EOF'
# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

export PATH=$HOME/bin:/usr/local/bin:$PATH
export ZSH="$HOME/.oh-my-zsh"

# ZSH_THEME="robbyrussell"
ZSH_THEME="powerlevel10k/powerlevel10k"

HIST_STAMPS="yyyy-mm-dd"

plugins=(
	git
	zsh-autosuggestions
	fast-syntax-highlighting
)

fpath+=${ZSH_CUSTOM:-${ZSH:-~/.oh-my-zsh}/custom}/plugins/zsh-completions/src
source $ZSH/oh-my-zsh.sh

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init - zsh)"

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

# Fix MobaXterm Home/End key with ZSH
bindkey '^[[H' beginning-of-line
bindkey '^[[F' end-of-line
EOF
  echo "$SENTINEL" >> "$HOME/.zshrc"
}

setup() {
  case "$FIXTURE" in
    fresh-bash)
      seed_extra_bashrc
      ;;
    zsh-no-omz)
      sudo apt-get install -y -qq --no-install-recommends zsh >/dev/null 2>&1
      seed_pyenv
      seed_extra_bashrc
      ;;
    v2-installed)
      sudo apt-get install -y -qq --no-install-recommends zsh >/dev/null 2>&1
      sudo chsh -s /usr/bin/zsh tester
      seed_omz
      seed_pyenv
      seed_bash_aliases
      seed_v2_zshrc
      ;;
    native-omz)
      sudo apt-get install -y -qq --no-install-recommends zsh >/dev/null 2>&1
      sudo chsh -s /usr/bin/zsh tester
      seed_omz
      seed_pyenv
      seed_nvm
      seed_native_zshrc
      ;;
    v2-with-user-edits)
      sudo apt-get install -y -qq --no-install-recommends zsh >/dev/null 2>&1
      sudo chsh -s /usr/bin/zsh tester
      seed_omz
      seed_pyenv
      seed_bash_aliases
      seed_v2_with_user_edits
      EXTRA_ARGS="--clean-v2"
      ;;
    has-desktop)
      sudo apt-get install -y -qq --no-install-recommends zsh >/dev/null 2>&1
      seed_desktop
      seed_extra_bashrc
      # 核對 sha256 的那一刻，正式檔名不能已經存在：不然這時按 Ctrl-C 會留下沒驗過的字型，
      # 重跑看到檔案在就跳過。包一層 sha256sum，被呼叫時記下正式檔名在不在。
      mkdir -p /tmp/shawrap
      cat > /tmp/shawrap/sha256sum <<'EOF'
#!/bin/sh
for a in "$@"; do
  case "$a" in
    *MesloLGS*) f="${a%.part}"; if [ -e "$f" ]; then echo "EXISTS $f"; else echo "ok $a"; fi >> /tmp/shawrap/log ;;
  esac
done
exec /usr/bin/sha256sum "$@"
EOF
      chmod +x /tmp/shawrap/sha256sum
      export PATH="/tmp/shawrap:$PATH"
      ;;
    forwarded-display)
      sudo apt-get install -y -qq --no-install-recommends zsh >/dev/null 2>&1
      seed_forwarded_display
      seed_extra_bashrc
      ;;
    hook-fallback)
      # chsh 走不通時的退路。把 zsh 從 /etc/shells 拿掉就會逼出這條路徑，
      # 不必真的去弄一顆自編的 zsh。
      sudo apt-get install -y -qq --no-install-recommends zsh >/dev/null 2>&1
      sudo sed -i '/zsh/d' /etc/shells
      # 這台有 .profile 但沒有 .bash_profile，共用主機就是這個形狀。
      # bash 的 login shell 只讀第一個存在的，憑空生一個 .bash_profile
      # 會讓整份 .profile 靜靜地失效。
      rm -f "$HOME/.bash_profile"
      cat > "$HOME/.profile" <<'EOF'
export PROFILE_SENTINEL=must-survive
EOF
      seed_extra_bashrc
      ;;
    dotfiles-symlink)
      # stow / chezmoi 的形狀：.zshrc 與 .zshenv 都是指進 dotfile repo 的 symlink。
      # 用 mv 蓋掉的話 symlink 會變成一般檔案，dotfile repo 就此收不到改動。
      sudo apt-get install -y -qq --no-install-recommends zsh >/dev/null 2>&1
      mkdir -p "$HOME/dotfiles"
      printf '# my dotfiles zshrc\n%s\n' "$SENTINEL" > "$HOME/dotfiles/zshrc"
      printf 'export DOTFILES_ENV=1\n' > "$HOME/dotfiles/zshenv"
      ln -s dotfiles/zshrc "$HOME/.zshrc"
      ln -s dotfiles/zshenv "$HOME/.zshenv"
      seed_extra_bashrc
      ;;
    sticky-options)
      # 第一次帶了選項，之後重跑都不帶。選項必須被記住，不能悄悄變回預設值。
      sudo apt-get install -y -qq --no-install-recommends zsh >/dev/null 2>&1
      printf '# existing zshrc\n%s\n' "$SENTINEL" > "$HOME/.zshrc"
      seed_extra_bashrc
      EXTRA_ARGS="--omz-update reminder --no-chsh"
      ;;
    self-build)
      # 沒有 zsh 也沒有 sudo：只剩自己編譯這條路。
      # 映像裡的 apt 索引會過期，libc6-dev 拉到的 linux-libc-dev 舊版會 404，所以這裡要先更新。
      sudo apt-get update -qq >/dev/null 2>&1
      sudo apt-get install -y -qq --no-install-recommends gcc g++ libc6-dev make xz-utils >/dev/null 2>&1
      sudo rm -f /usr/bin/sudo
      export PATH="$HOME/.local/bin:$PATH"
      seed_extra_bashrc
      ;;
    font-fail)
      # 字型的網址一律失敗，重試用完之後結尾要講實話。
      sudo apt-get install -y -qq --no-install-recommends zsh >/dev/null 2>&1
      seed_desktop
      seed_extra_bashrc
      mkdir -p /tmp/failcurl
      cat > /tmp/failcurl/curl <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> /tmp/failcurl/args
for a in "$@"; do
  case "$a" in
    http*MesloLGS*) echo "curl: (56) simulated failure" >&2; exit 56 ;;
  esac
done
exec /usr/bin/curl "$@"
EOF
      chmod +x /tmp/failcurl/curl
      export PATH="/tmp/failcurl:$PATH"
      ;;
    external-p10k)
      # p10k 由 oh-my-zsh 以外的地方載入：不 clone 第二份，oh-my-zsh 也不能去找主題。
      sudo apt-get install -y -qq --no-install-recommends zsh >/dev/null 2>&1
      mkdir -p "$HOME/brew"
      printf 'typeset -g EXTERNAL_P10K=1\n' > "$HOME/brew/powerlevel10k.zsh-theme"
      printf '# existing zshrc\nsource "$HOME/brew/powerlevel10k.zsh-theme"\n%s\n' "$SENTINEL" > "$HOME/.zshrc"
      seed_extra_bashrc
      ;;
    nonascii-home)
      # 家目錄有中文和泰文。zsh 的 zcompile、sysopen 用絕對路徑寫不了這種目錄
      # （路徑裡有 0x83-0x9F 的位元組就會壞），p10k 每開一次視窗就印一串錯誤。
      sudo apt-get install -y -qq --no-install-recommends zsh >/dev/null 2>&1
      export HOME="/tmp/使用者ผู้ใช้" LANG=C.UTF-8
      mkdir -p "$HOME"
      seed_extra_bashrc
      ;;
    ancient-awk)
      # 這個 fixture 只在 debian:buster 映像上跑，那裡的 awk 是 mawk 1.3.3。
      sudo apt-get install -y -qq --no-install-recommends zsh >/dev/null 2>&1
      seed_extra_bashrc
      ;;
    *) echo "unknown fixture: $FIXTURE" >&2; exit 2 ;;
  esac
}

# ---------------------------------------------------------------- 驗證

count() { grep -cF "$2" "$1" 2>/dev/null || true; }

banner "$FIXTURE"
EXTRA_ARGS=""
setup

[ -f "$HOME/.zshrc" ] && cp "$HOME/.zshrc" /tmp/zshrc.orig || : > /tmp/zshrc.orig
[ -f "$HOME/.zshenv" ] && cp "$HOME/.zshenv" /tmp/zshenv.orig || rm -f /tmp/zshenv.orig
STATE_FILE="$HOME/.config/zsh-p10k-install/options"
# 備份的權限必須跟原檔一樣。少了 cp -p 的話 600 的 .zshrc 會備份成 644，
# 等於把使用者的私人設定攤開給同機其他人看。
if [ -f "$HOME/.zshrc" ]; then
  chmod 600 "$HOME/.zshrc"
  ORIG_MODE="$(stat -L -c '%a' "$HOME/.zshrc")"
else
  ORIG_MODE=""
fi

echo "--- 第一次安裝 ---"
# shellcheck disable=SC2086
bash "$INSTALLER" -y $EXTRA_ARGS > /tmp/run1.log 2>&1
RC1=$?
if [ "$RC1" -ne 0 ]; then
  bad "安裝結束碼為 0（實際 $RC1）"
  tail -30 /tmp/run1.log
else
  ok "安裝結束碼為 0"
fi

ZSH_BIN="$(command -v zsh || echo /usr/bin/zsh)"

check ".zshrc 存在"                     '[ -s "$HOME/.zshrc" ]'
check ".zshrc 語法正確（zsh -n）"       '"$ZSH_BIN" -n "$HOME/.zshrc"'
check "head 區段只有一個"               '[ "$(count "$HOME/.zshrc" "# >>> zsh-p10k-install: head >>>")" = 1 ]'
check "tail 區段只有一個"               '[ "$(count "$HOME/.zshrc" "# >>> zsh-p10k-install: tail >>>")" = 1 ]'
check "instant prompt 區段只有一個"     '[ "$(grep -c "^if \[\[ -r \"\${XDG_CACHE_HOME" "$HOME/.zshrc")" = 1 ]'
check "oh-my-zsh.sh 只被 source 一次"   '[ "$(grep -cE "^[[:space:]]*(source|\.)[[:space:]]+.*oh-my-zsh\.sh" "$HOME/.zshrc")" = 1 ]'
check "MobaXterm bindkey 有寫入"        'grep -q "beginning-of-line" "$HOME/.zshrc"'
check ".bash_aliases 有被 source"       'grep -q "\.bash_aliases" "$HOME/.zshrc"'
# PATH 現在只寫在 .zshenv。head 區段刻意不再寫第二份：.zshenv 一定先讀，
# 放 .zshrc 是純粹多餘，而且每個互動 shell 都會把那三個目錄重新推到最前面。
check "PATH 那一行寫在 .zshenv"         'grep -qF "export PATH=\$HOME/bin:\$HOME/.local/bin:/usr/local/bin:\$PATH" "$HOME/.zshenv"'
check "head 區段沒有重複 PATH"          '[ "$(sed -n "/head >>>/,/head <<</p" "$HOME/.zshrc" | grep -cF "export PATH=\$HOME/bin")" = 0 ]'
check "head 區段沒有重複 typeset -U"    '[ "$(sed -n "/head >>>/,/head <<</p" "$HOME/.zshrc" | grep -c "^typeset -U path PATH$")" = 0 ]'
[ "$FIXTURE" != "sticky-options" ] && \
check "omz 更新提示預設為 prompt"       'grep -q "zstyle .:omz:update. mode prompt" "$HOME/.zshrc" || grep -q "已經有，所以我們不寫" /tmp/run1.log'
check "~/.p10k.zsh 已產生且夠大"        '[ "$(wc -c < "$HOME/.p10k.zsh")" -gt 90000 ]'
check "互動式 zsh 能載入"               '"$ZSH_BIN" -i -c "print READY" 2>/dev/null | grep -q READY'
check "備份沒有散在家目錄"              '! find "$HOME" -maxdepth 1 -name ".zshrc.backup.*" | grep -q .'
check "zsh-p10k 指令裝好了"             '[ -x "$HOME/.local/bin/zsh-p10k" ]'
check "zsh 裡打得到 zsh-p10k"           '[ "$("$ZSH_BIN" -c "command -v zsh-p10k" 2>/dev/null)" = "$HOME/.local/bin/zsh-p10k" ]'

case "$FIXTURE" in
  v2-installed|native-omz)
    check "偵測為附加模式"              'grep -q "附加模式" /tmp/run1.log'
    check "使用者原有內容保留（sentinel）" 'grep -qF "$SENTINEL" "$HOME/.zshrc"'
    ;;
  sticky-options)
    check "偵測為完整模式"              'grep -q "完整模式" /tmp/run1.log'
    check "--no-chsh 生效，login shell 維持 bash" 'getent passwd tester | grep -q "bash$"'
    ;;
  hook-fallback)
    check "偵測為完整模式"              'grep -q "完整模式" /tmp/run1.log'
    # 這個 fixture 刻意讓 chsh 走不通，所以 login shell 應該「維持 bash」。
    # 事前報告也必須先講出來，而不是承諾改 shell 然後失敗。
    check "login shell 維持 bash"       'getent passwd tester | grep -q "bash$"'
    check "報告事先講明 chsh 走不通"     'grep -q "chsh 走不通" /tmp/run1.log'
    ;;
  self-build)
    check "偵測為完整模式"              'grep -q "完整模式" /tmp/run1.log'
    check "報告講會自行編譯"            'grep -q "自行編譯" /tmp/run1.log'
    check "zsh 編好放在 ~/.local/bin"   '[ -x "$HOME/.local/bin/zsh" ]'
    check "編好的 zsh 載得起模組"       '[ "$("$HOME/.local/bin/zsh" -c "zmodload zsh/datetime && print ok")" = ok ]'
    check "login shell 維持 bash"       'getent passwd tester | grep -q "bash$"'
    check "改裝 hook"                   'grep -q "zsh-p10k-install auto start" "$HOME/.bash_profile"'
    ;;
  *)
    check "偵測為完整模式"              'grep -q "完整模式" /tmp/run1.log'
    check "login shell 已改成 zsh"      'getent passwd tester | grep -q "zsh$"'
    ;;
esac

# 開一個有 tty 的互動 zsh，等 p10k 跑完 prompt 之後的 dump，再離開。
# 印出 zsh 或 p10k 的錯誤行；沒有錯誤就什麼都不印。
# dump 掛在 zle 等輸入時才跑，輸入太早到它就不會跑，測試會假性通過。
# 所以不用固定秒數：等 zle 開始讀輸入（送出 bracketed paste 開啟序列 ESC[?2004h），
# 再等輸出停下來 0.5 秒，才送 exit。最多等 30 秒，等不到就印 TTY_TIMEOUT 讓檢查失敗。
tty_zsh_errors() {
  local log=/tmp/tty.log fifo=/tmp/tty.in pid i last=-1 size stable=0 ready=0
  rm -f "$log" "$fifo"; mkfifo "$fifo"
  # 外面包 timeout：zsh 收到 exit 卻不結束時，fixture 不能一直卡著。
  TERM=xterm-256color timeout 60 script -qfc "$ZSH_BIN -i" "$log" < "$fifo" >/dev/null 2>&1 &
  pid=$!
  exec 9> "$fifo"
  for i in $(seq 300); do
    if [ "$ready" -eq 0 ] && grep -qaF $'\e[?2004h' "$log" 2>/dev/null; then ready=1; fi
    if [ "$ready" -eq 1 ]; then
      size="$(wc -c < "$log")"
      if [ "$size" = "$last" ]; then stable=$((stable + 1)); else stable=0; last="$size"; fi
      [ "$stable" -ge 5 ] && break
    fi
    sleep 0.1
  done
  [ "$stable" -ge 5 ] || echo "TTY_TIMEOUT（${i} 次、zle ready=$ready）"
  echo exit >&9
  exec 9>&-
  wait "$pid" 2>/dev/null
  tr -d '\r' < "$log" \
    | grep -aE 'zwc|sysopen|definition file not found|no such file|command not found' || true
}

case "$FIXTURE" in
  fresh-bash)
    # VS Code 的終端機：bash 被 hook 換成 zsh 後，要自己載入 VS Code 的 zsh shell integration。
    # 用假的 code 指令：回報一個假的 integration 腳本路徑，並記下自己被叫了幾次。
    mkdir -p /tmp/fakecode
    printf '#!/bin/sh\necho call >> /tmp/fakecode/calls\n[ "$1 $2" = "--locate-shell-integration-path zsh" ] && echo /tmp/fakecode/si.zsh\n' > /tmp/fakecode/code
    chmod +x /tmp/fakecode/code
    # 第二行照抄 VS Code 腳本的行為：看到 VSCODE_INJECTION=1 就把 HISTFILE 改到 $USER_ZDOTDIR 底下。
    printf 'typeset -g VSC_SI_LOADED=1\n[[ "$VSCODE_INJECTION" == "1" ]] && HISTFILE=$USER_ZDOTDIR/.zsh_history\n' > /tmp/fakecode/si.zsh
    vsc_si() { env PATH="/tmp/fakecode:$PATH" "$@" "$ZSH_BIN" -i -c 'print -r -- "SI=${VSC_SI_LOADED:-0}"' 2>/dev/null | grep '^SI=' | tail -1; }
    check "VS Code 終端機裡會載入 zsh 的 shell integration" '[ "$(vsc_si TERM_PROGRAM=vscode)" = SI=1 ]'
    check "第二次用快取，不再叫 code（不用每次啟動 Node.js）" \
          '[ "$(vsc_si TERM_PROGRAM=vscode)" = SI=1 ] && [ "$(wc -l < /tmp/fakecode/calls)" -eq 1 ]'
    check "VS Code 自己注入過就不重複載入" '[ "$(vsc_si TERM_PROGRAM=vscode VSCODE_SHELL_INTEGRATION=1)" = SI=0 ]'
    check "VS Code 正在直接注入 zsh 時不插手" '[ "$(vsc_si TERM_PROGRAM=vscode VSCODE_ZDOTDIR=/tmp/vsc)" = SI=0 ]'
    # 從 VS Code 的 bash 切過來時，環境裡會留著 bash 那邊的 VSCODE_INJECTION=1。
    check "bash 留下的 VSCODE_INJECTION 不會把 HISTFILE 弄成 /.zsh_history" \
          '[ "$(env PATH="/tmp/fakecode:$PATH" TERM_PROGRAM=vscode VSCODE_INJECTION=1 "$ZSH_BIN" -i -c "print -r -- H=\$HISTFILE" 2>/dev/null | grep "^H=" | tail -1)" = "H=$HOME/.zsh_history" ]'
    check "不在 VS Code 裡就不載入"       '[ "$(vsc_si TERM_PROGRAM=other)" = SI=0 ]'
    ;;
  nonascii-home)
    check "事前有提醒家目錄有非 ASCII 字元" 'grep -q "非 ASCII" /tmp/run1.log'
    TTY_ERR1="$(tty_zsh_errors)"; TTY_ERR2="$(tty_zsh_errors)"
    check "第一次開 zsh 沒有錯誤輸出"   '[ -z "$TTY_ERR1" ]'
    check "第二次開 zsh 沒有錯誤輸出"   '[ -z "$TTY_ERR2" ]'
    [ -z "$TTY_ERR2" ] || printf '%s\n' "$TTY_ERR2" | head -5 | sed 's/^/    | /'
    check "p10k 真的有載入"             '[ "$("$ZSH_BIN" -i -c "print -r -- \${+functions[p10k]}" 2>/dev/null | tail -1)" = 1 ]'
    # josé、müller 這種路徑 zsh 寫得了，不能被一起關掉 instant prompt。
    mkdir -p /tmp/josé
    HOME=/tmp/josé bash "$INSTALLER" --dry-run > /tmp/jose.log 2>&1
    check "josé 這種帳號不會被提醒"     '! grep -q "非 ASCII" /tmp/jose.log && grep -q "dry-run" /tmp/jose.log'
    ;;
  native-omz)
    check "pyenv 被判定為已存在而跳過"  'grep -q "已在 .zshrc 裡，跳過.*pyenv" /tmp/run1.log'
    check "nvm 被判定為已存在而跳過"    'grep -q "已在 .zshrc 裡，跳過.*nvm" /tmp/run1.log'
    check "使用者的 HIST_STAMPS 還在"   'grep -q "HIST_STAMPS" "$HOME/.zshrc"'
    check "bindkey 沒有重複寫入"        '[ "$(grep -c "beginning-of-line" "$HOME/.zshrc")" = 1 ]'
    check "附加模式沒有插入 interactive guard" \
          '[ "$(count "$HOME/.zshrc" "[[ -o interactive ]] || return")" = 0 ]'
    ;;
  zsh-no-omz)
    check "pyenv 被寫入 head 區段"      'sed -n "/head >>>/,/head <<</p" "$HOME/.zshrc" | grep -q "pyenv init"'
    check "pyenv PATH 被寫入 .zshenv"   'sed -n "/env >>>/,/env <<</p" "$HOME/.zshenv" | grep -q "PYENV_ROOT"'
    check "非互動 zsh 拿得到 PYENV_ROOT" '"$ZSH_BIN" -c "echo \$PYENV_ROOT" | grep -q pyenv'
    check "非互動 zsh 的 PATH 有 .local/bin" '"$ZSH_BIN" -c "echo \$PATH" | grep -q "\.local/bin"'
    check ".zshenv 不會輸出任何東西"     '[ -z "$("$ZSH_BIN" -c "true" 2>&1)" ]'
    ;;
  v2-installed)
    check "pyenv 被寫入 head 區段"      'sed -n "/head >>>/,/head <<</p" "$HOME/.zshrc" | grep -q "PYENV_ROOT"'
    check "沒有插入第二個 interactive guard" \
          '[ "$(count "$HOME/.zshrc" "[[ -o interactive ]] || return")" = 1 ]'
    check "偵測到 v2 骨架"              'grep -q "偵測到 v2 的 .zshrc 骨架" /tmp/run1.log'
    check "沒加 --clean-v2 就不回收"    'grep -q "要收回來請加 --clean-v2" /tmp/run1.log'
    ;;
  v2-with-user-edits)
    check "偵測到 v2 骨架"              'grep -q "偵測到 v2 的 .zshrc 骨架" /tmp/run1.log'
    check "--clean-v2 後翻回完整模式"   'grep -q "完整模式" /tmp/run1.log'
    check "v2 骨架已被收走"             '! grep -q "User-local binaries, useful for no-sudo" "$HOME/.zshrc"'
    check "v2 的 oh-my-zsh.sh 只剩一份" '[ "$(grep -cE "^[[:space:]]*(source|\.)[[:space:]]+.*oh-my-zsh\.sh" "$HOME/.zshrc")" = 1 ]'
    # 這幾條是 --clean-v2 唯一會弄壞使用者檔案的路徑，一條都不能少
    check "使用者的 bash_aliases if/fi 完整" \
          '[ "$(grep -c "^if \[ -f ~/.bash_aliases \]; then$" "$HOME/.zshrc")" -ge 1 ]'
    check "使用者的 pyenv 行還在"       'grep -q "eval \"\$(pyenv init - zsh)\"" "$HOME/.zshrc"'
    check "p10k configure 寫的那行還在" 'grep -qF "[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh" "$HOME/.zshrc"'
    check "使用者原有內容保留（sentinel）" 'grep -qF "$SENTINEL" "$HOME/.zshrc"'
    check "沒有孤兒 fi（zsh -n 已驗）"   '"$ZSH_BIN" -n "$HOME/.zshrc"'
    ;;
  has-desktop)
    check "判定為有桌面"                'grep -q "桌面環境        這台有" /tmp/run1.log'
    check "字型有安裝"                  '[ -d "$HOME/.local/share/fonts/MesloLGS-NF" ]'
    check "字型有核對 sha256"           '[ -s /tmp/shawrap/log ]'
    check "核對時正式檔名還不存在"      '! grep -q "^EXISTS" /tmp/shawrap/log'
    ;;
  font-fail)
    check "安裝照樣完成"                '[ "$RC1" -eq 0 ]'
    check "沒有裝到字型檔"              '[ -z "$(find "$HOME/.local/share/fonts" -name "*.ttf" 2>/dev/null | head -1)" ]'
    check "結尾講 4 個字型沒裝到"       'grep -q "4 個字型沒裝到" /tmp/run1.log'
    check "下載先寫到 .part"            'grep -q "MesloLGS NF Regular.ttf.part" /tmp/failcurl/args'
    check "沒有留下 .part"              '[ -z "$(find "$HOME/.local/share/fonts" -name "*.part" 2>/dev/null | head -1)" ]'
    ;;
  external-p10k)
    check "報告說不另外 clone"          'grep -q "不另外 clone" /tmp/run1.log'
    check "沒有多 clone 一份 p10k"      '[ ! -e "$HOME/.oh-my-zsh/custom/themes/powerlevel10k" ]'
    check "oh-my-zsh 不去找主題"        'grep -q "^ZSH_THEME=\"\"$" "$HOME/.zshrc"'
    check "oh-my-zsh 沒抱怨找不到主題"  '! "$ZSH_BIN" -i -c exit 2>&1 | grep -q "not found"'
    check "外部的 p10k 真的有載入"      '[ "$("$ZSH_BIN" -i -c "print -r -- \$EXTERNAL_P10K" 2>/dev/null | tail -1)" = 1 ]'
    ;;
  forwarded-display)
    # DISPLAY 有值但機器沒有桌面。舊版就是在這裡把一台工作站判成「有圖形介面」的
    check "DISPLAY 有值不會騙過偵測"    'grep -q "桌面環境        沒有" /tmp/run1.log'
    check "沒有裝字型"                  '[ ! -d "$HOME/.local/share/fonts/MesloLGS-NF" ]'
    # 教人手動下載的網址要跟安裝用的一樣釘在 commit 上，上游換字型時才不會對不起來。
    check "字型說明有給下載網址"        'grep -q "powerlevel10k-media/raw/.*Regular.ttf" /tmp/run1.log'
    check "字型說明的網址沒有用 master" '! grep -q "powerlevel10k-media/raw/master" /tmp/run1.log'
    ;;
  hook-fallback)
    check "chsh 走不通時改裝 hook"      'grep -q "zsh-p10k-install auto start" "$HOME/.bash_profile"'
    # 新生的 .bash_profile 必須把 .profile 讀回來，否則使用者的 PATH / proxy /
    # conda 會在下次登入時無聲消失
    check "新建的 .bash_profile 有 source .profile" \
          'grep -q "\. ~/.profile" "$HOME/.bash_profile"'
    check ".profile 的內容仍然生效"     'bash -lc "echo \$PROFILE_SENTINEL" | grep -q must-survive'
    # zsh 裝了卻跑不起來時，hook 要留在 bash，不能讓人連 shell 都開不了。
    # hook 會跳過 TERM=dumb，容器裡的 script 預設就是，所以要自己設。
    login_in_tty() { TERM=xterm-256color timeout 15 script -qc 'bash -l -i -c "echo STILL_BASH"' /dev/null </dev/null 2>/dev/null; }
    # 只驗「沒印 STILL_BASH」的話，script 或 bash 起不來也會過。所以要 zsh 自己留下證據：
    # .zlogin 只有 login zsh 會讀，它寫出標記檔就代表真的切進 zsh 了。
    # 不用印到螢幕：p10k 的 instant prompt 會把啟動時的輸出扣住，session 太快結束就不會補印。
    printf ': > /tmp/in-zsh-login\n' > "$HOME/.zlogin"
    switched_to_zsh() { rm -f /tmp/in-zsh-login; login_in_tty >/dev/null; [ -f /tmp/in-zsh-login ]; }
    check "zsh 正常時 hook 會切過去"    'switched_to_zsh'
    # VS Code 主程序會設 VSCODE_PID，內建終端機全部繼承。這不能擋：VS Code 裡的終端機也要進 zsh。
    check "VS Code 的終端機也會切過去"  'VSCODE_PID=1234 TERM_PROGRAM=vscode switched_to_zsh'
    # VS Code 讀 shell 環境時會設 VSCODE_RESOLVING_ENVIRONMENT（而且沒有 tty）。那次要留在 bash。
    check "VS Code 讀環境時留在 bash"   'VSCODE_RESOLVING_ENVIRONMENT=1 login_in_tty | grep -q STILL_BASH'
    sudo cp /usr/bin/zsh /tmp/zsh.real
    printf '#!/bin/sh\nexit 1\n' | sudo tee /usr/bin/zsh >/dev/null
    check "zsh 跑不起來時留在 bash"     'login_in_tty | grep -q STILL_BASH'
    sudo cp /tmp/zsh.real /usr/bin/zsh
    rm -f "$HOME/.zlogin"
    ;;
  dotfiles-symlink)
    check ".zshrc 仍然是 symlink"       '[ -L "$HOME/.zshrc" ]'
    check ".zshenv 仍然是 symlink"      '[ -L "$HOME/.zshenv" ]'
    check "區段寫進了 dotfile repo 裡"  'grep -q "zsh-p10k-install: head" "$HOME/dotfiles/zshrc"'
    check "env 區段寫進了 dotfile repo 裡" 'grep -q "zsh-p10k-install: env" "$HOME/dotfiles/zshenv"'
    ;;
  sticky-options)
    check "寫入的更新提示是 reminder"   'grep -q "zstyle .:omz:update. mode reminder" "$HOME/.zshrc"'
    check "選項有記下來"                'grep -qx "omz_update=reminder" "$STATE_FILE" && grep -qx "no_chsh=1" "$STATE_FILE"'
    ;;
  ancient-awk)
    check "awk 是 mawk 1.3.3"           'mawk -W version 2>&1 | head -1 | grep -q "1.3.3"'
    check ".zshrc.local 有產生"         '[ -f "$HOME/.zshrc.local" ]'
    check "抽取真的有跑到（抓到自訂的 export）" \
          'grep -q "MY_CUSTOM_VAR" "$HOME/.zshrc.local"'
    check "發行版預設 alias 被濾掉"      '! grep -q "alias l=.ls -CF" "$HOME/.zshrc.local"'
    ;;
esac

# --- 還原點 ---
# 本來沒有 .zshrc 的機器不會產生還原點：沒有東西被覆蓋，備份也就沒有意義。
if [ -n "$ORIG_MODE" ]; then
  check "還原點目錄已建立"              '[ -d "$HOME/.zsh-p10k-backups" ]'
  # 同一次執行改到的檔案必須在同一個還原點。拆成兩個的話，--rollback 選哪個都只還原一半。
  check "同一次安裝只產生一個還原點"     '[ "$(find "$HOME/.zsh-p10k-backups" -mindepth 1 -maxdepth 1 -type d | wc -l)" = 1 ]'
  if [ -f /tmp/zshenv.orig ]; then
    check "還原點裡同時有 .zshrc 與 .zshenv" \
          '[ -f "$(find "$HOME/.zsh-p10k-backups" -mindepth 1 -maxdepth 1 -type d)/.zshenv" ]'
  fi
  check "還原點目錄權限為 700"          '[ "$(stat -c "%a" "$HOME/.zsh-p10k-backups")" = 700 ]'
  check "備份權限與原檔相同（$ORIG_MODE）" \
        '[ "$(stat -c "%a" "$(find "$HOME/.zsh-p10k-backups" -name .zshrc | head -1)")" = "$ORIG_MODE" ]'
  check ".zshrc 權限沒有被偷改"          '[ "$(stat -L -c "%a" "$HOME/.zshrc")" = "$ORIG_MODE" ]'
  check "--rollback 找得到還原點"        'bash "$INSTALLER" --rollback -y > /tmp/rb.log 2>&1 && grep -q "已還原" /tmp/rb.log'
  check "還原後 .zshrc 與安裝前相同"     'cmp -s /tmp/zshrc.orig "$HOME/.zshrc"'
  [ -f /tmp/zshenv.orig ] && \
  check "還原後 .zshenv 與安裝前相同"    'cmp -s /tmp/zshenv.orig "$HOME/.zshenv"'
  [ "$FIXTURE" = "dotfiles-symlink" ] && \
  check "還原後 .zshrc 仍然是 symlink"   '[ -L "$HOME/.zshrc" ]'
  # 還原本身也要能反悔：還原前的狀態要另外存成一個新的還原點
  check "還原前的狀態有被存起來"         '[ "$(find "$HOME/.zsh-p10k-backups" -mindepth 1 -maxdepth 1 -type d | wc -l)" -ge 2 ]'
  # 還原完再裝回去，後面的「重跑沒有變動」與解除安裝測試才有東西可測
  # shellcheck disable=SC2086
  bash "$INSTALLER" -y $EXTRA_ARGS > /tmp/run1b.log 2>&1
else
  check "沒有東西被覆蓋時不產生還原點"   '[ ! -d "$HOME/.zsh-p10k-backups" ]'
fi

check ".zshrc.local 已產生"             '[ -f "$HOME/.zshrc.local" ]'
if [ -f "$HOME/.zshrc.local" ]; then
  check ".zshrc.local 內容全部註解掉" \
        '! grep -vE "^[[:space:]]*(#|$)" "$HOME/.zshrc.local" | grep -q .'
fi
check "PS1 / shopt 沒有被搬進 .zshrc.local" \
      '! grep -qE "^# *(PS1|shopt)" "$HOME/.zshrc.local" 2>/dev/null'
# 白名單處理過的工具不該再出現在 .zshrc.local。大小寫都要濾掉，
# 共用主機的 .bashrc 寫的是 PYENV_ROOT，只比對小寫的 pyenv 會漏。
check "白名單工具沒有被重複抽進 .zshrc.local" \
      '! grep -qiE "^# *export +(PYENV_ROOT|NVM_DIR|GOPATH)" "$HOME/.zshrc.local" 2>/dev/null'
# 腳本自己寫進 .bash_profile 的 hook 不能被自己抽回來，否則每重裝一次就多抽一次
check "沒有把自己寫的 hook 抽進 .zshrc.local" \
      '! grep -q "export SHELL=" "$HOME/.zshrc.local" 2>/dev/null'

echo "--- 第二次安裝（應該沒有變動） ---"
cp "$HOME/.zshrc" /tmp/zshrc.run1
[ -f "$HOME/.bash_profile" ] && cp "$HOME/.bash_profile" /tmp/bash_profile.run1
bash "$INSTALLER" -y > /tmp/run2.log 2>&1
RC2=$?
[ "$FIXTURE" = "hook-fallback" ] && \
check "第二次沒有改動 .bash_profile"    'cmp -s /tmp/bash_profile.run1 "$HOME/.bash_profile"'
# hook 內容一樣就不該拆掉重寫：不然每重跑一次就多一份 .bash_profile 備份。
[ "$FIXTURE" = "hook-fallback" ] && \
check "第二次沒有備份 .bash_profile"    '! grep -q "已備份 .*\.bash_profile" /tmp/run2.log'
[ "$FIXTURE" = "hook-fallback" ] && \
check "第二次沒有印「已移除 hook」"      '! grep -q "已移除 ~/.bash_profile" /tmp/run2.log'
check "第二次安裝結束碼為 0"            '[ "$RC2" -eq 0 ]'
check "第二次沒有改動 .zshrc"           'cmp -s /tmp/zshrc.run1 "$HOME/.zshrc"'
check "第二次回報「已經是最新狀態」"     'grep -q "已經是最新狀態" /tmp/run2.log'
check "沒有多產生 .zshrc.local.new"     '[ ! -f "$HOME/.zshrc.local.new" ] || [ "$FIXTURE" = "none" ]'

if [ "$FIXTURE" = "sticky-options" ]; then
  check "重跑時報告有講沿用了哪些選項"   'grep -q "沿用上次的選項" /tmp/run2.log'
  check "重跑沒帶 --no-chsh 也沒有改 shell" 'getent passwd tester | grep -q "bash$"'
  # 3.1.x 裝的機器沒有狀態檔。這時要從 head 區段把 omz 更新提示推回來。
  rm -f "$STATE_FILE"
  bash "$INSTALLER" -y > /tmp/run2b.log 2>&1
  check "沒有狀態檔時從 head 區段推回選項" 'cmp -s /tmp/zshrc.run1 "$HOME/.zshrc"'
  check "命令列明講時會覆蓋記下的選項" \
        'bash "$INSTALLER" -y --omz-update disabled > /tmp/run2c.log 2>&1 && grep -qx "omz_update=disabled" "$STATE_FILE"'

  # zsh-p10k update：從 release 抓最新的腳本，核對 SHA256SUMS，用記下的選項重跑。
  # 用 file:// 的假 release，裡面放的就是這次要測的腳本。
  mkdir -p /tmp/rel /tmp/relbad
  # 版本號換掉：這樣 update 跑到一半，正在執行的 zsh-p10k 本身會被新版改寫，這條路也要測到。
  sed 's/^SCRIPT_VERSION=".*"$/SCRIPT_VERSION="9.9.9"/' "$INSTALLER" > /tmp/rel/install-zsh-p10k.sh
  (cd /tmp/rel && sha256sum install-zsh-p10k.sh > SHA256SUMS)
  cp "$INSTALLER" /tmp/relbad/install-zsh-p10k.sh
  printf '%064d  install-zsh-p10k.sh\n' 0 > /tmp/relbad/SHA256SUMS
  cp "$HOME/.zshrc" /tmp/zshrc.preupd
  # 前面測過「沒有狀態檔」的情況，選項和 login shell 已經不是一開始那樣了，所以跟 update 前的狀態比。
  cp "$STATE_FILE" /tmp/state.preupd
  SHELL_PREUPD="$(getent passwd tester | cut -d: -f7)"
  ZSH_P10K_RELEASE_URL=file:///tmp/rel "$HOME/.local/bin/zsh-p10k" update -y > /tmp/upd.log 2>&1
  UPD_RC=$?
  check "zsh-p10k update 結束碼為 0"    '[ "$UPD_RC" -eq 0 ]'
  [ "$UPD_RC" -eq 0 ] || tail -15 /tmp/upd.log
  check "update 有核對 sha256"          'grep -q "sha256 核對通過" /tmp/upd.log'
  check "update 有講版本"               'grep -q "目前 .* → 最新 9.9.9" /tmp/upd.log'
  check "zsh-p10k 本身換成新版了"       '"$HOME/.local/bin/zsh-p10k" version | grep -q "9.9.9"'
  check "update 帶了 --update"          'grep -q "會 git pull 更新" /tmp/upd.log'
  check "update 沿用上次的選項"         'grep -qx "omz_update=disabled" "$STATE_FILE" && [ "$(grep -v "^version=" /tmp/state.preupd)" = "$(grep -v "^version=" "$STATE_FILE")" ]'
  check "update 沒有改 login shell"     '[ "$(getent passwd tester | cut -d: -f7)" = "$SHELL_PREUPD" ]'
  check "update 後 .zshrc 沒變"         'cmp -s /tmp/zshrc.preupd "$HOME/.zshrc"'
  check "update 沒留下暫存目錄"         '[ -z "$(find /tmp -maxdepth 1 -name "zsh-p10k-update.*" | head -1)" ]'
  ZSH_P10K_RELEASE_URL=file:///tmp/relbad "$HOME/.local/bin/zsh-p10k" update -y > /tmp/updbad.log 2>&1
  UPD_RC=$?
  check "sha256 對不上時停下來"         '[ "$UPD_RC" -ne 0 ] && grep -q "sha256 對不上" /tmp/updbad.log'
  check "sha256 對不上時沒有跑安裝"     '! grep -q "偵測環境" /tmp/updbad.log'
  ZSH_P10K_RELEASE_URL=file:///tmp/nowhere "$HOME/.local/bin/zsh-p10k" update -y > /tmp/updnone.log 2>&1
  UPD_RC=$?
  check "下載失敗時停下來並講清楚"     '[ "$UPD_RC" -ne 0 ] && grep -q "下載失敗" /tmp/updnone.log'
  USAGE_OUT="$("$HOME/.local/bin/zsh-p10k" 2>&1)"; USAGE_RC=$?
  check "zsh-p10k 不帶參數會印用法並回 2" '[ "$USAGE_RC" -eq 2 ] && printf "%s" "$USAGE_OUT" | grep -q "zsh-p10k update"'
fi

echo "--- 解除安裝 ---"
bash "$INSTALLER" --uninstall > /tmp/run3.log 2>&1
RC3=$?
check "解除安裝結束碼為 0"              '[ "$RC3" -eq 0 ]'
check ".zshrc 區段已移除"               '! grep -q "zsh-p10k-install:" "$HOME/.zshrc"'
check ".zshenv 區段已移除"              '! grep -q "zsh-p10k-install:" "$HOME/.zshenv" 2>/dev/null'
if [ "$FIXTURE" = "v2-with-user-edits" ]; then
  # 這個 fixture 用了 --clean-v2,v2 骨架是「刻意」被收走的，還原不回原檔是對的。
  # 要驗的是：收走的只有 v2 的行，使用者自己的一行都沒少。
  check "解除安裝後 v2 骨架確實不在了" \
        '! grep -q "User-local binaries, useful for no-sudo" "$HOME/.zshrc"'
  check "解除安裝後使用者的行都還在" \
        'grep -qF "$SENTINEL" "$HOME/.zshrc" && grep -q "pyenv init - zsh" "$HOME/.zshrc" \
         && grep -q "bash_aliases" "$HOME/.zshrc"'
elif [ -s /tmp/zshrc.orig ]; then
  if cmp -s /tmp/zshrc.orig "$HOME/.zshrc"; then
    ok "解除安裝後 .zshrc 與原檔位元組相同"
  else
    bad "解除安裝後 .zshrc 與原檔不同"
    diff -u /tmp/zshrc.orig "$HOME/.zshrc" | head -20
  fi
fi
check "oh-my-zsh 沒有被刪掉"            '[ -d "$HOME/.oh-my-zsh" ]'
check "~/.p10k.zsh 沒有被刪掉"          '[ -f "$HOME/.p10k.zsh" ]'
check "記錄選項的檔案已移除"            '[ ! -f "$STATE_FILE" ]'
check "zsh-p10k 指令已移除"             '[ ! -e "$HOME/.local/bin/zsh-p10k" ]'
if [ "$FIXTURE" = "dotfiles-symlink" ]; then
  check "解除安裝後 .zshrc 仍然是 symlink" '[ -L "$HOME/.zshrc" ]'
  check "解除安裝後 .zshenv 與原檔相同"   'cmp -s /tmp/zshenv.orig "$HOME/.zshenv"'
fi

if [ "$FIXTURE" = "hook-fallback" ]; then
  # 本來就有 .bash_profile、hook 加在它後面：--rollback 要連 hook 一起還原掉，
  # 不然 .zshrc 回到裝之前，開 bash 卻還是被切進 zsh。
  echo "--- 有 .bash_profile 時裝完再 --rollback ---"
  printf 'export MINE=1\n# keep\n' > "$HOME/.bash_profile"
  cp "$HOME/.bash_profile" /tmp/bash_profile.mine
  bash "$INSTALLER" -y > /tmp/run4.log 2>&1
  check "hook 加在既有的 .bash_profile"  'grep -q "zsh-p10k-install auto start" "$HOME/.bash_profile"'
  bash "$INSTALLER" --rollback -y > /tmp/rb4.log 2>&1
  check "--rollback 後 .bash_profile 回到裝之前" 'cmp -s /tmp/bash_profile.mine "$HOME/.bash_profile"'
  # .bash_profile 是安裝時才新建的：還原點裡沒有它，hook 會留著，要講怎麼拿掉。
  rm -f "$HOME/.bash_profile"
  bash "$INSTALLER" -y > /tmp/run6.log 2>&1
  bash "$INSTALLER" --rollback -y > /tmp/rb6.log 2>&1
  check "新建的 .bash_profile 留著 hook 時，rollback 會講要 --uninstall" 'grep -q "hook.*--uninstall" /tmp/rb6.log'
fi

if [ "$FIXTURE" = "has-desktop" ]; then
  # sha256sum 自己失敗（例如讀不了檔）：不能說「沒有 sha256sum」，也不能說「實際 」是空的。
  echo "--- sha256sum 讀檔失敗 ---"
  mkdir -p /tmp/shafail
  printf '#!/bin/sh\necho "sha256sum: $1: Input/output error" >&2\nexit 1\n' > /tmp/shafail/sha256sum
  chmod +x /tmp/shafail/sha256sum
  rm -f "$HOME/.local/share/fonts/MesloLGS-NF/MesloLGS NF Bold.ttf"
  PATH="/tmp/shafail:$PATH" bash "$INSTALLER" -y --no-chsh > /tmp/run5.log 2>&1
  check "沒有誤報「沒有 sha256sum」"      '! grep -q "沒有 sha256sum 也沒有 shasum" /tmp/run5.log'
  check "沒有印空的 sha256"               '! grep -q "實際 ）" /tmp/run5.log'
  check "講是算不出 sha256"               'grep -q "算不出 .*sha256" /tmp/run5.log'
  check "沒有留下沒驗過的字型"           '[ ! -e "$HOME/.local/share/fonts/MesloLGS-NF/MesloLGS NF Bold.ttf" ]'
fi

printf '\n\033[1m%s: %d passed, %d failed\033[0m\n' "$FIXTURE" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
