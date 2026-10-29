"""绿幕抠图：纯绿背景的生成图 → 透明底，边缘不发绿、不发白

用法：python3 greenkey.py 输入.png 输出.webp [--size 768] [--outline]
  --outline  角色是深色描边的画风（二次元、Q 版）时加上：半透明边缘压成描边色，浅色残线就不会出现

判断背景只看「绿是否明显多于红和蓝」，亮绿、暗绿、薄荷绿都算；所以角色身上别有大块纯绿。
"""
import argparse

import cv2
import numpy as np
from PIL import Image


def key(path, size=768, outline=False):
    img = cv2.cvtColor(cv2.imread(path), cv2.COLOR_BGR2RGB).astype(np.float32)
    r, g, b = img[..., 0], img[..., 1], img[..., 2]
    h, w = g.shape

    # 绿比红蓝都多出 30 以上 = 背景；8～30 之间是边缘过渡
    dominance = g - np.maximum(r, b)
    alpha = 1.0 - np.clip((dominance - 8) / 22, 0, 1)

    # 被角色包住的「绿」：四周是深色 → 头发缝这类空隙，保持透明；四周是亮色 → 角色身上本来的绿，补回来
    lum = img.mean(axis=2)
    n, cc, stats, _ = cv2.connectedComponentsWithStats((alpha < 0.5).astype(np.uint8), connectivity=8)
    for k in range(1, n):
        x, y, bw, bh, _ = stats[k]
        if x == 0 or y == 0 or x + bw >= w or y + bh >= h:
            continue
        m = (cc == k).astype(np.uint8)
        rim = (cv2.dilate(m, np.ones((5, 5), np.uint8)) > 0) & (m == 0)
        if lum[rim].mean() > 120:
            alpha[m > 0] = 1.0

    # 背景里的孤立小块去掉；半透明只允许出现在实心区域边上 3 像素内
    n, cc, stats, _ = cv2.connectedComponentsWithStats((alpha > 0.5).astype(np.uint8), connectivity=8)
    alpha[np.isin(cc, [k for k in range(1, n) if stats[k, cv2.CC_STAT_AREA] < 60])] = 0
    near = cv2.dilate((alpha > 0.7).astype(np.uint8), cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (7, 7))) > 0
    alpha = np.where(near, alpha, 0)

    # 贴着身体、又和身体断开的零碎小块（发丝碎屑）去掉；离身体远一点的小装饰（星星、zzz）保留
    _drop_fragments(alpha, max_area=400, max_dist=25)

    # 去绿溢色；半透明边缘混了背景绿，不用它自己的颜色，改用紧挨着的实心像素的颜色
    fg = img.copy()
    fg[..., 1] = np.minimum(g, np.maximum(r, b) * 1.03 + 3)
    core = (alpha > 0.92).astype(np.float32)
    edge = (alpha > 0) & (core == 0)
    for sigma in (1.5, 3, 6):
        wsum = cv2.GaussianBlur(core, (0, 0), sigma)
        fill = np.dstack([cv2.GaussianBlur(fg[..., c] * core, (0, 0), sigma) for c in range(3)]) / np.maximum(wsum, 1e-4)[..., None]
        if (wsum[edge] > 1e-3).all():
            break
    fg[edge] = fill[edge]

    out = np.dstack([np.clip(fg, 0, 255), alpha * 255]).astype(np.uint8)
    small = np.array(Image.fromarray(out).resize((size, size), Image.LANCZOS))
    sc = size / 512

    # 缩放后边缘的零星残点
    a = small[..., 3].astype(np.float32) / 255
    _drop_fragments(a, max_area=60 * sc * sc, max_dist=12 * sc, threshold=0.02)
    small[..., 3] = (a * 255).astype(np.uint8)

    # 被包在角色内部的半透明像素（不挨着外面的透明区）恢复成不透明，颜色取旁边的实心像素
    clear = (small[..., 3] == 0).astype(np.uint8)
    n, cc, _, _ = cv2.connectedComponentsWithStats(clear, connectivity=4)
    border = set(np.unique(np.concatenate([cc[0], cc[-1], cc[:, 0], cc[:, -1]]))) - {0}
    outside = np.isin(cc, list(border))
    dist_out = cv2.distanceTransform((~outside).astype(np.uint8), cv2.DIST_L2, 3)
    solid = (small[..., 3] > 200).astype(np.float32)
    k = max(3, int(round(7 * sc)) | 1)
    nb_rgb = cv2.blur(small[..., :3].astype(np.float32) * solid[..., None], (k, k)) / np.maximum(cv2.blur(solid, (k, k))[..., None], 1e-4)
    inner = (small[..., 3] > 0) & (small[..., 3] < 235) & (dist_out > 3 * sc)
    small[inner, 3] = 255
    small[inner, :3] = nb_rgb[inner].astype(np.uint8)

    if outline:
        # 描边色 = 不透明像素里最暗那 5% 的中位色；半透明边缘往它压
        opaque = small[..., 3] > 235
        lum2 = small[..., :3].astype(np.float32).mean(axis=2)
        dark = opaque & (lum2 <= np.percentile(lum2[opaque], 5))
        line = np.median(small[dark][:, :3], axis=0).astype(np.float32)
        edge = (small[..., 3] > 0) & (small[..., 3] < 235)
        small[edge, :3] = (small[edge, :3].astype(np.float32) * 0.25 + line * 0.75).astype(np.uint8)
    return Image.fromarray(small)


def _drop_fragments(alpha, max_area, max_dist, threshold=0.5):
    """去掉面积小、离主体很近、又和主体断开的碎块（就地改 alpha）"""
    solid = (alpha > threshold).astype(np.uint8)
    n, cc, stats, _ = cv2.connectedComponentsWithStats(solid, connectivity=8)
    if n <= 2:
        return
    main = 1 + np.argmax(stats[1:, cv2.CC_STAT_AREA])
    dist_main = cv2.distanceTransform((cc != main).astype(np.uint8), cv2.DIST_L2, 5)
    for k in range(1, n):
        m = cc == k
        if k != main and stats[k, cv2.CC_STAT_AREA] < max_area and dist_main[m].min() < max_dist:
            alpha[m] = 0


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("src"); p.add_argument("out")
    p.add_argument("--size", type=int, default=768)
    p.add_argument("--outline", action="store_true")
    a = p.parse_args()
    key(a.src, a.size, a.outline).save(a.out, "WEBP", lossless=True, exact=True, method=6)
