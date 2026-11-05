# macOS 支援：設計

狀態：草稿，等使用者核准。對應版本：v3.3.0（暫定）。

## 為什麼要做

`install-zsh-p10k.sh` 目前只支援 Linux（apt-get / dnf / pacman / zypper）。在 macOS 上跑，
`check_supported` 會因為認不得套件管理器而直接結束。這次要讓同一支腳本在 macOS 上
（Apple silicon 和 Intel 都要）裝好 oh-my-zsh、Powerlevel10k、外掛、字型，並且可以選擇幫忙裝 iTerm2、
幫忙加一個用 MesloLGS NF 字型的 iTerm2 profile。

## 目標

1. macOS 13 以上、arm64 和 x86_64 都能從乾淨狀態裝好，結果跟 Linux 一樣（oh-my-zsh、p10k、四個外掛、`~/.p10k.zsh` template、MesloLGS NF 字型）。
2. 已經有 oh-my-zsh 和 `~/.p10k.zsh` 的機器：保留原本設定，只補缺的部分。行為跟 Linux 現在的 `append` 模式一樣（`detect_zshrc_mode`），`~/.p10k.zsh` 已存在就不覆蓋（`install_p10k_template`）。
3. 只用系統內建的工具：系統的 zsh 5.9、git、curl、shasum、ditto、dscl。不裝 Homebrew，不用 sudo。
4. 沒偵測到 iTerm2 時，詢問要不要幫忙安裝。
5. 詢問要不要在 iTerm2 加一個字型設成 MesloLGS NF 的 profile。

## 不做的事

- 不裝 Homebrew，也不透過 Homebrew 裝任何東西。
- 不在 macOS 上自己編 zsh（`build_zsh_locally`）。macOS 13 以上都內建 `/bin/zsh`。
- 不改 Terminal.app 的設定。只在最後的提示裡講怎麼手動改字型。
- 不把新的 iTerm2 profile 設成預設。使用者自己到 iTerm2 設定裡按「Set as Default」（使用者決定的）。
- 不修改 iTerm2 既有的 profile，包括 Default profile。
- macOS 12 以下：iTerm2 安裝選項不提供（官方 3.7.x 要求 macOS 13 以上）。其他部分能跑就跑，不特別保證。

## 做錯就算失敗的事（即使功能都動了）

- 動到使用者 `~/.zshrc` 裡腳本管理區塊以外的內容，或覆蓋既有的 `~/.p10k.zsh`。
- 在任何情況下呼叫 sudo，或要求輸入密碼（`chsh` 例外，下面講 login shell 那段會說明）。
- 沒有 tty 的時候（例如 `curl ... | bash` 從 ssh host command 跑）卡在等輸入，或跳出 GUI 視窗等人點。
- 下載的 iTerm2 沒核對 SHA256 就解壓。
- Linux 上的行為有任何改變：11 個 fixture 照樣要 0 failed。

## 限制

### bash 3.2

macOS 內建的 bash 是 3.2.57（在 Intel 機器上實測）。腳本開頭是 `set -euo pipefail`，
bash 4.4 以前，在 `set -u` 底下展開空陣列 `"${arr[@]}"` 會報 unbound variable。
腳本裡有 13 處 `${xxx[@]}`，每一處都要確認陣列可能是空的時候不會炸
（常見寫法：`${arr[@]+"${arr[@]}"}`）。其他 bash 4 才有的語法（`mapfile`、`declare -A`、`${x,,}`、`local -n`）目前 grep 沒找到，但實作完要在 macOS 上真的跑過才算數。

### BSD 工具

| 用到的地方 | Linux 寫法 | macOS 怎麼辦 |
|---|---|---|
| 查 login shell（`detect_shell_change` 和兩處 summary 輸出） | `getent passwd` | macOS 沒有 `getent`，改用 `dscl . -read "/Users/$USER" UserShell` |
| `detect_os` | `/etc/os-release` | 用 `sw_vers -productVersion` 和 `uname -m` |
| `file_mode` | `stat -c` | 已經有 `stat -f '%Lp'` 的 fallback，不用改 |
| `file_sha256` | `sha256sum` | 已經有 `shasum` 的 fallback，確認走得到 |
| `base64 -d` | GNU | macOS 15 的 `base64 -d` 實測可以用 |
| 事前報告裡提示使用者跑的 `sed -i` | GNU | macOS 要寫成 `sed -i ''`，這段提示在 macOS 上要換文字 |

### git 可能是假的

macOS 沒裝 Command Line Tools 的時候，`/usr/bin/git` 還是存在，但一執行就跳出 GUI 安裝視窗。
`command -v git` 會成功，所以不能只看這個。偵測方法：`xcode-select -p` 失敗就當作沒有 git。
我們的 Intel 測試機就是這個狀態。

沒有 Command Line Tools 時怎麼辦（使用者決定的）：

- 有 tty：問「這台沒有 Command Line Tools（git 需要它），要幫你叫出安裝視窗嗎？[y/N]」。答 y 就跑 `xcode-select --install`，然後每幾秒檢查一次 `xcode-select -p`，成功就繼續往下裝（等多久、要不要讓使用者按 Enter 放棄，是我的決定：最多等 30 分鐘，Ctrl-C 可以中斷）。答 N 就印說明後結束。
- 沒有 tty：不跳視窗，印出「先在這台 Mac 上跑 `xcode-select --install`，裝好再重跑」後結束。
- 這個檢查要放在任何檔案改動之前（事前報告裡就要列出來）。

## 各部分怎麼做

### 偵測與事前報告

- `detect_os`：macOS 時 `DET_OS_PRETTY` 顯示成例如 `macOS 15.8.2 (x86_64)`。
- `detect_pkg_mgr`：macOS 沒有套件管理器是正常的。`check_supported` 改成：macOS 只要有 `/bin/zsh`、可用的 git、curl 就算支援。缺 zsh 就結束並說明（理論上不會發生）。
- `detect_desktop`：macOS 一律當成有桌面（字型裝在這台 Mac 上，坐在前面的人就能用）。`--no-fonts` 照樣有效。
- 事前報告要多列：字型會裝到 `~/Library/Fonts`、iTerm2 兩題的答案（或「會問你」）。

### 字型

- macOS 的字型目錄是 `~/Library/Fonts`，`LOCAL_FONTS` 依平台決定。
- 不跑 `fc-cache`，macOS 放進去就生效。
- ⚠ `do_uninstall` 現在會提示「`rm -rf $LOCAL_FONTS`」。macOS 上這會變成 `~/Library/Fonts`，照著跑會刪掉使用者所有字型。macOS 上的提示要改成只刪那四個 `MesloLGS NF *.ttf`。
- 字型下載沒核對 checksum 是既有的缺口（Linux 也一樣），這次不處理，另外排。

### login shell

- 兩台測試機的 login shell 都已經是 `/bin/zsh`（macOS 10.15 起的預設），這種情況什麼都不做。
- 是 bash 的話：`/bin/zsh` 本來就在 `/etc/shells` 裡，走原本的 `chsh -s /bin/zsh` 路線（有 tty 時會問使用者自己的密碼，這不是 sudo）。沒有 tty 就沿用現有的 `~/.bash_profile` hook 做法。
- 現有的 `sudo_run chsh` 退路在 macOS 上拿掉。

### iTerm2 安裝（第 1 題）

- 只在 macOS 13 以上、而且 `/Applications/iTerm.app` 和 `~/Applications/iTerm.app` 都不存在時才問。
- 有 tty：問「沒偵測到 iTerm2，要幫你裝嗎？[y/N]」。沒有 tty：當成「不要」，事前報告寫出怎麼用命令列參數要求安裝。
- 命令列參數：`--iterm2` 不問直接裝，`--no-iterm2` 不問也不裝。不寫進 options 記憶檔（這是一次性的動作）。
- 版本和 SHA256 寫死在腳本裡，跟自編 zsh 的 5.9.2 做法一樣。目前官方穩定版是 3.7.7，zip 是 `https://iterm2.com/downloads/stable/iTerm2-3_7_7.zip`，官網公布的 SHA256 是 `549eb2b21464d7f4606165e51c36a6b1a252ac9a79958228a240152412759da2`（2026-11-05 從 iterm2.com/downloads 查到的，實作時要自己下載重算一次確認）。
- 流程：下載到暫存目錄（沿用 `fetch_verified`）→ 核對 SHA256 → 用 `ditto -x -k` 解壓 → `codesign --verify --deep --strict` 檢查簽章 → 搬到 `/Applications`（這台使用者在 admin 群組、`/Applications` 可寫的話），不行就放 `~/Applications`。
- 任何一步失敗：印警告、清掉暫存檔、繼續做其他部分，不讓整支腳本失敗。注意 `fetch_verified` 在 hash 不符時會 `die`，這段要用不會結束腳本的版本。

### iTerm2 profile（第 2 題）

- 有 iTerm2（原本就有，或剛剛裝好）而且 profile 檔還不存在時才問。
- 有 tty：問「要幫你在 iTerm2 加一個用 MesloLGS NF 字型的 profile 嗎？[y/N]」。沒有 tty：當成「不要」。
- 命令列參數：`--iterm2-profile` / `--no-iterm2-profile`，同樣不寫進記憶檔。
- 做法：用 iTerm2 的 Dynamic Profiles，在 `~/Library/Application Support/iTerm2/DynamicProfiles/` 寫一個 JSON 檔（例如 `zsh-p10k.json`）。官方文件說必填的 key 只有 `Name` 和 `Guid`，其他沒寫的設定會沿用 Default profile；檔案放進去 iTerm2 就會讀到，不用重開。
- `Guid` 用寫死的常數，重跑時才認得出是同一個 profile。檔案已存在就不改（使用者可能自己改過）。
- 字型 key：文件沒寫名稱。實作時從 iTerm2 匯出一個 profile 的 JSON 來確認（推測是 `"Normal Font": "MesloLGS-NF-Regular 13"`，要驗證）。
- 寫完之後印出：「到 iTerm2 → Settings → Profiles，選 zsh-p10k，按 Other Actions → Set as Default」。
- 解除安裝（我的決定）：跟 `~/.p10k.zsh` 一樣列進「刻意保留」，uninstall 印出刪除指令，不自動刪（使用者可能改過）。
- rollback 不管它（我的決定）：現在的還原點只存 `$HOME` 底下的 dotfile，要記子路徑得改還原點格式，會連帶動到 Linux 的行為和 fixture，不值得。

### Readme 和文件

- `Readme.md` 加 macOS 段落：支援的版本、不需要 Homebrew、iTerm2 兩題是什麼。
- `docs/development.md` 加 macOS 怎麼驗證。

## 驗證

| 項目 | 過關條件 |
|---|---|
| 既有檢查 | `./build.sh` 最後一行 round-trip OK；`shellcheck -S warning` 沒輸出；`./tests/run-fixtures.sh` 11 個 0 failed |
| 公開前檢查 | 新增內容黑名單 0 筆、gitleaks 0 findings |
| CI | 新增 macOS runner 的 job（arm64 和 Intel 各一），從乾淨的 `HOME` 跑一次安裝並檢查結果。runner 標籤實作時查 GitHub 文件確認 |
| Intel 實機（沒有 Command Line Tools 的路） | 趁這台現在還沒裝 Command Line Tools，先驗：沒 tty 時印說明並結束、而且沒改任何檔案；有 tty 時會問、答 N 會結束。然後由使用者坐在 imac 前面把 Command Line Tools 裝好（CI 的 macOS runner 預裝 Xcode，測不到這條路） |
| Intel 實機 | 先用 `HOME=$(mktemp -d)` 跑乾淨安裝；再對真的 home 跑；再跑第二次確認重跑結果一樣；測 iTerm2 安裝和 profile |
| Apple silicon 實機 | Intel 都過了才做。先整包備份 `~/.zshrc`、`~/.oh-my-zsh`、`~/.p10k.zsh`。先用暫存 `HOME` 跑，最後才對真的 home 跑；兩題都回答「不要」；跑完 diff 確認使用者區塊和 `~/.p10k.zsh` 沒變 |

## 留給實作者決定

- 函式怎麼拆、平台判斷放哪裡。
- 事前報告和提示文字的確切措辭（照 repo 現有風格：全形標點、不用破折號）。
- CI job 的檢查細節。

## 文件放在哪

這份設計文件提到的都是一般化的機器描述（Apple silicon / Intel），沒有主機名稱，可以跟著程式一起 commit 進公開 repo。
