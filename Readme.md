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
| `-y` | 不等確認 |

`--omz-update` 和帶斜線的那幾組會被記住，要改就在命令列明講一次。

## 字型

p10k 的圖示要 MesloLGS NF 字型，而且要裝在**你眼睛看著的那個終端機**那一端
（MobaXterm、Windows Terminal…），不是 ssh 進去的那台。
腳本只在目標機真的有桌面時才替它裝；判斷時不看 `$DISPLAY`，因為 X11 forwarding 會讓沒桌面的伺服器也有值。

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
