#!/usr/bin/env bash
# 在容器裡跑一個 fixture:佈置初始狀態 → 安裝 → 驗證 → 重跑驗證冪等 → 解除安裝驗證還原。
# 用法: incontainer.sh <fixture-name> <installer-path>
# check() 用 eval 跑字串,shellcheck 看不到字串裡用到的變數。
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
# 必須逐字——v3.1 的 v2 骨架判定要求這 40 行全中且順序一致,少一行註解就判不出來。
# 之前這裡是「大意相同」的簡化版,結果新判定把它當成非 v2 產物,測不到 --clean-v2。
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

# 重現樹莓派:v2 骨架 + 使用者自己插在「骨架中間」的行。
#
# 關鍵是最後那個 `if [ -f ~/.bash_aliases ]; then … fi` —— 它的 fi 跟骨架裡的 fi
# 一字不差。按文字刪 v2 的行會刪掉它,留下孤兒 if,zsh -n 就會炸。
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

# 有桌面的機器:xsessions 裡真的有 session 檔。
seed_desktop() {
  sudo mkdir -p /usr/share/xsessions
  echo '[Desktop Entry]' | sudo tee /usr/share/xsessions/LXDE.desktop >/dev/null
}

# 沒有桌面,但 ssh 帶了 X11 forwarding —— DISPLAY 有值。
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
      ;;
    forwarded-display)
      sudo apt-get install -y -qq --no-install-recommends zsh >/dev/null 2>&1
      seed_forwarded_display
      seed_extra_bashrc
      ;;
    hook-fallback)
      # chsh 走不通時的退路。把 zsh 從 /etc/shells 拿掉就會逼出這條路徑,
      # 不必真的去弄一顆自編的 zsh。
      sudo apt-get install -y -qq --no-install-recommends zsh >/dev/null 2>&1
      sudo sed -i '/zsh/d' /etc/shells
      # 這台有 .profile 但沒有 .bash_profile —— 共用主機就是這個形狀。
      # bash 的 login shell 只讀第一個存在的,憑空生一個 .bash_profile
      # 會讓整份 .profile 靜靜地失效。
      rm -f "$HOME/.bash_profile"
      cat > "$HOME/.profile" <<'EOF'
export PROFILE_SENTINEL=must-survive
EOF
      seed_extra_bashrc
      ;;
    dotfiles-symlink)
      # stow / chezmoi 的形狀:.zshrc 與 .zshenv 都是指進 dotfile repo 的 symlink。
      # 用 mv 蓋掉的話 symlink 會變成一般檔案,dotfile repo 就此收不到改動。
      sudo apt-get install -y -qq --no-install-recommends zsh >/dev/null 2>&1
      mkdir -p "$HOME/dotfiles"
      printf '# my dotfiles zshrc\n%s\n' "$SENTINEL" > "$HOME/dotfiles/zshrc"
      printf 'export DOTFILES_ENV=1\n' > "$HOME/dotfiles/zshenv"
      ln -s dotfiles/zshrc "$HOME/.zshrc"
      ln -s dotfiles/zshenv "$HOME/.zshenv"
      seed_extra_bashrc
      ;;
    sticky-options)
      # 第一次帶了選項,之後重跑都不帶。選項必須被記住,不能悄悄變回預設值。
      sudo apt-get install -y -qq --no-install-recommends zsh >/dev/null 2>&1
      printf '# existing zshrc\n%s\n' "$SENTINEL" > "$HOME/.zshrc"
      seed_extra_bashrc
      EXTRA_ARGS="--omz-update reminder --no-chsh"
      ;;
    ancient-awk)
      # 這個 fixture 只在 debian:buster 映像上跑,那裡的 awk 是 mawk 1.3.3。
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
# 備份的權限必須跟原檔一樣。少了 cp -p 的話 600 的 .zshrc 會備份成 644,
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
  bad "安裝結束碼為 0(實際 $RC1)"
  tail -30 /tmp/run1.log
else
  ok "安裝結束碼為 0"
fi

ZSH_BIN="$(command -v zsh || echo /usr/bin/zsh)"

check ".zshrc 存在"                     '[ -s "$HOME/.zshrc" ]'
check ".zshrc 語法正確 (zsh -n)"        '"$ZSH_BIN" -n "$HOME/.zshrc"'
check "head 區段只有一個"               '[ "$(count "$HOME/.zshrc" "# >>> zsh-p10k-install: head >>>")" = 1 ]'
check "tail 區段只有一個"               '[ "$(count "$HOME/.zshrc" "# >>> zsh-p10k-install: tail >>>")" = 1 ]'
check "instant prompt 區段只有一個"     '[ "$(grep -c "^if \[\[ -r \"\${XDG_CACHE_HOME" "$HOME/.zshrc")" = 1 ]'
check "oh-my-zsh.sh 只被 source 一次"   '[ "$(grep -cE "^[[:space:]]*(source|\.)[[:space:]]+.*oh-my-zsh\.sh" "$HOME/.zshrc")" = 1 ]'
check "MobaXterm bindkey 有寫入"        'grep -q "beginning-of-line" "$HOME/.zshrc"'
check ".bash_aliases 有被 source"       'grep -q "\.bash_aliases" "$HOME/.zshrc"'
# PATH 現在只寫在 .zshenv。head 區段刻意不再寫第二份:.zshenv 一定先讀,
# 放 .zshrc 是純粹多餘,而且每個互動 shell 都會把那三個目錄重新推到最前面。
check "PATH 那一行寫在 .zshenv"         'grep -qF "export PATH=\$HOME/bin:\$HOME/.local/bin:/usr/local/bin:\$PATH" "$HOME/.zshenv"'
check "head 區段沒有重複 PATH"          '[ "$(sed -n "/head >>>/,/head <<</p" "$HOME/.zshrc" | grep -cF "export PATH=\$HOME/bin")" = 0 ]'
check "head 區段沒有重複 typeset -U"    '[ "$(sed -n "/head >>>/,/head <<</p" "$HOME/.zshrc" | grep -c "^typeset -U path PATH$")" = 0 ]'
[ "$FIXTURE" != "sticky-options" ] && \
check "omz 更新提示預設為 prompt"       'grep -q "zstyle .:omz:update. mode prompt" "$HOME/.zshrc" || grep -q "已經有,所以我們不寫" /tmp/run1.log'
check "~/.p10k.zsh 已產生且夠大"        '[ "$(wc -c < "$HOME/.p10k.zsh")" -gt 90000 ]'
check "互動式 zsh 能載入"               '"$ZSH_BIN" -i -c "print READY" 2>/dev/null | grep -q READY'
check "備份沒有散在家目錄"              '! find "$HOME" -maxdepth 1 -name ".zshrc.backup.*" | grep -q .'

case "$FIXTURE" in
  v2-installed|native-omz)
    check "偵測為附加模式"              'grep -q "附加模式" /tmp/run1.log'
    check "使用者原有內容保留 (sentinel)" 'grep -qF "$SENTINEL" "$HOME/.zshrc"'
    ;;
  sticky-options)
    check "偵測為完整模式"              'grep -q "完整模式" /tmp/run1.log'
    check "--no-chsh 生效,login shell 維持 bash" 'getent passwd tester | grep -q "bash$"'
    ;;
  hook-fallback)
    check "偵測為完整模式"              'grep -q "完整模式" /tmp/run1.log'
    # 這個 fixture 刻意讓 chsh 走不通,所以 login shell 應該「維持 bash」。
    # 事前報告也必須先講出來,而不是承諾改 shell 然後失敗。
    check "login shell 維持 bash"       'getent passwd tester | grep -q "bash$"'
    check "報告事先講明 chsh 走不通"     'grep -q "chsh 走不通" /tmp/run1.log'
    ;;
  *)
    check "偵測為完整模式"              'grep -q "完整模式" /tmp/run1.log'
    check "login shell 已改成 zsh"      'getent passwd tester | grep -q "zsh$"'
    ;;
esac

case "$FIXTURE" in
  native-omz)
    check "pyenv 被判定為已存在而跳過"  'grep -q "已在 .zshrc 裡,跳過.*pyenv" /tmp/run1.log'
    check "nvm 被判定為已存在而跳過"    'grep -q "已在 .zshrc 裡,跳過.*nvm" /tmp/run1.log'
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
    # 這幾條是 --clean-v2 唯一會弄壞使用者檔案的路徑,一條都不能少
    check "使用者的 bash_aliases if/fi 完整" \
          '[ "$(grep -c "^if \[ -f ~/.bash_aliases \]; then$" "$HOME/.zshrc")" -ge 1 ]'
    check "使用者的 pyenv 行還在"       'grep -q "eval \"\$(pyenv init - zsh)\"" "$HOME/.zshrc"'
    check "p10k configure 寫的那行還在" 'grep -qF "[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh" "$HOME/.zshrc"'
    check "使用者原有內容保留 (sentinel)" 'grep -qF "$SENTINEL" "$HOME/.zshrc"'
    check "沒有孤兒 fi(zsh -n 已驗)"   '"$ZSH_BIN" -n "$HOME/.zshrc"'
    ;;
  has-desktop)
    check "判定為有桌面"                'grep -q "桌面環境        這台有" /tmp/run1.log'
    check "字型有安裝"                  '[ -d "$HOME/.local/share/fonts/MesloLGS-NF" ]'
    ;;
  forwarded-display)
    # DISPLAY 有值但機器沒有桌面 —— 舊版就是在這裡把一台工作站判成「有圖形介面」的
    check "DISPLAY 有值不會騙過偵測"    'grep -q "桌面環境        沒有" /tmp/run1.log'
    check "沒有裝字型"                  '[ ! -d "$HOME/.local/share/fonts/MesloLGS-NF" ]'
    ;;
  hook-fallback)
    check "chsh 走不通時改裝 hook"      'grep -q "zsh-p10k-install auto start" "$HOME/.bash_profile"'
    # 新生的 .bash_profile 必須把 .profile 讀回來,否則使用者的 PATH / proxy /
    # conda 會在下次登入時無聲消失
    check "新建的 .bash_profile 有 source .profile" \
          'grep -q "\. ~/.profile" "$HOME/.bash_profile"'
    check ".profile 的內容仍然生效"     'bash -lc "echo \$PROFILE_SENTINEL" | grep -q must-survive'
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
    check "抽取真的有跑到(抓到自訂的 export)" \
          'grep -q "MY_CUSTOM_VAR" "$HOME/.zshrc.local"'
    check "發行版預設 alias 被濾掉"      '! grep -q "alias l=.ls -CF" "$HOME/.zshrc.local"'
    ;;
esac

# --- 還原點 ---
# 本來沒有 .zshrc 的機器不會產生還原點:沒有東西被覆蓋,備份也就沒有意義。
if [ -n "$ORIG_MODE" ]; then
  check "還原點目錄已建立"              '[ -d "$HOME/.zsh-p10k-backups" ]'
  # 同一次執行改到的檔案必須在同一個還原點。拆成兩個的話,--rollback 選哪個都只還原一半。
  check "同一次安裝只產生一個還原點"     '[ "$(find "$HOME/.zsh-p10k-backups" -mindepth 1 -maxdepth 1 -type d | wc -l)" = 1 ]'
  if [ -f /tmp/zshenv.orig ]; then
    check "還原點裡同時有 .zshrc 與 .zshenv" \
          '[ -f "$(find "$HOME/.zsh-p10k-backups" -mindepth 1 -maxdepth 1 -type d)/.zshenv" ]'
  fi
  check "還原點目錄權限為 700"          '[ "$(stat -c "%a" "$HOME/.zsh-p10k-backups")" = 700 ]'
  check "備份權限與原檔相同 ($ORIG_MODE)" \
        '[ "$(stat -c "%a" "$(find "$HOME/.zsh-p10k-backups" -name .zshrc | head -1)")" = "$ORIG_MODE" ]'
  check ".zshrc 權限沒有被偷改"          '[ "$(stat -L -c "%a" "$HOME/.zshrc")" = "$ORIG_MODE" ]'
  check "--rollback 找得到還原點"        'bash "$INSTALLER" --rollback -y > /tmp/rb.log 2>&1 && grep -q "已還原" /tmp/rb.log'
  check "還原後 .zshrc 與安裝前相同"     'cmp -s /tmp/zshrc.orig "$HOME/.zshrc"'
  [ -f /tmp/zshenv.orig ] && \
  check "還原後 .zshenv 與安裝前相同"    'cmp -s /tmp/zshenv.orig "$HOME/.zshenv"'
  [ "$FIXTURE" = "dotfiles-symlink" ] && \
  check "還原後 .zshrc 仍然是 symlink"   '[ -L "$HOME/.zshrc" ]'
  # 還原本身也要能反悔:還原前的狀態要另外存成一個新的還原點
  check "還原前的狀態有被存起來"         '[ "$(find "$HOME/.zsh-p10k-backups" -mindepth 1 -maxdepth 1 -type d | wc -l)" -ge 2 ]'
  # 還原完再裝回去,後面的冪等與解除安裝測試才有東西可測
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
# 白名單處理過的工具不該再出現在 .zshrc.local。大小寫都要濾掉——
# 共用主機的 .bashrc 寫的是 PYENV_ROOT,只比對小寫的 pyenv 會漏。
check "白名單工具沒有被重複抽進 .zshrc.local" \
      '! grep -qiE "^# *export +(PYENV_ROOT|NVM_DIR|GOPATH)" "$HOME/.zshrc.local" 2>/dev/null'
# 腳本自己寫進 .bash_profile 的 hook 不能被自己抽回來,否則每重裝一次就多抽一次
check "沒有把自己寫的 hook 抽進 .zshrc.local" \
      '! grep -q "export SHELL=" "$HOME/.zshrc.local" 2>/dev/null'

echo "--- 第二次安裝(冪等) ---"
cp "$HOME/.zshrc" /tmp/zshrc.run1
bash "$INSTALLER" -y > /tmp/run2.log 2>&1
RC2=$?
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
fi

echo "--- 解除安裝 ---"
bash "$INSTALLER" --uninstall > /tmp/run3.log 2>&1
RC3=$?
check "解除安裝結束碼為 0"              '[ "$RC3" -eq 0 ]'
check ".zshrc 區段已移除"               '! grep -q "zsh-p10k-install:" "$HOME/.zshrc"'
check ".zshenv 區段已移除"              '! grep -q "zsh-p10k-install:" "$HOME/.zshenv" 2>/dev/null'
if [ "$FIXTURE" = "v2-with-user-edits" ]; then
  # 這個 fixture 用了 --clean-v2,v2 骨架是「刻意」被收走的,還原不回原檔是對的。
  # 要驗的是:收走的只有 v2 的行,使用者自己的一行都沒少。
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
if [ "$FIXTURE" = "dotfiles-symlink" ]; then
  check "解除安裝後 .zshrc 仍然是 symlink" '[ -L "$HOME/.zshrc" ]'
  check "解除安裝後 .zshenv 與原檔相同"   'cmp -s /tmp/zshenv.orig "$HOME/.zshenv"'
fi

printf '\n\033[1m%s: %d passed, %d failed\033[0m\n' "$FIXTURE" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
