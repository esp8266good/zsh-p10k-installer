# 開發

改的是 `install-zsh-p10k.sh.in`。`./build.sh` 會把 95 KB 的 `template_basic-admin_.p10.zsh.sh`
壓成約 28 KB 的 base64 塞進去，產生單檔的 `dist/install-zsh-p10k.sh`（不進 git）。

```bash
./build.sh                           # 產生單檔腳本，並驗證塞進去的 template 解得回原檔
./tests/run-fixtures.sh              # 每種初始狀態各開一個容器跑完整流程（需要 docker，約 8 分鐘）
./tests/run-fixtures.sh native-omz   # 只跑一個
```

## 發版

改 `SCRIPT_VERSION`，commit，打同名 tag 推上去：

```bash
git tag v3.2.0 && git push origin main v3.2.0
```

CI 會 build、跑 shellcheck、全部 fixture 與 macOS、Windows runner 的 smoke test，都過了才建立 Release，附上腳本與 `SHA256SUMS`。
tag 跟 `SCRIPT_VERSION` 對不上，CI 直接失敗。

## fixture

每個 fixture 是一種真的踩過的初始狀態。每個都驗同一條流程：
裝 → 重跑沒有變動 → 還原點回得去 → 解除安裝後 `.zshrc` 跟原檔每個 byte 都一樣。

| fixture | 初始狀態 | 它防的是 |
|---|---|---|
| `fresh-bash` | 純 bash 的新機器 | 無 |
| `zsh-no-omz` | 有 zsh 沒 oh-my-zsh | 非互動 zsh 拿不到 PATH |
| `v2-installed` | v2 裝過，骨架一字未動 | 認不出是 v2 寫的 |
| `v2-with-user-edits` | 樹莓派：使用者的行夾在 v2 骨架中間 | 收回 v2 時吃掉使用者的 `fi` |
| `native-omz` | 工作站：手寫的完整 omz 設定 | 把使用者的骨架當成 v2 收走 |
| `has-desktop` | 真的有桌面 | 該裝字型卻跳過；`sha256sum` 讀檔失敗時誤報「沒有 sha256sum」 |
| `forwarded-display` | 沒桌面，但 ssh 帶了 X11 forwarding | `$DISPLAY` 有值就以為有桌面 |
| `hook-fallback` | 共用主機：sudo 要密碼又沒有 tty | 新建 `.bash_profile` 讓 `.profile` 不再被讀；VS Code 終端機進不了 zsh；`--rollback` 還原不了 hook |
| `ancient-awk` | 樹莓派的 mawk 1.3.3（1996 年版） | `[[:space:]]` 不報錯但永遠比對不到 |
| `dotfiles-symlink` | `.zshrc` 是 stow / chezmoi 建的 symlink | symlink 被換成一般檔案 |
| `sticky-options` | 第一次帶了 `--omz-update reminder --no-chsh`，之後都不帶 | 選項悄悄變回預設值；`zsh-p10k update` 沒沿用選項、sha256 對不上還照跑 |
| `nonascii-home` | 家目錄有中文 | zsh 寫不了 `.zwc` 和 p10k 快取，每開一次視窗就印錯誤 |

`zsh-p10k update` 的測試用 `ZSH_P10K_RELEASE_URL` 指到 `file://` 的假 Release，不連 GitHub。
| `font-fail` | 字型的網址一律下載失敗 | 字型沒裝到，結尾還說裝好了 |
| `external-p10k` | `.zshrc` 自己 source 外部的 p10k | 多 clone 一份、oh-my-zsh 去找不存在的主題 |
| `self-build` | 沒有 zsh 也沒有 sudo | 自行編譯那條路壞掉沒人發現 |

`ancient-awk` 要另外拉 `debian:buster` 映像，比較慢，但只有它測得到 mawk 1.3.3 那種
「regex 不報錯、就是永遠不成立」的狀況，在 gawk 或 mawk 1.3.4 上怎麼測都會過。
所以 `build.sh` 另外會掃腳本裡所有 awk 程式，出現 `[[:` 就讓 build 失敗。

## macOS

fixture 是 Linux 容器，測不到 macOS。macOS 另外用 `tests/macos-smoke.sh`，要在 Mac 上跑：

```bash
./build.sh
scp dist/install-zsh-p10k.sh tests/macos-smoke.sh mac:/tmp/   # 或在 Mac 上 clone 之後直接跑
ssh mac 'mkdir -p /tmp/s/dist /tmp/s/tests && mv /tmp/install-zsh-p10k.sh /tmp/s/dist/ && mv /tmp/macos-smoke.sh /tmp/s/tests/ && bash /tmp/s/tests/macos-smoke.sh'
```

每個情境都用 `mktemp -d` 當 `HOME`，iTerm2 也裝到暫存目錄（`ZSH_P10K_APPS_DIR`），不碰真的 home 和 `/Applications`。
CI 在 `macos-15`（Apple silicon）和 `macos-15-intel` 上各跑一次。
「沒有 Command Line Tools」的情境用一個假的 `xcode-select`（`FAKE_NO_CLT=1` 時 `-p` 回失敗）模擬，
所以裝了 Xcode 的 runner 也測得到；測試也會放一個假的 `sudo`，確認 macOS 上一次都沒被叫到。

有 tty 的情境用 `expect` 送答案，不用 `printf ... | script`：macOS 的 `script` 讀到 stdin 的 EOF 會送出 `^D`，
而且比前面的輸入還早被處理，`read` 會讀到空字串。
`expect` 的比對字串只能用 ASCII（`[y/N] `、`Ctrl-C`）：macOS 內建的 expect 5.45 遇到中文比對字串會 segfault。

## Windows

`tests/windows-smoke.sh` 要在 Git Bash 裡跑：`bash tests/windows-smoke.sh`。
每個情境都用暫存的 `HOME` 和 `LOCALAPPDATA`，字型登錄寫在測試專用的機碼（`ZSH_P10K_WIN_FONT_KEY`），跑完刪掉。
CI 在 `windows-2022`、`windows-2025` 上各跑一次。

Git Bash 上要注意的事：

- 傳給 Windows 程式的 `/v` 這類參數會被當成路徑改寫，要加 `MSYS_NO_PATHCONV=1`。
- `chmod 600` 沒有效果，`ln -s` 會變成複製。
- Git for Windows 出廠是 `core.autocrlf=true`，clone 要明確關掉。
- Windows 10 內建的 `tar` 沒有 zstd，Windows 11 有，只在 Windows 11 上測會漏掉。
- 開真的視窗時 hook 會不會切進 zsh，ssh 和 CI 都沒有 tty 測不到，要有人實際開一次。

## 寫法規則

- awk 程式裡不能用 POSIX 字元類別，空白寫 `[ \t]`；`grep -E` 要比對空白用腳本裡的 `$SP`。
- `$變數` 後面不能直接接中文或全形標點，要寫成 `${變數}`。macOS 內建的 bash 3.2 在 C locale 下會把全形字的位元組當成變數名稱的一部分，加上 `set -u` 就整支腳本掛掉。`build.sh` 會擋。
- 要能在 bash 3.2 下跑：不用 `mapfile`、關聯陣列、`${x,,}`；可能是空的陣列寫成 `${arr[@]+"${arr[@]}"}`，或先檢查 `${#arr[@]}`。
- 使用者看得到的訊息與註解都用全形中文標點，不用破折號。
- 設計決定寫在 `docs/adr/`，名詞定義寫在 `CONTEXT.md`。
