"""成对的循环帧（眨眼、敲键盘左右手……）：第二帧只保留真正在动的部位，其余用第一帧

两张分别生成的图，发丝、衣褶总会有细微差别，直接来回切会一闪一闪。这里只把两张图差别成块的地方
（眼睛、手）从第二张拿过来，其他地方都用第一张。

用法：python3 pairs.py 第一帧.png 第二帧.png 输出.png [--thresh 18] [--grow 21]
  输入输出都是绿幕原图（抠图之前）；输出按 p_<帧名>.png 命名，finalize.py 会优先用它
"""
import argparse

import cv2
import numpy as np


def match_color(src, ref, mask):
    """把 src 在 mask 内的 LAB 均值和方差校准到 ref，两张图整体色调对齐"""
    s = cv2.cvtColor(src, cv2.COLOR_BGR2LAB).astype(np.float32)
    r = cv2.cvtColor(ref, cv2.COLOR_BGR2LAB).astype(np.float32)
    m = mask > 0
    for c in range(3):
        s[..., c] = (s[..., c] - s[..., c][m].mean()) / (s[..., c][m].std() + 1e-6) * r[..., c][m].std() + r[..., c][m].mean()
    return cv2.cvtColor(np.clip(s, 0, 255).astype(np.uint8), cv2.COLOR_LAB2BGR)


def moving_part(a, b, out, thresh=18, grow=21):
    A = cv2.imread(a)
    B = cv2.imread(b)
    person = ((A[..., 1].astype(int) - np.maximum(A[..., 0], A[..., 2])) < 20).astype(np.uint8)
    B = match_color(B, A, person)
    d = cv2.GaussianBlur(np.abs(A.astype(np.float32) - B.astype(np.float32)).mean(axis=2), (0, 0), 6)
    m = (d > thresh).astype(np.uint8)
    n, cc, stats, _ = cv2.connectedComponentsWithStats(m)
    keep = np.zeros_like(m)
    for k in range(1, n):
        if stats[k, cv2.CC_STAT_AREA] > 400:          # 只要成块的变化，零散的发丝噪点不要
            keep[cc == k] = 1
    keep = cv2.dilate(keep, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (grow, grow)))
    w = cv2.GaussianBlur(keep.astype(np.float32), (0, 0), 5)[..., None]
    cv2.imwrite(out, (B * w + A * (1 - w)).astype(np.uint8))
    return int(keep.sum())


if __name__ == "__main__":
    p = argparse.ArgumentParser(description="成对的循环帧：第二帧只保留真正在动的部位")
    p.add_argument("first"); p.add_argument("second"); p.add_argument("out")
    p.add_argument("--thresh", type=float, default=18, help="差别多大算在动，调大只留更明显的变化")
    p.add_argument("--grow", type=int, default=21, help="在动的区域往外扩多少像素，边缘更自然")
    a = p.parse_args()
    px = moving_part(a.first, a.second, a.out, a.thresh, a.grow)
    print(f"{a.out}：换了 {px} 个像素")
