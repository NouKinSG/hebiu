# 换电脑

## 1. 旧电脑：备份数据

```bash
cd hebiu
make backup                # 打包到桌面：hebiu-backup-日期.tar.gz
```

包里有台词与设置（`hebiu.md`）、待办（`todo.json`）、提醒状态、来源脚本、待办的每日备份。不含日志和事件文件。

代码在 git 里，改过的话记得 `git push` 到你自己的仓库。

## 2. 新电脑：装好

```bash
xcode-select --install                     # 没装过命令行工具的话
git clone <仓库地址> hebiu
cd hebiu
make install                               # 编译（Apple 芯片 / Intel 都能跑）、装到 ~/Applications、开机自启
make restore FILE=~/Desktop/hebiu-backup-xxx.tar.gz   # 把备份放到新电脑桌面后
make hooks                                 # 接上 Claude Code
```

`make restore` 不会直接覆盖：新电脑上已有的 `~/.hebiu` 会先挪成 `~/.hebiu.before-restore-时间`。

第一次启动时系统可能会问：

| 弹窗 | 怎么选 |
|---|---|
| 「Hebiu」想发送通知 | 允许（到点提醒用；不想要可以在设置 → 待办里关掉） |
| 访问日历 / 提醒事项 | 只在设置 → 来源里打开对应来源时才会问 |

## 3. 检查

```bash
hebiu version
hebiu todo
make test
```

## App 标识

钥匙串里的 DeepSeek key、开机自启都认 App 标识（默认 `io.github.hebiu`）。想换成自己的，在仓库根目录建一个 `local.mk`（不进 git）：

```make
BUNDLE_ID = com.你的名字.hebiu
```

换电脑时新电脑也放一份同样的 `local.mk`；key 存在旧电脑的钥匙串里，新电脑要在「AI 大脑」里重新粘贴一次。

## 不放进仓库的东西

| 东西 | 在哪 | 怎么带走 |
|---|---|---|
| 待办、台词、设置 | `~/.hebiu/` | `make backup` / `make restore` |
| 自己做的形象 | `~/.hebiu/characters/` | `make backup` 会一起带上 |
| DeepSeek key | 钥匙串 | 新电脑重新粘贴 |
| `local.mk` | 仓库根目录 | 自己拷 |
