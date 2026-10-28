#!/bin/bash
# GitLab 上等你 review 的 MR → 待办（MR 合并或关闭后，待办自动消失）
# 只读：用本机已经登录的 glab 查询，结果只写在本机的 ~/.hebiu 里
# 查哪个 GitLab：设置了 GITLAB_HOST 就用它，否则用 glab 已登录的第一个
set -euo pipefail
command -v glab >/dev/null || { echo "没找到 glab（brew install glab 并 glab auth login）" >&2; exit 2; }
command -v python3 >/dev/null || { echo "没找到 python3" >&2; exit 2; }

if [ -z "${GITLAB_HOST:-}" ]; then
  STATUS=$(glab auth status 2>&1 || true)     # 先整段存下来，避免管道提前关闭让 pipefail 误判失败
  HOST=$(printf '%s\n' "$STATUS" | sed -n 's/.*Logged in to \([^ ]*\) as.*/\1/p' | sed -n 1p)
else
  HOST="$GITLAB_HOST"
fi
[ -n "$HOST" ] || { echo "glab 还没登录任何 GitLab（glab auth login）" >&2; exit 2; }

ME=$(glab api --hostname "$HOST" user | python3 -c 'import json, sys; print(json.load(sys.stdin)["username"])')
glab api --hostname "$HOST" "merge_requests?scope=all&state=opened&reviewer_username=${ME}&per_page=50" | python3 -c '
import json, sys
items = []
for mr in json.load(sys.stdin):
    ref = (mr.get("references") or {}).get("full", "")
    author = (mr.get("author") or {}).get("name", "")
    items.append({
        "id": "mr-%s-%s" % (mr["project_id"], mr["iid"]),
        "title": "Review：" + mr["title"],
        "note": " · ".join(x for x in (ref, author) if x),
        "link": mr["web_url"],
    })
print(json.dumps(items, ensure_ascii=False))
'
