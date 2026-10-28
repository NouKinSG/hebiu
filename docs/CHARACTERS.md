# 做一个自己的形象

桌宠长什么样、叫什么、怎么说话、每件事做什么动作，全在一个**形象包**里，不用改代码。

```
~/.hebiu/characters/<文件夹名>/
├── character.json      名字、称呼、人设、台词、动作表
└── frames/             一张图一帧：idle.webp、wave.webp……（webp 或 png，透明底）
```

- 程序自带的形象在 `Resources/characters/`，默认是 `default`（Biu，一个头顶长芽的小团子）
- 自己做的放 `~/.hebiu/characters/`，和自带的同名时以自己的为准
- 换形象：「设置 → 形象」里选，或在 `~/.hebiu/hebiu.md` 里写 `- character: 文件夹名`

## 最快的做法：在 Biu 上改

1. 复制一份：`cp -r Resources/characters/default ~/.hebiu/characters/mine`
2. 把 `frames/` 里的图换成你的（文件名不变，就不用改动作表）
3. 改 `character.json` 里的 `name`、`pronoun`、`persona`、`lines`
4. 「设置 → 形象」选 `mine`

只想改某个动作怎么演：不用复制，直接在主窗口「动作」页，鼠标移到那一格点铅笔改，保存后会在 `~/.hebiu/characters/<形象名>/` 存一份你的动作表，图片继续用自带的；点「恢复成自带的」就删掉你那份。

## 图片

- 每帧一张正方形透明底图，建议 768×768，角色站在画面下方居中，脚下留一点空
- 所有帧的角色大小、位置要一致，否则换帧时会跳
- 用到哪些帧由动作表决定，名字随便起；少了的帧会用 `idle` 顶上，启动日志里会列出缺了哪些（`~/.hebiu/hebiu.log`）
- Biu 是用代码画的，想照着画一个：见 [art/biu/README.md](../art/biu/README.md)

## character.json

```jsonc
{
  "name": "Biu",                 // 角色的名字，界面和 AI 提示词里用
  "pronoun": "它",               // 界面上怎么称呼它：她 / 他 / 它
  "callsUser": "你",             // 它怎么称呼你（写进提示词）
  "summary": "头顶长芽的小团子",   // 形象列表里的一句话介绍
  "persona": "……",               // 默认人设（打开 AI 大脑后用；「人设」页改过就以改过的为准）
  "lines": { "done": ["做完啦～", "又搞定一件"] },   // 默认台词，动作的 line 指向这里的键
  "actions": { … },              // 动作表，见下
  "taps": [ { "action": "pat", "weight": 22 } ],    // 点它时随机挑哪个反应，weight 越大越常出现
  "annoyed": "annoyed",          // 6 秒内戳 5 下
  "rightClick": "poke",
  "doubleClick": "love",
  "idle": {
    "frame": "idle",             // 平时站着的那帧
    "blink": "blink",            // 眨眼帧，不要就写 null
    "fidgets": ["milktea", "chin"],   // 闲着偶尔做的动作
    "sleep": "sleepy",           // 睡着时的帧
    "startle": "surprised",      // 被吵醒那一下
    "wake": "wave"               // 醒来后
  },
  "expressions": ["pat", "love"],     // AI 回答时能配的表情（动作名）；空就用 taps 里的
  "catalog": [ … ]               // 「动作」页怎么分组显示，见下
}
```

### 一个动作怎么写

```jsonc
"done": {
  "steps": [ { "frame": "star", "seconds": 0.8, "effect": "kick" } ],  // 先依次播这几帧
  "hold": "proud",               // 最后停在这帧
  "holdSeconds": 3.5,            // 停多久后回到 idle；不写就一直停到下一个动作
  "holdEffect": "pop",           // 换到 hold 那一下的小效果
  "loop": [],                    // 停住后循环播的几帧（比如敲键盘），直到下一个动作
  "line": "done"                 // 说 lines 里哪一组，不写就不说话
}
```

换帧时的小效果：`pop` 弹一下、`kick` 后坐力、`squish` 往下缩、`sway` 左右摇。

### 程序会触发哪些动作

动作名是固定的，程序按名字找；形象包里没写的动作，到时候就不演。

| 动作 | 什么时候 |
|---|---|
| `hello` | 打开 Claude Code / Codex |
| `working` | Claude Code / Codex 在干活（一直演到下一个事件，适合用 `loop`） |
| `wait` | 等你批准 |
| `nudge` | Claude Code 闲着等你回话（Codex 没有这个事件） |
| `done` | 做完一件事 |
| `error` | Claude Code 出错（一分钟最多一次；Codex 没有这个事件） |
| `remind` | 待办、习惯到点 |
| `rest` / `night` | 连续忙太久 / 深夜还在用 |
| `focus_start` / `focus_done` / `rest_done` | 番茄钟开始 / 专心时间到 / 休息结束 |
| `together` / `birthday` | 纪念日 / 生日 |
| `pat` `love` `poke` `tap_*` … | 点它时的反应，由 `taps`、`rightClick`、`doubleClick` 决定，名字自己起 |

`hebiu <动作名>` 可以在终端里让它马上演一遍，`hebiu actions` 看当前形象所有动作。

### 「动作」页的分组

```jsonc
"catalog": [
  { "title": "陪你写代码", "items": [
      { "action": "done", "title": "完成啦", "when": "做完一件事", "thumb": "proud" }
  ] }
]
```

`thumb` 是格子里显示的那帧。没放进 catalog 的动作照样能触发，只是动作页上看不到。

## 分享给别人

把整个文件夹打个包发出去，对方放进 `~/.hebiu/characters/` 就能选。想放进仓库让大家都能用：放到 `Resources/characters/<名字>/`，提个 PR；请确认图片是你自己画的或者有权公开。
