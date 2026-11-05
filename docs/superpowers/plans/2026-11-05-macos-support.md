# macOS 支援 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 讓 `install-zsh-p10k.sh` 在 macOS 13 以上（arm64 / x86_64）只用系統內建工具就能裝好，並可選擇安裝 iTerm2、加一個 MesloLGS NF 的 iTerm2 profile。

**Architecture:** 不拆檔，照 repo 現有做法全部改在 `install-zsh-p10k.sh.in`。用一個 `DET_IS_MACOS` 旗標分平台，macOS 專屬的步驟集中在新的「macOS」段落（放在「安裝步驟」段落後面）。macOS 的測試另寫 `tests/macos-smoke.sh`，用暫存 `HOME` 跑，不碰真的 home；Linux 的 11 個 fixture 不改。

**Tech Stack:** bash 3.2 相容的 bash、macOS 內建的 `sw_vers` / `dscl` / `shasum` / `ditto` / `codesign` / `xcode-select`，GitHub Actions。

**Spec:** `docs/superpowers/specs/2026-11-05-macos-support-design.md`

## Global Constraints

- 不裝 Homebrew，macOS 上任何路徑都不呼叫 sudo（`chsh` 問使用者自己的密碼除外）。
- 腳本要能在 bash 3.2.57 + `set -euo pipefail` 下跑。
- 既有 `~/.zshrc` 的使用者區塊、既有 `~/.p10k.zsh`、iTerm2 既有 profile 一律不動。
- 沒有 tty 時不能卡住等輸入，也不能跳 GUI 視窗。所有選擇題沒 tty 一律當「不要」。
- iTerm2：版本 3.7.7，URL `https://iterm2.com/downloads/stable/iTerm2-3_7_7.zip`，SHA256 `549eb2b21464d7f4606165e51c36a6b1a252ac9a79958228a240152412759da2`，只在 macOS 13 以上提供。
- iTerm2 profile 字型值是 `MesloLGS-NF-Regular 13`，key 是 `Normal Font`（2026-11-05 從一台裝了 iTerm2 3.7.7 的 Mac 讀 `defaults read com.googlecode.iterm2 "New Bookmarks"` 確認）。
- Linux 行為不變：`./build.sh` 最後一行 round-trip OK；`shellcheck -S warning` 沒輸出；`./tests/run-fixtures.sh` 11 個 0 failed。不改 `tests/incontainer.sh`。
- 給使用者看的文字照 repo 風格：全形標點，不用破折號。
- 新增內容黑名單 0 筆、gitleaks 0 findings；文件和程式裡不出現測試機的主機名稱。

## Review Focus

1. 已經有 oh-my-zsh 和 `~/.p10k.zsh` 的 Mac 重跑：`~/.p10k.zsh` 的 sha256、`~/.zshrc` 使用者區塊都不能變。→ Task 2 的 `existing-setup` 情境。
2. `curl | bash` 經由 ssh、沒有 tty：不能問、不能跳視窗、不能卡住。→ Task 1 的 `no-clt-notty`、Task 3 / Task 4 的 `notty` 情境。
3. uninstall 的字型提示在 macOS 上不能是 `rm -rf ~/Library/Fonts`。→ Task 2 的 `uninstall-hint` 情境。
4. iTerm2 下載被竄改：hash 不符時只警告、不留下任何 `iTerm.app`，其他部分照常完成。→ Task 4 的 `bad-hash` 情境。
5. `~/Library/Fonts` 裡已經有同名字型（使用者自己裝過）：不重下載、不覆蓋。→ Task 2 的 `existing-setup` 情境。

---

### Task 1：macOS 偵測與 Command Line Tools 檢查

趁 Intel 測試機還沒裝 Command Line Tools 先做這個 task，裝了就測不到。

**Files:**
- Modify: `install-zsh-p10k.sh.in`：`detect_os`（636）、`run_detection`（919）、`check_supported`（940）、`print_report`（963 起）、全域 `DET_*` 宣告（605-634）
- Create: `tests/macos-smoke.sh`

**Interfaces:**
- Produces:
  - 全域 `DET_IS_MACOS`（0 / 1）、`DET_MACOS_VERSION`（例如 `15.8.2`）、`DET_MACOS_MAJOR`（整數）、`DET_ARCH`（`uname -m`）
  - 全域 `DET_MAC_CLT`（0 / 1）：`xcode-select -p` 成功才是 1
  - `macos_require_clt()`：沒有 Command Line Tools 時的互動流程，在 `check_supported` 之後、`print_report` 之前呼叫
  - `ask_yn "<問題>"`：有 tty 而且 `OPT_YES=0` 時從 `/dev/tty` 讀，`y` / `Y` 回 0，其他回 1；沒 tty 或 `OPT_YES=1` 直接回 1。Task 3、Task 4 也用它
  - `tests/macos-smoke.sh <情境>`：輸出格式跟 `tests/incontainer.sh` 一樣（`PASS` / `FAIL` 行，最後 `N passed, M failed`），用 `ZSH_P10K_INSTALLER` 環境變數指定要測的腳本（預設 `dist/install-zsh-p10k.sh`），每個情境用 `HOME=$(mktemp -d)`

- [ ] **Step 1：寫 `tests/macos-smoke.sh`，先放兩個情境**
  - `no-clt-notty`（只在 `xcode-select -p` 失敗的機器上跑，否則印 `SKIP`）：`HOME=$tmp bash $INSTALLER < /dev/null`。斷言：exit code 不是 0；輸出含 `xcode-select --install`；`$tmp` 底下沒有任何檔案（`find "$tmp" -mindepth 1 | wc -l` 是 0）；腳本沒有執行 `xcode-select --install`（測試用一個放在 `PATH` 最前面的假 `xcode-select` 包住真的那個：參數是 `-p` 就轉給真的，參數是 `--install` 就在 `$log` 記一行後 exit 1；斷言 `$log` 是空的）。
  - `no-clt-tty-no`（同樣條件）：`printf 'n\n' | script -q /dev/null env HOME=$tmp bash $INSTALLER`。斷言：輸出含問題文字「要幫你叫出安裝視窗嗎」；exit code 不是 0；`$tmp` 底下沒有任何檔案。
  - `dry-run-report`（任何 Mac）：`HOME=$tmp bash $INSTALLER --dry-run < /dev/null`。有 Command Line Tools 時斷言：exit 0；輸出含 `macOS`、`sw_vers -productVersion` 的值、`uname -m` 的值；不含 `不支援這台機器`。

- [ ] **Step 2：`./build.sh` 後把 `dist/install-zsh-p10k.sh` 和測試 scp 到 Intel 測試機的暫存目錄跑**
  Expected：`no-clt-notty`、`no-clt-tty-no` FAIL（現在的腳本會因為認不得套件管理器而印 `不支援這台機器`，但輸出不含 `xcode-select --install`）。

- [ ] **Step 3：實作**
  - `detect_os`：`uname -s` 是 `Darwin` 時設 `DET_IS_MACOS=1`、`DET_OS_ID=macos`、`DET_OS_PRETTY="macOS $(sw_vers -productVersion) ($(uname -m))"`，並偵測 `DET_MAC_CLT`。
  - `check_supported`：macOS 上有 `/bin/zsh` 就算支援，不看套件管理器。
  - `macos_require_clt`：`DET_MAC_CLT=1` 直接回傳。否則有 tty 時用 `ask_yn "這台沒有 Command Line Tools（git 需要它），要幫你叫出安裝視窗嗎？[y/N] "`；答 y 就跑 `xcode-select --install`，然後每 5 秒檢查 `xcode-select -p`，最多 30 分鐘，等到了就設 `DET_MAC_CLT=1` 繼續；超時就 `die`。答 N 或沒 tty：印「先在這台 Mac 上跑 `xcode-select --install`，裝好再重跑」後 `exit 1`。這段在 `--dry-run` 時也照跑（dry-run 不改檔，但要講清楚會停在這裡）。
  - `print_report`：macOS 時列出 macOS 版本、架構、Command Line Tools 狀態。

- [ ] **Step 4：再跑 Step 2**，Expected：三個情境全部 PASS（沒有 Command Line Tools 的機器上 `dry-run-report` 會走到 Command Line Tools 檢查，改成斷言輸出含 `xcode-select --install`）。

- [ ] **Step 5：Linux 回歸**：`./build.sh`（最後一行 round-trip OK）、`shellcheck -S warning dist/install-zsh-p10k.sh tests/macos-smoke.sh`（沒輸出）。11 個 fixture 留到 Task 5 一次跑。

- [ ] **Step 6：Commit**：`git add install-zsh-p10k.sh.in tests/macos-smoke.sh && git commit -m "macOS：偵測系統版本與 Command Line Tools"`

- [ ] **Step 7：⛔ 停下來通知使用者**：到 Intel 測試機前面把 Command Line Tools 裝好（或在那台跑 `sudo softwareupdate -i ...`）。`ssh <Intel 機> xcode-select -p` 成功之後才開始 Task 2。

### Task 2：macOS 上完整安裝（bash 3.2、字型、login shell、uninstall）

**Files:**
- Modify: `install-zsh-p10k.sh.in`：`LOCAL_FONTS`（55）、`detect_desktop`（758）、`detect_shell_change`（887）、`install_fonts`（1409）、`change_login_shell`（1872）、`do_uninstall`（2073、2076）、`print_font_guide`（2084）、`print_summary`（2114）、事前報告裡的 `sed -i` 提示（1169），以及 13 處 `${xxx[@]}` 中可能為空的陣列
- Modify: `tests/macos-smoke.sh`

**Interfaces:**
- Consumes: Task 1 的 `DET_IS_MACOS`
- Produces: `login_shell_of_current_user()`：印出目前使用者的 login shell。Linux 用 `getent passwd`，macOS 用 `dscl . -read "/Users/$(id -un)" UserShell | awk '{print $2}'`，都失敗就印 `${SHELL:-unknown}`。取代三處 `getent` 呼叫。

- [ ] **Step 1：在 `tests/macos-smoke.sh` 加四個情境**
  - `clean`：`HOME=$tmp bash $INSTALLER --no-chsh < /dev/null`。斷言：exit 0；`$tmp/.oh-my-zsh/oh-my-zsh.sh` 存在；四個外掛目錄和 `powerlevel10k` 存在；`$tmp/.p10k.zsh` 存在；`$tmp/Library/Fonts/` 下有四個 `MesloLGS NF *.ttf`；`$tmp/.local/share/fonts` 不存在；`zsh -i -c exit` 在 `HOME=$tmp` 下 exit 0 而且 stderr 是空的。
  - `rerun`：接著 `clean` 的 `$tmp` 再跑一次。斷言：exit 0；`.zshrc`、`.zshenv`、`.p10k.zsh` 的 sha256 跟第一次跑完一樣。
  - `existing-setup`：先在 `$tmp` 放 `git clone --depth 1 https://github.com/ohmyzsh/ohmyzsh $tmp/.oh-my-zsh`、一份 `.zshrc`（含 `export ZSH=...`、`source $ZSH/oh-my-zsh.sh` 和一行 `alias mine=true`）、一份內容是 `# my p10k` 的 `.p10k.zsh`、一個內容是 `fake` 的 `$tmp/Library/Fonts/MesloLGS NF Regular.ttf`。跑完斷言：`.p10k.zsh` 的 sha256 沒變；`.zshrc` 去掉腳本管理區塊之後跟原本一樣（`alias mine=true` 還在）；`MesloLGS NF Regular.ttf` 內容還是 `fake`；事前報告的模式是 `append`。
  - `uninstall-hint`：`HOME=$tmp bash $INSTALLER --uninstall < /dev/null`。斷言：輸出不含 `rm -rf` 加 `Library/Fonts`（`grep -E 'rm -rf .*Library/Fonts'` 沒東西）；含 `MesloLGS NF`；不含 `getent`。

- [ ] **Step 2：在 Intel 測試機跑這四個情境**，Expected：FAIL（字型裝到 `.local/share/fonts`、uninstall 提示 `rm -rf`，可能還有 bash 3.2 的 unbound variable）。

- [ ] **Step 3：實作**
  - `LOCAL_FONTS`：macOS 是 `$HOME/Library/Fonts`。這個值在 `detect_os` 之前就被設定，改成在 `detect_os` 裡依平台重設，或改成函式，二選一由實作者決定，但 `do_uninstall` 也要拿到正確的值（`do_uninstall` 在 `run_detection` 之前就被呼叫，見 `main`）。
  - `install_fonts`：macOS 不跑 `fc-cache`。
  - `detect_desktop`：macOS 一律 `DET_HAS_DESKTOP=1`，`DET_DESKTOP_EVIDENCE="macOS"`。
  - `change_login_shell`：macOS 上拿掉 `sudo_run chsh` 那條退路；`detect_shell_change` 裡 `sudo:免密碼 sudo` 那個分支在 macOS 上也不能出現。
  - `do_uninstall`：macOS 上字型那行改成 `rm -f ~/Library/Fonts/MesloLGS\ NF\ *.ttf`。
  - `print_font_guide`：macOS 上改成講 iTerm2（Settings → Profiles → Text → Font）和 Terminal.app（設定 → 描述檔 → 文字 → 字體）怎麼改，字型已經裝在這台 Mac 上，不用再下載。
  - 事前報告裡的 `sed -i 's|...|' ~/.profile` 提示，macOS 上改成 `sed -i ''`。
  - 13 處 `"${arr[@]}"`：逐一看，可能為空的改成 `${arr[@]+"${arr[@]}"}`。

- [ ] **Step 4：在 Intel 測試機跑全部情境**，Expected：全部 PASS。

- [ ] **Step 5：`./build.sh`、shellcheck**，同 Task 1 Step 5。

- [ ] **Step 6：Commit**：`git commit -m "macOS：字型、login shell、uninstall 與 bash 3.2 相容"`

### Task 3：iTerm2 profile（第 2 題）

先做 profile 再做安裝：profile 可以用一個假的 `iTerm.app` 目錄測，不用真的下載。

**Files:**
- Modify: `install-zsh-p10k.sh.in`：參數解析（144-156）、`usage`（106）、`print_report`、`main`（2134）、`do_uninstall`
- Modify: `tests/macos-smoke.sh`

**Interfaces:**
- Consumes: `ask_yn`、`DET_IS_MACOS`
- Produces:
  - `OPT_ITERM2_PROFILE`：`ask`（預設）/ `yes` / `no`，由 `--iterm2-profile` / `--no-iterm2-profile` 設定，**不**加進 `OPTS_GIVEN`、不寫進記憶檔
  - `find_iterm2_app()`：依序檢查 `${ZSH_P10K_APPS_DIR:-}/iTerm.app`（只給測試用，空字串就跳過）、`/Applications/iTerm.app`、`$HOME/Applications/iTerm.app`，印出第一個存在的路徑，都沒有回 1
  - `ITERM2_PROFILE_FILE="$HOME/Library/Application Support/iTerm2/DynamicProfiles/zsh-p10k.json"`
  - `ITERM2_PROFILE_GUID`：寫死的常數，實作時用 `uuidgen` 產生一次貼進來
  - `install_iterm2_profile()`

- [ ] **Step 1：加四個情境**（都用 `ZSH_P10K_APPS_DIR=$tmp/apps`，先 `mkdir -p $tmp/apps/iTerm.app` 假裝有 iTerm2）
  - `profile-yes`：`--iterm2-profile --no-chsh`。斷言：`ITERM2_PROFILE_FILE` 存在；`plutil -lint` 通過；`plutil -extract Profiles.0.Name raw` 是 `zsh-p10k (MesloLGS NF)`；`Profiles.0."Normal Font"` 是 `MesloLGS-NF-Regular 13`；`Guid` 等於腳本裡的常數；輸出含 `Set as Default`。
  - `profile-keep`：先寫一份內容不同的 `zsh-p10k.json`，再跑 `--iterm2-profile`。斷言：檔案 sha256 沒變；輸出含「已存在」。
  - `profile-notty`：不帶參數、`< /dev/null`。斷言：profile 檔不存在；事前報告含 `--iterm2-profile`（告訴使用者怎麼用參數要求）。
  - `profile-tty-yes`：`printf 'y\n' | script -q /dev/null env HOME=$tmp ZSH_P10K_APPS_DIR=$tmp/apps bash $INSTALLER --no-chsh -y`。注意 `-y` 會讓 `ask_yn` 回 1，所以這個情境**不帶** `-y`，改成餵 `\n`（按 Enter 繼續）和 `y`，順序依實作的提問順序決定。斷言：profile 檔存在。
  另外在 `uninstall-hint` 情境加斷言：輸出含 `zsh-p10k.json`。

- [ ] **Step 2：跑新情境**，Expected：FAIL（參數不認得）。

- [ ] **Step 3：實作 `install_iterm2_profile()`**：macOS、`find_iterm2_app` 找得到、profile 檔不存在時才處理。`OPT_ITERM2_PROFILE=ask` 就 `ask_yn "要幫你在 iTerm2 加一個用 MesloLGS NF 字型的 profile 嗎？[y/N] "`。JSON 內容：

  ```json
  {"Profiles":[{"Name":"zsh-p10k (MesloLGS NF)","Guid":"<ITERM2_PROFILE_GUID>","Normal Font":"MesloLGS-NF-Regular 13"}]}
  ```

  寫完印：「到 iTerm2 → Settings → Profiles，選 zsh-p10k (MesloLGS NF)，按 Other Actions → Set as Default」。
  問題要在 `print_report` 之後、`confirm_or_exit` 之前問完（所有選擇都在動手前定案），實際寫檔放在 `install_fonts` 之後。事前報告列出這一題的狀態（會問你 / 會建立 / 不建立 / 已存在）。`do_uninstall` 的「刻意保留」清單加一行這個檔案的刪除指令。

- [ ] **Step 4：跑全部情境**，Expected：全部 PASS。

- [ ] **Step 5：`./build.sh`、shellcheck。**

- [ ] **Step 6：Commit**：`git commit -m "macOS：可選擇加一個 MesloLGS NF 的 iTerm2 profile"`

### Task 4：iTerm2 安裝（第 1 題）

**Files:**
- Modify: `install-zsh-p10k.sh.in`：全域常數（59-61 旁邊）、參數解析、`usage`、`print_report`、`main`、「下載」段落（1194-1235）
- Modify: `tests/macos-smoke.sh`

**Interfaces:**
- Consumes: `ask_yn`、`find_iterm2_app`、`download_to`、`file_sha256`、`DET_MACOS_MAJOR`
- Produces:
  - 常數 `ITERM2_VERSION="3.7.7"`、`ITERM2_URL`、`ITERM2_SHA256`（值見 Global Constraints）
  - `OPT_ITERM2`：`ask` / `yes` / `no`，由 `--iterm2` / `--no-iterm2` 設定，不寫進記憶檔
  - `fetch_verified_soft <out> <sha> <url>...`：跟 `fetch_verified` 一樣，但 hash 不符或下載失敗時印 `warn` 並回 1，不 `die`
  - `install_iterm2()`：成功後 `find_iterm2_app` 要找得到，Task 3 的 profile 題目接在它後面
  - 安裝目的地：`ZSH_P10K_APPS_DIR` 有設就用它（只給測試用）；否則 `/Applications` 可寫就用它，不行就 `$HOME/Applications`

- [ ] **Step 1：加三個情境**
  - `iterm2-install`：`ZSH_P10K_APPS_DIR=$tmp/apps`，`--iterm2 --no-chsh < /dev/null`。斷言：`$tmp/apps/iTerm.app` 存在；`codesign --verify --deep --strict $tmp/apps/iTerm.app` 通過；`defaults read $tmp/apps/iTerm.app/Contents/Info.plist CFBundleShortVersionString` 是 `3.7.7`；暫存目錄裡沒有殘留的 zip。
  - `bad-hash`：用 `ZSH_P10K_ITERM2_SHA256_OVERRIDE=0000...`（64 個 0，只給測試用的環境變數）跑同樣指令。斷言：exit 0；輸出含 `sha256`；`$tmp/apps/iTerm.app` 不存在；oh-my-zsh 照樣裝好。
  - `iterm2-notty`：沒參數、`< /dev/null`、沒有假的 iTerm.app。斷言：`$tmp/apps/iTerm.app` 不存在；事前報告含 `--iterm2`。
  另外：macOS 12 以下沒機器可測，只做程式碼審查：`DET_MACOS_MAJOR -lt 13` 時不問、不裝，`--iterm2` 給了就 warn「iTerm2 3.7.7 需要 macOS 13 以上」。

- [ ] **Step 2：跑新情境**，Expected：FAIL。

- [ ] **Step 3：實作 `install_iterm2()`**：只在 macOS 13 以上、`find_iterm2_app` 找不到時處理。下載到 `mktemp -d` → `fetch_verified_soft` → `ditto -x -k <zip> <暫存目錄>` → `codesign --verify --deep --strict` → `mv` 到目的地。任何一步失敗：`warn`、`rm -rf` 暫存目錄、回 0 讓腳本繼續。`OPT_ITERM2=ask` 時用 `ask_yn "沒偵測到 iTerm2，要幫你裝嗎？[y/N] "`，跟 Task 3 一樣在 `confirm_or_exit` 之前問，實際下載在 `install_fonts` 之後、`install_iterm2_profile` 之前。

- [ ] **Step 4：跑全部情境**，Expected：全部 PASS。

- [ ] **Step 5：`./build.sh`、shellcheck。**

- [ ] **Step 6：Commit**：`git commit -m "macOS：可選擇安裝 iTerm2 3.7.7（核對 sha256）"`

### Task 5：CI、文件、版本號，與 Linux 回歸

**Files:**
- Modify: `.github/workflows/ci.yml`：新增 job `macos`
- Modify: `Readme.md`、`docs/development.md`
- Modify: `install-zsh-p10k.sh.in:28`：`SCRIPT_VERSION="3.3.0"`

- [ ] **Step 1：CI 加 job `macos`**：`needs: build`（下載 installer artifact），`strategy.matrix.os: [macos-15, macos-15-intel]`（2026-11-05 查 GitHub 文件：前者 arm64、後者 Intel，公開 repo 可用），跑 `./tests/macos-smoke.sh` 的 `clean`、`rerun`、`existing-setup`、`uninstall-hint`、`profile-yes`、`profile-keep`、`profile-notty`、`iterm2-install`、`bad-hash`、`iterm2-notty`（`no-clt-*` 在 runner 上會印 SKIP）。`release` job 加 `needs: macos`。

- [ ] **Step 2：Readme 加 macOS 段落**：支援 macOS 13 以上的 Apple silicon 和 Intel、不需要 Homebrew、沒有 Command Line Tools 時會發生什麼、iTerm2 兩題和四個參數、profile 要自己 Set as Default。`docs/development.md` 加怎麼在 Mac 上跑 `tests/macos-smoke.sh`。

- [ ] **Step 3：Linux 全套回歸**：`./build.sh`（最後一行 round-trip OK）、`shellcheck -S warning`（沒輸出）、`./tests/run-fixtures.sh`（11 個 0 failed，約 8 分鐘）。

- [ ] **Step 4：公開前檢查**：新增內容跑黑名單（0 筆）和 gitleaks（0 findings）；`git grep` 確認沒有測試機主機名稱。

- [ ] **Step 5：Commit**：`git commit -m "v3.3.0：macOS 支援的 CI 與文件"`。push 到 `main` 要先問使用者。push 之後 CI 的 macOS job 要綠；看 log 要用 `gh api .../actions/runs/<id>/logs` 下載 zip，不能用 `gh run view --log`。

### Task 6：實機驗證

- [ ] **Step 1：Intel 測試機，真的 home**：`curl | bash` 的方式跑 v3.3.0（沒有 tty）；跑完再跑一次確認 `.zshrc` / `.zshenv` / `.p10k.zsh` sha256 沒變；`ssh -t` 有 tty 再跑一次，iTerm2 兩題都答 y，確認 `/Applications/iTerm.app` 版本 3.7.7、profile 出現在 iTerm2 裡（要有人看螢幕，或截圖 `screencapture`）。
- [ ] **Step 2：Apple silicon 機器（工作用筆電，小心）**：先 `tar czf ~/zsh-p10k-pre-v3.3.0-<date>.tgz ~/.zshrc ~/.zshenv ~/.oh-my-zsh ~/.p10k.zsh`（存在的才放）並確認檔案大小合理；先用 `HOME=$(mktemp -d)` 跑 `tests/macos-smoke.sh` 全部情境；然後才對真的 home 跑，加 `--no-iterm2 --no-iterm2-profile`。跑完斷言：`~/.p10k.zsh` sha256 跟備份裡一樣、`.zshrc` 使用者區塊跟備份一樣、`~/Library/Fonts` 的四個 MesloLGS 檔沒變、iTerm2 偏好設定沒被動（`defaults read com.googlecode.iterm2 "New Bookmarks"` 跑完前後 diff 為空）。
- [ ] **Step 3：發 v3.3.0 Release**：打 tag 和 push tag 是對外動作，先問使用者。
