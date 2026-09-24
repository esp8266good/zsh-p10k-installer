# zsh + oh-my-zsh + Powerlevel10k 安裝器

一支可以分享出去、能在陌生機器上安全重跑的安裝腳本。

## 安裝

```bash
curl -fsSL https://github.com/esp8266good/zsh-p10k-installer/releases/latest/download/install-zsh-p10k.sh -o ~/install-zsh-p10k.sh && bash ~/install-zsh-p10k.sh
```

這個網址永遠指向最新的 Release。要固定某一版,把 `latest/download` 換成
`download/v3.2.0` 之類的 tag。想先驗證檔案沒被動過:

```bash
cd ~ && curl -fsSLO https://github.com/esp8266good/zsh-p10k-installer/releases/latest/download/SHA256SUMS && sha256sum -c SHA256SUMS
```

腳本是單一檔案,不需要其他東西。目標機連不到 GitHub 的話,在別台下載好再
`scp` 過去也一樣能用(只是 oh-my-zsh 與 plugin 還是得從 GitHub clone)。

> ⚠ 有些機器的 `/tmp` 掛了 `noexec` 或不給寫,把腳本放家目錄比較保險。

先看它要做什麼、再決定跑不跑:

```bash
bash ~/install-zsh-p10k.sh --dry-run
```

### 跟舊版 v2 差在哪

| | V2 | V3 |
|---|---|---|
| `.zshrc` | 備份後**整份覆蓋** | 只寫入兩個標記包起來的區段,區段外不動 |
| 重跑 | 每跑一次就再覆蓋一次 | 沒變動就什麼都不做 |
| 已有 omz 的機器 | 骨架被換掉 | 自動切換到附加模式,骨架完全不碰 |
| 從 bash 繼承 | 無 | pyenv / conda / nvm / cargo / go 自動偵測;其餘 export 與 alias 抽到 `~/.zshrc.local` 並註解掉 |
| 套件安裝 | `apt update` + `apt install` | 缺才裝,永不 `upgrade`;非 Debian 系明確報錯而非硬幹 |
| 字型 | 一律裝在目標機 | 只有真的有桌面才裝;判準不看 `$DISPLAY`,因為 X11 forwarding 會騙人 |
| 備份 | 散在家目錄,權限跟著 umask 走 | 同一次執行整組存進 `~/.zsh-p10k-backups/<時間戳>/`,權限與原檔相同 |
| 回復 | 自己 `cp` | `--rollback`,還原本身也能再還原 |
| 重複插入 | 每跑一次多一份 | 使用者已經有的設定一律讓給他,讓掉哪幾項列在報告裡 |
| 解除安裝 | 無 | `--uninstall` |

V2 在樹莓派上把 4863 bytes 的 `.zshrc` 換成 1641 bytes,`HIST_STAMPS` 就此消失——
備份檔還在,但沒有人會回去讀它。V3 的 managed block 就是為了這件事。
理由寫在 [docs/adr/0001](docs/adr/0001-managed-block-instead-of-overwrite.md)。

### 選項

```
--dry-run             只印事前報告,不修改任何檔案
--update              順便更新已安裝的 oh-my-zsh / p10k / plugin(預設不更新)
--omz-update MODE     oh-my-zsh 自己的更新提示:prompt(預設) / auto / reminder / disabled
--uninstall           移除本腳本寫入的區段與 hook
--rollback            列出還原點,選一個把設定檔還原回去
--clean-v2            把 v2 寫進 .zshrc / .zshenv / .bash_profile 的東西收回來
--no-chsh             不改變 login shell(--chsh 取消)
--no-fonts            不在目標機安裝字型,即使這台真的有桌面(--fonts 取消)
--refresh-local       重新從 .bashrc 抽取 export / alias
--interactive-guard   在附加模式也插入非互動 shell 的提前 return(--no-interactive-guard 取消)
-y, --yes             不等待確認
```

`--omz-update`、`--no-chsh`、`--no-fonts`、`--interactive-guard` 會記在
`~/.config/zsh-p10k-install/options`。之後重跑沒帶這些旗標，就沿用上次的選擇，
事前報告會列出沿用了哪幾項。要改就在命令列明講一次。

### 出錯了想回去

```bash
bash ~/install-zsh-p10k.sh --rollback
```

每次真的改到檔案時,改動前的版本會整組存進 `~/.zsh-p10k-backups/<時間戳>/`,
權限跟原檔一樣、目錄本身 700。沒改到就不會產生還原點——重跑一次沒有變動時,
腳本會直接告訴你最近一個還原點在哪,不會讓你以為備份消失了。

還原本身也會先把當下的狀態存成一個新的還原點,所以還原完還可以再還原回來。

### 它會動哪些檔案

| 檔案 | 動作 |
|---|---|
| `~/.zshenv` | 寫入 `env` 區段:非互動 zsh 的 PATH |
| `~/.zshrc` | 寫入 `head` 與 `tail` 兩個區段 |
| `~/.zshrc.local` | 只在不存在時產生;一旦存在就完全屬於你 |
| `~/.p10k.zsh` | 只在不存在時寫入內建 template |
| `~/.oh-my-zsh` | 缺才裝 |
| `~/.bash_profile` | 只在 `chsh` 失敗時才加 auto-start hook |

`~/.zshenv` 跟 `~/.zshrc` 的分工很重要:**zsh 只有互動式 shell 會讀 `~/.zshrc`**。
`ssh host command`、scp、Claude Code / Codex 這類 agent 讀到的只有 `~/.zshenv`,
所以 PATH 放在那裡,而 `pyenv init` 這種需要 eval 的初始化留在 `~/.zshrc`。

### 在一批機器上鋪開

先看,再裝。`--dry-run` 不會碰任何檔案,而且會把這台的狀況講完:
它是不是真的有桌面、`.zshrc` 是誰寫的、有哪些設定因為你已經有了所以腳本不寫、
`chsh` 走不走得通。

```bash
for h in hostA hostB hostC; do
  scp install-zsh-p10k.sh $h:~/ && ssh $h 'bash ~/install-zsh-p10k.sh --dry-run'
done
```

看過報告再實際裝:

```bash
ssh -t hostA 'bash ~/install-zsh-p10k.sh'
```

`ssh -t` 那個 `-t` 有差。沒有它就沒有 tty,`chsh` 問不了密碼,腳本只能退而改裝
`~/.bash_profile` hook —— 能用,但 login shell 沒真的換掉。報告會事先告訴你會走哪一條。

**裝過 v2 的機器**要多一個旗標。v2 把 oh-my-zsh 骨架直接寫進 `.zshrc`,
那些行現在算在「使用者區段」裡,腳本預設繞著它們走,結果就是同一段設定存在兩份:

```bash
ssh -t hostA 'bash ~/install-zsh-p10k.sh --dry-run --clean-v2'   # 先看它要收走什麼
ssh -t hostA 'bash ~/install-zsh-p10k.sh --clean-v2'
```

判定很嚴格:v2 那 30 行骨架要全部都在、順序一致,而且不能有 oh-my-zsh 官方 template
的特徵註解,才會被收走。判不出來就什麼都不做 —— 誤判的代價是弄壞別人的 `.zshrc`,
所以寧可漏抓。收走的只有 v2 的行,你自己插在中間的一行都不會少。

**一個要自己選的預設**:`--omz-update` 預設 `prompt`,也就是 oh-my-zsh 出廠行為 ——
每 13 天在你登入時問一次要不要更新。如果你跟我一樣覺得那會擋畫面,
裝的時候加 `--omz-update reminder`(只提醒)或 `--omz-update disabled`(完全關掉)。

### 開發

腳本本體是 `install-zsh-p10k.sh.in`。95 KB 的 `.p10k.zsh` template 會被壓成
約 28 KB 的 base64 內嵌進去,產生單檔的 `dist/install-zsh-p10k.sh`(不進 git):

```bash
./build.sh                    # 產生單檔腳本,並驗證 payload 解得回原檔
./tests/run-fixtures.sh       # 每種初始狀態各開一個容器,跑完整流程(需要 docker)
./tests/run-fixtures.sh native-omz   # 只跑一個
```

發版:改 `install-zsh-p10k.sh.in` 裡的 `SCRIPT_VERSION`,commit 之後打同名 tag 推上去。
CI 會 build、跑 shellcheck 與全部 fixture,都過了才建立 Release,附上腳本與 `SHA256SUMS`。
tag 跟 `SCRIPT_VERSION` 對不上的話 CI 會直接失敗。

```bash
git tag v3.2.0 && git push origin main v3.2.0
```

每個 fixture 各自對應一種在真實機器上踩到過的狀況。每個都會驗證
「裝 → 重跑不變動 → 還原點回得去 → 解除安裝後與原檔位元組相同」。

| fixture | 對應的真實狀況 | 它擋住的回歸 |
|---|---|---|
| `fresh-bash` | 純 bash 的新機器 | — |
| `zsh-no-omz` | 有 zsh 沒 oh-my-zsh | 非互動 zsh 拿不到 PATH |
| `v2-installed` | v2 裝過,骨架逐字未動 | 誤判成非 v2 產物 |
| `v2-with-user-edits` | 樹莓派:使用者的行夾在 v2 骨架中間 | 剔除 v2 時吃掉使用者的 `fi` |
| `native-omz` | 工作站:手寫的完整 omz 設定 | 把使用者的骨架當成 v2 收走 |
| `has-desktop` | 真的有桌面的機器 | 該裝字型卻跳過 |
| `forwarded-display` | 沒桌面,但 ssh 帶了 X11 forwarding | `$DISPLAY` 有值就誤判成有圖形介面 |
| `hook-fallback` | 共用主機:sudo 要密碼又沒有 tty | 新建 `.bash_profile` 讓 `.profile` 靜靜失效 |
| `ancient-awk` | 樹莓派的 mawk 1.3.3(1996) | `[[:space:]]` 靜默不匹配,抽取整個失效 |
| `dotfiles-symlink` | `.zshrc` 是 stow / chezmoi 建的 symlink | symlink 被換成一般檔案,dotfile repo 收不到改動 |
| `sticky-options` | 第一次帶了 `--omz-update reminder --no-chsh`,之後重跑都不帶 | 選項悄悄變回預設值 |

`ancient-awk` 要另外拉一份 `debian:buster` 映像,慢一點,但那是唯一能複現
「regex 不報錯、只是永遠不成立」的方法 —— 在 gawk 或 mawk 1.3.4 的機器上
怎麼測都是綠的。`build.sh` 另外會掃描腳本裡所有 awk 程式,
出現 POSIX 字元類別就讓建置失敗。

