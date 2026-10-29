# 参与贡献

谢谢你愿意一起改 Hebiu！新功能、新形象、修 bug、翻译都欢迎。English is welcome too.

## 开发

```bash
make test          # 单元测试（不碰你的 ~/.hebiu）
make install-dev   # 改完代码后快速重装，只编本机架构
make help          # 全部命令
```

- `Sources/HebiuKit/` 是核心逻辑，不依赖界面，新逻辑尽量放这里并配测试
- `Sources/Hebiu/` 是桌宠程序和主窗口
- 想手动试命令行又不想动自己的数据：`HEBIU_HOME=$(mktemp -d) .build/debug/Hebiu todo add 明天 10:00 试一下`

代码结构和扩展点见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)。

## 几条约定

- **默认不联网**：新功能要连外部服务的，默认关闭，在设置里打开；代码里不写死任何地址、账号、key
- **钩子永远不拖累别人**：给 Claude Code / Codex 的钩子只能往本地文件写一行，不输出、不等待、永远返回成功
- **能撤销**：AI 改你数据的操作都要能撤销，删除这类操作要你自己点确认
- **界面文字用口语**：短句，说清楚「做什么、什么时候」，不用术语
- 提 PR 前跑一遍 `make test`

## 分享形象

做好的形象包放进 `Resources/characters/<名字>/`，跑一遍 `make test`（会检查动作表用到的帧都在），然后提 PR。请确认图片是你自己画的或者有权公开。用 AI 生成的形象（[art/ai](art/ai/README.md)）受模型许可限制，不能并进 MIT 的仓库，单独分享就好。格式见 [docs/CHARACTERS.md](docs/CHARACTERS.md)。

## 报 bug

附上：macOS 版本、怎么复现、`~/.hebiu/hebiu.log` 里相关的几行（贴之前看一眼，别带上私人内容）。
