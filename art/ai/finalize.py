"""母版 → 形象包的帧：masters/g_<帧名>.png（生成的原图）和 p_<帧名>.png（pairs.py 合成的，同名优先）
抠图后存成 768×768 无损 WebP，放进形象包的 frames/，再对一遍 character.json 用到的帧

用法：python3 finalize.py <母版文件夹> <形象包文件夹> [--outline]
  例：python3 finalize.py ~/hebiu-art/mine ~/.hebiu/characters/mine --outline
"""
import argparse
import glob
import json
import os

import cv2
import numpy as np
from PIL import Image

from greenkey import key


def lighten_dark_marks(im):
    """和身体分开、颜色很深的小装饰（zzz、问号、汗滴的描边）在深色桌面上看不见，改成浅色"""
    a = np.array(im)
    solid = (a[:, :, 3] > 128).astype(np.uint8)
    n, cc, stats, _ = cv2.connectedComponentsWithStats(solid, connectivity=8)
    if n <= 2:
        return im
    main = 1 + np.argmax(stats[1:, cv2.CC_STAT_AREA])
    lum = a[:, :, :3].mean(axis=2)
    dist_main = cv2.distanceTransform((cc != main).astype(np.uint8), cv2.DIST_L2, 5)
    for k in range(1, n):
        if k == main or stats[k, cv2.CC_STAT_AREA] > 0.03 * solid.size or stats[k, cv2.CC_STAT_AREA] < 56:
            continue
        m = cc == k
        if dist_main[m].min() < 21:      # 紧贴身体的是发丝、衣角，不是装饰
            continue
        if lum[m].mean() < 90:
            grow = cv2.dilate(m.astype(np.uint8), np.ones((3, 3), np.uint8)) > 0
            a[grow & (a[:, :, 3] > 0), :3] = (238, 240, 246)
    return Image.fromarray(a)

if __name__ == "__main__":
    p = argparse.ArgumentParser(description="母版 → 形象包的帧")
    p.add_argument("masters"); p.add_argument("pack")
    p.add_argument("--outline", action="store_true", help="深色描边的画风加上，见 greenkey.py")
    p.add_argument("--size", type=int, default=768)
    p.add_argument("--keep-dark-marks", action="store_true", help="不把分开的深色小装饰改成浅色")
    a = p.parse_args()

    src = {os.path.basename(f)[2:-4]: f for f in glob.glob(os.path.join(a.masters, "g_*.png"))}
    src.update({os.path.basename(f)[2:-4]: f for f in glob.glob(os.path.join(a.masters, "p_*.png"))})
    if not src:
        raise SystemExit(f"{a.masters} 里没有 g_*.png / p_*.png")
    out = os.path.join(a.pack, "frames")
    os.makedirs(out, exist_ok=True)
    for name, f in sorted(src.items()):
        # 无损 + exact：有损压缩会改写半透明像素，桌面上看边缘一圈白
        im = key(f, a.size, a.outline)
        if not a.keep_dark_marks:
            im = lighten_dark_marks(im)
        im.save(os.path.join(out, f"{name}.webp"), "WEBP", lossless=True, exact=True, method=6)
        print("  ", name)

    # 动作表里用到、但还没有图的帧
    cfg = os.path.join(a.pack, "character.json")
    if os.path.exists(cfg):
        pack = json.load(open(cfg, encoding="utf-8"))
        used = {s["frame"] for act in pack.get("actions", {}).values() for s in act.get("steps", []) + act.get("loop", [])}
        used |= {act["hold"] for act in pack.get("actions", {}).values()}
        idle = pack.get("idle", {})
        used |= {idle.get(k) for k in ("frame", "blink", "sleep", "startle", "wake")} - {None}
        have = {os.path.basename(f)[:-5] for f in glob.glob(os.path.join(out, "*.webp"))}
        missing = sorted(used - have)
        print("还缺这些帧（会先用 idle 顶上）：" + " ".join(missing) if missing else "动作表用到的帧都齐了")
