# 用 AI 生成自己的形象

想把自己、家里的猫、喜欢的原创角色做成桌宠，又不会画画：在 Mac 上用本地模型出图，再用这里的脚本抠图、导出成形象包。全程在本机跑，照片不上传。

```
参考照片 / 一句描述
   │  gen.sh（不带参考图）            ① 出一张基础图：纯绿背景、站姿、拿着道具
   ▼
g_idle.png
   │  gen.sh（以基础图为参考）        ② 只改脸和小特效，一帧一帧出：眨眼、笑、生气、睡着……
   ▼
g_blink.png  g_pat.png  g_pout.png …
   │  pairs.py                        ③ 成对循环帧（眨眼、敲键盘左右手）只保留在动的部位
   ▼
p_blink.png …
   │  finalize.py                     ④ 抠绿幕、存成无损 WebP、放进形象包、对一遍缺哪些帧
   ▼
~/.hebiu/characters/mine/frames/*.webp
```

不想用 AI 的话：Biu 是用代码画的（[art/biu](../biu)），也可以自己画好图直接放进 `frames/`，格式见 [docs/CHARACTERS.md](../../docs/CHARACTERS.md)。

## 准备环境

需要 Apple 芯片的 Mac，留出约 15 GB 磁盘。生成时很吃内存，别和大型 IDE、虚拟机一起跑。

```bash
mkdir -p ~/hebiu-art && cd ~/hebiu-art
python3 -m venv venv                     # Python 3.10～3.12
venv/bin/pip install mflux "pillow==11.3.0" opencv-python-headless numpy
```

模型推荐 **FLUX 3 Image Klein** 的 mflux 8bit 版（约 9 GB），这套流程就是用它做出来的。下载前先读它的许可（见文末「许可和注意」），同意了再下：

```bash
pip install modelscope
modelscope download --model OsaurusAI/FLUX-3-Image-Klein-mflux-8bit --local_dir ~/hebiu-art/model
```

`gen.sh` 默认在 `~/hebiu-art` 找环境和模型，放在别处就设 `ART_HOME` / `MODEL`。

## ① 出基础图

基础图决定整个形象的样子，**多换几个种子出几张，挑最满意的一张再往下做**。要求：

- **纯绿背景**（抠图靠它）；角色身上别有大块纯绿色
- 上半身、正面、居中，头顶留一点空，手里拿着道具也放在画面里
- 768×768，深色描边的 Q 版画风最好抠，桌面上也最清楚

有参考照片（照片放在 `~/hebiu-art/mine/photo.jpg`）：

```bash
cd ~/hebiu-art && ART=~/hebiu/art/ai     # 换成你 clone 的仓库位置
$ART/gen.sh mine/g_idle.png 1001 "Image 1 is a reference photo. Draw the same person as a cute chibi desktop mascot: upper body, facing the viewer, smiling, holding a cup of milk tea, clean anime style with dark outlines, flat colors, centered with some space above the head, on a solid pure green background, no shadow, no text." mine/photo.jpg
```

没有照片，就把长相写清楚，去掉参考图：

```bash
$ART/gen.sh mine/g_idle.png 1001 "A cute chibi desktop mascot of a girl with short black hair and round glasses, wearing a yellow hoodie, upper body, facing the viewer, smiling, holding a laptop, clean anime style with dark outlines, flat colors, centered with some space above the head, on a solid pure green background, no shadow, no text."
```

同一句话换第二个参数（种子）就是另一张：`1001`、`1002`、`1003`……

## ② 一帧一帧改表情

**每一帧都从基础图改，只改脸和小特效，手和道具不动。** 提示词前面固定加这一句，不然模型会顺手重画手，帧和帧之间就对不上了：

```
Edit image 1: Keep the exact same character, outfit, hands, arms, the object being held, the pose and the green background exactly as in image 1; do not move or redraw the hands or arms.
```

后面接 `Change only ...` 描述要改的地方，比如：

```bash
KEEP="Edit image 1: Keep the exact same character, outfit, hands, arms, the object being held, the pose and the green background exactly as in image 1; do not move or redraw the hands or arms."
$ART/gen.sh mine/g_blink.png 2001 "$KEEP Change only the eyes: both eyes gently closed." mine/g_idle.png
$ART/gen.sh mine/g_pout.png  2001 "$KEEP Change only the face: puffed cheeks, pouting lips, slightly angry eyebrows, a small pink anger mark next to the head." mine/g_idle.png
```

帧名就是文件名去掉 `g_`。直接沿用 Biu 的动作表最省事：把 [Resources/characters/default](../../Resources/characters/default) 整个复制成你的形象包，按下表出同名的帧，动作表一行都不用改。

| 帧名 | 用在哪 | Change only …（提示词参考） |
|---|---|---|
| `idle` | 平时 | 基础图本身 |
| `blink` | 眨眼 | the eyes: both eyes gently closed |
| `wave` | 打招呼、醒来 | one hand raised and waving, happy closed-eye smile（这帧要动手，去掉 KEEP 里 hands 那半句） |
| `think` | 开始干活前 | the face: looking up thoughtfully, a small question mark next to the head |
| `chin` | 闲着托腮 | one hand under the chin, relaxed smile（要动手） |
| `type` / `typeL` / `typeR` | Claude / Codex 干活 | typing on a laptop with both hands；左右手各抬一下的两张用 ③ 合成 |
| `wait` | 等你批准 | the face: big surprised eyes, open mouth, an exclamation mark; leaning toward the viewer |
| `star` → `proud` | 做完了 | star-shaped sparkling eyes, big grin, sparkles / proud smile with closed eyes, small sparkles |
| `huh` / `dizzy` | 出错了 | confused face with a sweat drop / spiral dizzy eyes, wavy mouth, little stars around the head |
| `pat` `bliss` `grin` `nuzzle` `poke` `bleh` `blush` `heart` `surprised` | 点它时的反应 | 摸头眯眼、享受、大笑、歪头蹭、坏笑眨眼、吐舌头、害羞脸红、比心冒爱心、小惊讶 |
| `pout` | 戳太多、该休息了 | puffed cheeks, pouting, a small anger mark |
| `sleepy` | 深夜、睡着 | half-closed sleepy eyes, small yawn, "zzz" next to the head |
| `cheer` `tea` `sad` | 生日、闲着、出错 | both arms up cheering / sipping milk tea / teary eyes, sad mouth |

`wave`、`chin`、`type`、`heart`、`cheer`、`tea` 这几帧要动手，提示词里去掉 KEEP 那句关于 hands / arms 的半句。

不想做那么多帧也行：少了的帧会用 `idle` 顶上，`finalize.py` 最后会列出还缺哪些。也可以只做几帧，再在主窗口「动作」页把动作改成只用你有的帧。

## ③ 成对的循环帧

眨眼、敲键盘这种两帧来回切的，分别生成的两张图发丝总有细微差别，切起来会一闪一闪。用 `pairs.py` 让第二帧只保留真正在动的部位：

```bash
~/hebiu-art/venv/bin/python $ART/pairs.py mine/g_idle.png mine/g_blink.png mine/p_blink.png
~/hebiu-art/venv/bin/python $ART/pairs.py mine/g_type.png mine/g_typeL.png mine/p_typeL.png
```

输出叫 `p_<帧名>.png`，导出时优先用它。

## ④ 抠图、导出

```bash
~/hebiu-art/venv/bin/python $ART/finalize.py mine ~/.hebiu/characters/mine --outline
```

- `--outline`：深色描边的画风加上，边缘会更干净；写实、水彩风不要加
- 和身体分开的深色小装饰（zzz、问号）会自动改成浅色，深色桌面上才看得见；不想要就加 `--keep-dark-marks`
- 一律存无损 WebP：有损压缩会改写半透明像素，桌面上看边缘一圈白

然后改 `~/.hebiu/characters/mine/character.json` 里的名字、称呼、人设、台词，在「设置 → 形象」里选 `mine`。

## ⑤ 检查

每一帧都看一遍，不合格的换个种子重出：

- 手指数对不对、手有没有多出一只、道具有没有变样
- 表情有没有混搭：一只眼眨一只眼瞪、嘴型两种表情叠在一起
- 眼镜、发型、衣服和基础图是不是同一个
- 在**深色和浅色桌面**上各看一眼：有没有白边、绿边、残留的小点
- 点它、拖它、让它做几个动作（`hebiu <动作名>`，`hebiu actions` 看全部），看换帧时会不会跳

## 踩过的坑

| 现象 | 原因 | 做法 |
|---|---|---|
| 手怪、多一只手、道具变了 | 改表情时模型把手也重画了 | 提示词固定加 KEEP 那句；只有确实要动手的帧才去掉 |
| 眨眼、敲键盘一闪一闪 | 两帧分别生成，发丝细节不同 | `pairs.py` 只换在动的部位 |
| 边缘一圈白 | 有损 WebP 改写半透明像素 | `finalize.py` 已固定无损 |
| 发丝间残留绿色 | 按「接近背景色」抠 | `greenkey.py` 按「绿明显多于红蓝」抠 |
| 某一帧突然变大、头发被画面切平 | 模型把角色画满了整张图 | 提示词加「centered with some space above the head」，或者换种子 |
| 一直卡着不动 | mflux 第一次运行去联网检查模型 | `gen.sh` 已设 `HF_HUB_OFFLINE=1` |
| 出图很慢 | 改图要同时读参考图 | 768px、12 步在 M 系列上一张几分钟，正常；先用少几帧把流程走通 |

## 许可和注意

这里的脚本是 MIT。**模型不是**，它有自己的许可，下载即表示你同意：

| 模型 | 许可 | 意味着 |
|---|---|---|
| FLUX 3 Image Klein（推荐，本流程用它做的） | [FLUX Kommunity License v1.0](https://modelscope.cn/models/OsaurusAI/FLUX-3-Image-Klein-mflux-8bit) | 个人爱好、自己用：可以。商用：只有年收入低于 500 万美元的个人或公司可以商用生成的图，而且要做内容审查、按法律要求标注 AI 生成；其他商用找 Black Forest Labs 要授权 |
| FLUX.2 [klein] 4B | [Apache 2.0](https://github.com/black-forest-labs/flux2) | 可以商用。用 `FAMILY=flux2` 切换；这套流程没有用它实测过 |
| FLUX.2 [klein] 9B | FLUX Non-Commercial License | 只能非商用 |

几条一定要守的：

- **用真人照片，先征得本人同意。** 模型许可明确禁止侵犯肖像权、生成「数字复制品」类的内容
- **公开分享生成的图，按当地法律标注是 AI 生成的**（中国有《人工智能生成合成内容标识办法》），分享前自己看一遍内容
- **AI 生成的形象不要提 PR 进本仓库的 `Resources/characters/`**：仓库是 MIT（允许任何人商用），和非商用模型的许可冲突。想分享就单独发形象包，写明用了什么模型、是什么许可
