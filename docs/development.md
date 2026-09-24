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

CI 會 build、跑 shellcheck 與全部 fixture，都過了才建立 Release，附上腳本與 `SHA256SUMS`。
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
| `has-desktop` | 真的有桌面 | 該裝字型卻跳過 |
| `forwarded-display` | 沒桌面，但 ssh 帶了 X11 forwarding | `$DISPLAY` 有值就以為有桌面 |
| `hook-fallback` | 共用主機：sudo 要密碼又沒有 tty | 新建 `.bash_profile` 讓 `.profile` 不再被讀 |
| `ancient-awk` | 樹莓派的 mawk 1.3.3（1996 年版） | `[[:space:]]` 不報錯但永遠比對不到 |
| `dotfiles-symlink` | `.zshrc` 是 stow / chezmoi 建的 symlink | symlink 被換成一般檔案 |
| `sticky-options` | 第一次帶了 `--omz-update reminder --no-chsh`，之後都不帶 | 選項悄悄變回預設值 |

`ancient-awk` 要另外拉 `debian:buster` 映像，比較慢，但只有它測得到 mawk 1.3.3 那種
「regex 不報錯、就是永遠不成立」的狀況，在 gawk 或 mawk 1.3.4 上怎麼測都會過。
所以 `build.sh` 另外會掃腳本裡所有 awk 程式，出現 `[[:` 就讓 build 失敗。

## 寫法規則

- awk 程式裡不能用 POSIX 字元類別，空白寫 `[ \t]`；`grep -E` 要比對空白用腳本裡的 `$SP`。
- 使用者看得到的訊息與註解都用全形中文標點，不用破折號。
- 設計決定寫在 `docs/adr/`，名詞定義寫在 `CONTEXT.md`。
