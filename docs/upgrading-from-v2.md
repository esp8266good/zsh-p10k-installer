# 從 v2 升級

裝過 v2 的機器，重跑時多加 `--clean-v2`，先用 `--dry-run` 看它要收走什麼：

```bash
bash ~/install-zsh-p10k.sh --dry-run --clean-v2
bash ~/install-zsh-p10k.sh --clean-v2
```

不加的話也不會壞，只是同一段 oh-my-zsh 設定會存在兩份。原因是 v2 把骨架直接寫進 `.zshrc`，
那些行現在不在腳本的區段裡，算是「你的」，腳本沒你明講就不動。

## 什麼會被收走

只有 v2 那 30 行骨架**全部都在、順序一致**，而且沒有 oh-my-zsh 官方 template 的特徵註解，才會被收走。
判斷不出來就什麼都不做：誤判的代價是弄壞別人的 `.zshrc`，所以寧可漏抓。
收走的只有 v2 的行，你自己插在中間的行一行都不會少。判斷方式的細節在
[adr/0002](adr/0002-v2-skeleton-two-stage-detection.md)。

長得像 v2、但其實不是 v2 寫的東西，`--clean-v2` 一律不碰：

- `[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh`：這是 `p10k configure` 寫的。
- `.profile` 裡的 `export SHELL=` 與 `exec … zsh`：手寫的。v2 只寫進 `.bash_profile`。

## 跟 v2 差在哪

| | v2 | 現在 |
|---|---|---|
| `.zshrc` | 備份後整份覆蓋 | 只寫兩個區段，區段外不動 |
| 重跑 | 每次都再覆蓋一次 | 沒變動就什麼都不做 |
| 已有 oh-my-zsh 的機器 | 骨架被換掉 | 骨架不碰 |
| 套件 | `apt update` + `apt install` | 缺才裝，不跑 `update`，除非安裝失敗 |
| 備份 | `~/.zshrc.backup.*` 散在家目錄 | 同一次執行整組放進 `~/.zsh-p10k-backups/<時間戳>/` |
| 還原 | 自己 `cp` | `--rollback` |
| 解除安裝 | 無 | `--uninstall` |

整份覆蓋在樹莓派上把 4863 bytes 的 `.zshrc` 換成 1641 bytes，`HIST_STAMPS` 就這樣不見了。
備份檔還在，但沒有人會回去讀它。這是改成只寫區段的原因，細節在
[adr/0001](adr/0001-managed-block-instead-of-overwrite.md)。

`--rollback` 只認新格式的還原點。v2 留下的 `~/.zshrc.backup.*` 不會被使用也不會被刪，要用請自己 `cp` 回去。
