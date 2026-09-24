# zsh + oh-my-zsh + Powerlevel10k 安裝器

一支可以分享出去、能在陌生機器上安全重跑的安裝腳本。核心約束：**目標機器上原本就有的東西不能弄丟**。

## Language

### 安裝器怎麼看待目標機器

**目標機**：
腳本實際執行的那台機器。與「終端機」不同：使用者多半是 ssh 進目標機的。
_Avoid_: 遠端、伺服器、本機

**終端機**：
使用者眼睛真正看著的那個程式（MobaXterm、GNOME Terminal、Windows Terminal）。
字型只在終端機這一端才有意義。
_Avoid_: 前端、client、本地

**事前報告**：
腳本動手前印出的一份清單：偵測到什麼、打算改哪些檔案、要跑哪些需要 sudo 的指令。
_Avoid_: preview、summary、確認畫面

**支援環境**：
腳本願意動手的機器。目前定義為：Debian 系（有 `apt-get`），或已經有 zsh 可用的任何機器。
其餘（Alpine、以及認不得套件管理器又沒有 zsh 的機器）一律明確報錯退出，不做部分安裝。
_Avoid_: 相容性、平台

### `.zshrc` 的所有權

**managed block**：
`.zshrc` 裡由腳本擁有的區段，以固定標記包起來。區段外的一切都是使用者的，腳本永不修改。
重跑時只重寫區段內容，這是「安全重跑」的唯一機制。
_Avoid_: 我們的區塊、腳本區段、template 區

**env block**：
`.zshenv` 裡的 managed block。`.zshenv` 是每一次 zsh 啟動都會讀的檔案，包含
`ssh host command`、scp、agent、CI 這些非互動情境。而 **`.zshrc` 只有互動式 shell 會讀**，
所以任何非互動也需要的 PATH 只能放在這裡。
反過來說這裡只放環境變數與 PATH：會輸出東西、或需要 eval / source 的初始化都不能放。
_Avoid_: 環境檔、全域設定

**head block**：
插在 `.zshrc` 最上面的 managed block。放需要在 oh-my-zsh 載入之前生效的東西，
以及 p10k instant prompt。位置由 p10k 的硬性要求決定：instant prompt 之前不能有任何輸出。
_Avoid_: 前置區、上半部

**tail block**：
附加在 `.zshrc` 最下面的 managed block。放必須在 oh-my-zsh 載入之後才生效的東西。
_Avoid_: 後置區、下半部

**完整模式**：
目標機的 `.zshrc` 還沒載入過 oh-my-zsh 時採用的模式。此時 managed block 內含完整的
oh-my-zsh 骨架（theme、plugins、載入指令）。
_Avoid_: 全新安裝、fresh install、覆蓋模式

**附加模式**：
目標機的 `.zshrc` 已經自己載入 oh-my-zsh 時採用的模式。腳本不寫任何骨架，
只補 head 與 tail 兩個 block，使用者原有的 theme 與 plugins 設定完全不動。
_Avoid_: 增量安裝、merge 模式、升級模式

### 從 bash 帶過來的東西

**繼承**：
把使用者在 bash 底下已經有的設定，變成在 zsh 底下同樣能用。
這個詞在本專案永遠指下面兩種具體做法之一，不可以單獨使用。
_Avoid_: 遷移、轉換、同步

**白名單繼承**：
針對認得出來的工具（pyenv、conda、nvm、cargo 等），產生該工具**官方的 zsh 寫法**。
不是搬運 bash 的那一行，因為多數工具的 zsh 初始化寫法與 bash 不同。
_Avoid_: 偵測安裝、自動設定

**抽取繼承**：
把 `.bashrc` 系列裡認不出歸屬的 `export`、`alias`、函式抄進 `.zshrc.local`，
但**全部註解掉**，由使用者自己確認後取消註解。
腳本不保證抄過來的東西在 zsh 底下語意正確，所以預設不生效。
_Avoid_: 自動搬遷、匯入

**`.zshrc.local`**：
抽取繼承的產物，也是使用者放個人設定的地方。
一旦這個檔案存在，它就完全屬於使用者，腳本永不覆蓋。
_Avoid_: 使用者設定檔、custom.zsh

**讓步**：
使用者區段裡已經有等價設定時，腳本就不寫自己那一份，值也照使用者的，不覆蓋。
這是「同一行被插兩次」的唯一防線，涵蓋 instant prompt、`source ~/.p10k.zsh`、
interactive guard、bindkey、`HIST_STAMPS`、`zstyle ':omz:update'`、
`source ~/.bash_aliases`、`source ~/.zshrc.local`，以及 `.zshenv` 裡的
`typeset -U` 與 PATH 那一行。讓掉了哪幾項會列在事前報告裡。
_Avoid_: 去重、跳過、偵測

### 這台機器與你手邊的終端機

**有桌面**：
這台機器裝了桌面環境，判斷方式是 `/usr/share/xsessions` 或 `/usr/share/wayland-sessions`
裡真的有 session 檔，或者存在 display manager。這是決定「字型要不要裝在這台」的唯一依據。
刻意不看 `$DISPLAY` 與 `$WAYLAND_DISPLAY`：sshd 開了 X11Forwarding 的話，
從終端機連進來就會把 `DISPLAY` 設成 `localhost:10.0`，一台完全沒有桌面的伺服器會被判成有。
「有桌面」不等於「你現在看得到圖形」：ssh 進一台有桌面的機器，字型照裝，
但你要看到圖示，手邊的終端機也得裝一份。
_Avoid_: 圖形介面、headless、GUI

### 遺留狀態

**v2 殘骸**：
舊版腳本留下、v3 需要辨識的東西。分兩類，處置不同。
_Avoid_: 垃圾、舊檔案

**v2 骨架**：
v2 寫進 `.zshrc` 的那 30 行 oh-my-zsh 骨架，現在位於使用者區段。
只有在整組都在、順序一致，而且沒有 oh-my-zsh 官方 template 的特徵註解時，
才判定為 v2 產物。`--clean-v2` 會把它收回 managed block，預設不做。
理由與判定方式見 [docs/adr/0002](docs/adr/0002-v2-skeleton-two-stage-detection.md)。
_Avoid_: 舊區塊、v2 區段

**不歸類為 v2 殘骸的東西**：
`[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh` 是 `p10k configure` 自己寫的；
`.profile` 裡的 `export SHELL=` 與 `exec … zsh` 是手寫的（v1/v2 只寫進 `.bash_profile`
且帶完整護欄）。這幾樣長得像舊版產物，但不是，`--clean-v2` 一律不碰。

**還原點**：
同一次執行改到的所有檔案，備份進 `~/.zsh-p10k-backups/<時間戳>/` 這同一個目錄，
權限與原檔相同、目錄本身 700。沒改到任何檔案就不產生。
舊版把備份散在家目錄（`~/.zshrc.backup.*`），那樣回答不了「把這台還原到上禮拜三」，因為
`.zshrc` 與 `.zshenv` 各自最新的那一份可能來自不同次執行，
分別還原會湊出一個從來沒存在過的組合。
`--rollback` 只認得新格式，散裝的舊備份留著不動、也不使用。
_Avoid_: 備份、backup 檔
