# zsh-p10k-installer

裝好 zsh + oh-my-zsh + Powerlevel10k，而且重跑幾次都不會弄丟你原本的設定。

```bash
curl -fsSL https://github.com/esp8266good/zsh-p10k-installer/releases/latest/download/install-zsh-p10k.sh -o ~/install-zsh-p10k.sh && bash ~/install-zsh-p10k.sh
```

腳本動手前會先印一份報告（偵測到什麼、要改哪些檔案、要跑哪些 sudo 指令），按 Enter 才開始。
只想看報告：`bash ~/install-zsh-p10k.sh --dry-run`。

> ⚠ 有些機器的 `/tmp` 掛了 `noexec` 或不給寫，所以腳本放家目錄。

## 為什麼可以放心重跑

腳本在 `~/.zshrc` 裡只擁有兩段用標記包起來的區段（`# >>> zsh-p10k-install: head >>>` 那種），
重跑時只重寫區段裡面，區段外你寫的東西一行都不碰。沒有變動就什麼都不做。

| 情況 | 腳本怎麼處理 |
|---|---|
| 你已經自己設定好 oh-my-zsh | 不寫骨架，只補兩個區段 |
| 你已經有某項設定（`HIST_STAMPS`、instant prompt…） | 讓給你，不寫第二份，報告裡列出讓掉哪些 |
| `.bashrc` 裡有 pyenv / conda / nvm / cargo / go | 產生這些工具官方的 zsh 寫法 |
| `.bashrc` 裡其他的 export 與 alias | 抄進 `~/.zshrc.local`，全部註解掉，你確認後自己打開 |
| `.zshrc` 是 stow / chezmoi 建的 symlink | 寫進它指到的檔案，symlink 不動 |
| 上次裝的時候帶了 `--omz-update reminder` 之類的選項 | 記在 `~/.config/zsh-p10k-install/options`，重跑沒帶也沿用 |

套件只在缺的時候才裝，永遠不跑 `apt upgrade`。

## 之後要更新

```bash
zsh-p10k update        # 加 -y 就不等確認
```

它會下載最新版的安裝腳本和 `SHA256SUMS`，核對 sha256 之後帶 `--update` 重跑，選項沿用上次安裝時的。
`SHA256SUMS` 跟腳本是從同一個 Release 下載的，所以它擋得住下載壞掉，擋不住有人換掉整個 Release。
這個指令放在 `~/.local/bin/zsh-p10k`，bash 裡也跑得了（zsh 設定壞掉時可以拿來修）。

## 出錯了想回去

```bash
bash ~/install-zsh-p10k.sh --rollback     # 選一個還原點，把設定檔還原回去
bash ~/install-zsh-p10k.sh --uninstall    # 移除腳本寫入的區段與 hook
```

每次真的改到檔案，改動前的版本會整組存進 `~/.zsh-p10k-backups/<時間戳>/`，
權限跟原檔一樣，目錄本身 700。還原之前也會先存一個還原點，所以還原完還能再還原回來。

## 它會動哪些檔案

| 檔案 | 動作 |
|---|---|
| `~/.zshenv` | 寫入 `env` 區段：PATH |
| `~/.zshrc` | 寫入 `head` 與 `tail` 兩個區段 |
| `~/.zshrc.local` | 只在不存在時產生，之後完全屬於你 |
| `~/.p10k.zsh` | 只在不存在時寫入內建的設定 |
| `~/.oh-my-zsh` | 缺才裝 |
| `~/.bash_profile` | 只在 `chsh` 失敗時加一段自動切到 zsh 的 hook |
| `~/.local/bin/zsh-p10k` | `zsh-p10k update` 指令，每次安裝時更新 |

PATH 放在 `~/.zshenv` 是因為 **zsh 只有互動式 shell 會讀 `~/.zshrc`**。
`ssh host command`、scp、Claude Code 這類 agent 只讀得到 `~/.zshenv`。

## 選項

| 選項 | 作用 |
|---|---|
| `--dry-run` | 只印報告，不改任何檔案 |
| `--update` | 順便 `git pull` 已安裝的 oh-my-zsh / p10k / plugin（預設不更新） |
| `--omz-update MODE` | oh-my-zsh 的更新提示：`prompt`（預設，每 13 天問一次）/ `auto` / `reminder` / `disabled` |
| `--no-chsh` / `--chsh` | 不改 login shell / 取消上次的 `--no-chsh` |
| `--no-fonts` / `--fonts` | 不裝字型 / 取消上次的 `--no-fonts` |
| `--interactive-guard` / `--no-interactive-guard` | 在已有 oh-my-zsh 的機器也加上「非互動 shell 直接 return」 |
| `--refresh-local` | 重新從 `.bashrc` 抽取 export / alias |
| `--clean-v2` | 收回舊版 v2 寫進去的設定，見 [docs/upgrading-from-v2.md](docs/upgrading-from-v2.md) |
| `--iterm2` / `--no-iterm2` | 只有 macOS：沒有 iTerm2 就直接裝 / 不問也不裝 |
| `--iterm2-profile` / `--no-iterm2-profile` | 只有 macOS：加一個用 MesloLGS NF 的 iTerm2 profile / 不問也不加 |
| `-y` | 不等確認。所有 `[y/N]` 的問題都照預設答案「不要」走，要裝 iTerm2 請明講 `--iterm2` |

`--omz-update` 和 `--no-chsh` 這類用斜線列出的成對選項會被記住，要改就在命令列明講一次。iTerm2 那兩組不會記住，每次都要明講。

## 字型

p10k 的圖示要 MesloLGS NF 字型，而且要裝在**你眼睛看著的那個終端機**那一端
（MobaXterm、Windows Terminal…），不是 ssh 進去的那台。
腳本只在目標機真的有桌面時才替它裝；判斷時不看 `$DISPLAY`，因為 X11 forwarding 會讓沒桌面的伺服器也有值。

## macOS

支援 macOS 13 以上，Apple silicon 和 Intel 都可以。用的是 macOS 內建的 zsh、git、curl，
**不裝 Homebrew，也不會用 sudo**。安裝指令跟上面一樣。

| 情況 | 腳本怎麼處理 |
|---|---|
| 沒有 Command Line Tools（git 一執行就跳安裝視窗） | 有 tty：問你要不要叫出 Apple 的安裝視窗，裝好就自動繼續。沒有 tty：說明要先跑 `xcode-select --install`，什麼都不改就結束 |
| 字型 | 裝到 `~/Library/Fonts`，已經有同名檔案就不重下載 |
| 沒有 iTerm2 | 問你要不要裝官方 3.7.7（核對 sha256 和簽章，放進 `/Applications`；那裡不能寫就放 `~/Applications`）。沒有 tty 就不裝 |
| 有 iTerm2 | 問你要不要加一個字型設成 MesloLGS NF 的 profile。**不會改你原本的 profile**，也不會把它設成預設 |

新的 profile 叫「zsh-p10k (MesloLGS NF)」。要讓新視窗都用它：iTerm2 → Settings → Profiles，選它，按 Other Actions → Set as Default。
不想要了就刪掉 `~/Library/Application Support/iTerm2/DynamicProfiles/zsh-p10k.json`。

macOS 開新視窗是 login shell，會跑 `/etc/zprofile` 裡的 `path_helper`，每次都把 `~/.zshenv` 加的目錄排到 `/usr/bin` 後面
（在 macOS 上實測過）。所以 `~/.zshrc` 的 head 區段會把 `~/.zshenv` 讀完時就在的家目錄底下的目錄（`~/.local/bin`、`~/bin`、pyenv、cargo…）排回最前面，
`~/.local/bin` 裡自己裝的指令就不會被系統的同名指令蓋掉。
`~/.zprofile` 裡加的目錄和系統目錄的順序不動：你在那裡加的 Homebrew 還是排在 `/usr/bin` 前面，刻意加在最後面的也還是在最後面。

## Windows 10 / 11

在 [Git for Windows](https://git-scm.com/downloads/win) 的 **Git Bash** 裡執行上面的安裝指令。
**不需要 WSL、虛擬化，也不需要系統管理員權限。**

| 情況 | 腳本怎麼處理 |
|---|---|
| zsh | Git Bash 沒有 zsh，腳本下載 MSYS2 編好的 zsh（核對 sha256），解開放在 `~/.local/zsh-msys` |
| 開 Git Bash 時自動進 zsh | Windows 沒有 `chsh`，改在 `~/.bash_profile` 加一段 hook。VS Code 裡的 Git Bash 也會切。設 `DISABLE_AUTO_ZSH=1` 可以繞過 |
| 字型 | 裝到這個 Windows 帳號的字型目錄並登錄，然後要自己把終端機字型改成 MesloLGS NF（結尾會教） |
| Windows Terminal | 多一個「Git Bash (zsh)」設定檔，字型已經是 MesloLGS NF。用 Windows Terminal 的 fragment 加，**不動你的 `settings.json`**；`--uninstall` 會拿掉 |

只支援 Git Bash。PowerShell 和 cmd 不會變成 zsh。

家目錄路徑有中文、日文、泰文這類字元時（Windows 的中文帳號最常見，Linux、macOS 也一樣），
zsh 本身寫不了這種路徑下的編譯檔和快取，p10k 每開一個視窗就會印一串錯誤。
（`josé`、`müller` 這類路徑沒有這個問題，不受影響。）
腳本會在動手前講，然後在安裝時用相對路徑先把 p10k 編好，並關掉 p10k 寫快取的動作，開新視窗就不會再印錯誤。
代價是 p10k 的 instant prompt（先畫出提示列、其餘在背景載入）在這種帳號下沒辦法用，開新視窗時提示列會晚一點出現。
之後要更新 p10k 請用 `zsh-p10k update`（或重跑安裝腳本加 `--update`），不要自己 `git pull`，不然錯誤會回來。

## 一次裝很多台

```bash
for h in hostA hostB; do scp ~/install-zsh-p10k.sh $h:~/ && ssh $h 'bash ~/install-zsh-p10k.sh --dry-run'; done
ssh -t hostA 'bash ~/install-zsh-p10k.sh'
```

`-t` 不能省：沒有 tty，`chsh` 就問不了密碼，腳本只能改裝 `~/.bash_profile` hook。報告會事先講它會走哪一條。

目標機連不到 GitHub 的話，腳本本身 scp 過去就能跑，但 oh-my-zsh 和 plugin 還是得從 GitHub clone。

## 更多

- 從舊版 v2 升級：[docs/upgrading-from-v2.md](docs/upgrading-from-v2.md)
- 開發、測試、發版：[docs/development.md](docs/development.md)
- 名詞定義：[CONTEXT.md](CONTEXT.md)
