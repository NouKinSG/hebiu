# 数据来源

数据来源把外面的事情变成待办。hebiu 本体不联网；要什么数据，就写一个小脚本去拿，hebiu 定时运行它。

## 最简单的例子

```bash
#!/bin/bash
echo '[{"id": "water", "title": "喝杯水", "due": "2026-10-26 15:00"}]'
```

1. 存成 `~/.hebiu/sources/water.sh`，`chmod +x`
2. 设置 → 来源 → 打开「water」（或在 `~/.hebiu/hebiu.md` 的 `## sources` 下加一行 `- water: 15`，表示每 15 分钟同步一次）
3. 想马上看效果：`hebiu source run water`

## 规则

脚本往**标准输出**打印 JSON 数组（也可以是 `{"items": [...]}`），每条一个待办：

| 字段 | 必填 | 说明 |
|---|---|---|
| `id` | ✓ | 来源里的唯一标识。下次同步还是这个 id，就是同一条：标题、时间变了会更新 |
| `title` | ✓ | 待办内容 |
| `due` | | `2026-10-26 10:00`、`2026-10-26` 或 ISO 8601。只有日期的不到点喊，只在当天汇总里提 |
| `note` | | 备注 |
| `link` | | 待办里点了能打开 |

同步时：

- 这次有、上次没有 → 加进待办
- 上次有、这次没有、还没打勾 → 从待办里删掉（比如 MR 合并了、会议过去了）
- 已经打勾的，来源里还有也不会复活
- **退出码不是 0 算失败，失败时待办一条都不动**；错误信息（标准错误输出）显示在设置页
- 超过 60 秒没结束会被结束，算失败
- 关掉这个来源时，它带进来、还没完成的待办一起清掉

脚本运行时：

- 工作目录不固定，用绝对路径
- 环境变量 `HEBIU_HOME`（数据目录）、`HEBIU_SOURCE`（来源名）
- `PATH` 额外加了 `/opt/homebrew/bin`、`/usr/local/bin`、`~/.local/bin`、`~/bin`（开机自启时系统给的 PATH 很短）

## 自带的来源

| 名字 | 类型 | 内容 |
|---|---|---|
| `calendar` | 内置（EventKit） | 今天和明天的会议（全天、已取消的不算），开始前 5 分钟提醒；会议结束后自动消失 |
| `reminders` | 内置（EventKit） | 没完成的提醒事项：没日期的、7 天内到期的。在 hebiu 打勾不会同步回提醒事项 |
| `gitlab-review` | 脚本 `datasources/gitlab-review.sh` | 等你 review、还开着的 MR。用本机已登录的 glab（`GITLAB_HOST` 可指定服务器），只读 |

日历和提醒事项要系统权限，第一次打开时系统会问；拒绝了以后要去「系统设置 → 隐私与安全性 → 日历 / 提醒事项」里打开 Hebiu。

## 再举几个例子

**每周一提醒交周报**（`datasources/example.sh` 就是这个）：

```bash
#!/bin/bash
if [ "$(date +%u)" = "1" ]; then
  echo "[{\"id\": \"weekly-$(date +%Y-%W)\", \"title\": \"交周报\", \"due\": \"$(date +%Y-%m-%d) 17:00\"}]"
else
  echo "[]"
fi
```

id 里带上周数，每周是新的一条；打勾后这一周不会再出现。

**从一个文本文件读**（比如手机同步过来的笔记）：

```python
#!/usr/bin/env python3
import json, os
path = os.path.expanduser("~/Library/Mobile Documents/com~apple~CloudDocs/待办.txt")
lines = [l.strip() for l in open(path, encoding="utf-8")] if os.path.exists(path) else []
print(json.dumps([{"id": l, "title": l} for l in lines if l], ensure_ascii=False))
```

## 涉及公司数据时

GitLab、邮件、飞书这类来源拿的是公司数据：

- 只读，只存在本机 `~/.hebiu/`，不往任何地方发
- 用本机已经登录好的工具（glab 等），不要把密码、令牌写进脚本或 hebiu 的配置
- 先确认公司允许再接
