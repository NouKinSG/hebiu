# Biu：默认形象的画法

Biu 全部是代码画的（SVG），没有用到任何图片素材，可以随便改、随便用（MIT）。

- `biu.html`：所有表情由部件拼出来——眼睛、嘴、手、脸红、小道具（电脑、奶茶、爱心、星星、Zzz……），再加身体倾斜和压扁。`FRAMES` 里一行一个表情
- `render.mjs`：用 Chrome 把每个表情截成 768×768 的透明 PNG

要 Google Chrome、node 和 Python 的 Pillow：

```bash
cd art/biu && npm install puppeteer-core && cd ../..
make art                       # 重画所有帧，转成 webp 放进 Resources/characters/default/frames
make icon                      # 顺便重新生成 App 图标
```

改了某个表情、或者想照着它画一个自己的角色：改 `FRAMES` 或部件函数，重新跑一遍就行。
