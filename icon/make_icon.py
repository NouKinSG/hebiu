"""生成 App 图标：嫩芽绿超椭圆底板 + 形象的一帧，输出 1024 PNG

用法：python3 make_icon.py [帧图] [输出]，默认用默认形象 Biu 招手那帧
"""
import sys, math
from PIL import Image, ImageDraw, ImageFilter

SRC = sys.argv[1] if len(sys.argv) > 1 else "../Resources/characters/default/frames/wave.webp"
OUT = sys.argv[2] if len(sys.argv) > 2 else "icon_1024.png"
N = 1024
SQ = 824                     # macOS 图标网格：824 的底板居中，四周留 100
OFF = (N - SQ) // 2

def squircle_mask(size, n=5.0):
    """超椭圆（|x|^n + |y|^n = 1），比普通圆角更接近系统图标的连续曲率"""
    m = Image.new("L", (size * 4, size * 4), 0)
    d = ImageDraw.Draw(m)
    pts = []
    r = size * 2
    for i in range(720):
        t = 2 * math.pi * i / 720
        c, s = math.cos(t), math.sin(t)
        x = r * math.copysign(abs(c) ** (2 / n), c)
        y = r * math.copysign(abs(s) ** (2 / n), s)
        pts.append((r + x, r + y))
    d.polygon(pts, fill=255)
    return m.resize((size, size), Image.LANCZOS)

mask = squircle_mask(SQ)
# 底板：嫩芽绿，上浅下深一点点
bg = Image.new("RGBA", (SQ, SQ))
top, bottom = (226, 243, 214), (196, 228, 182)
px = bg.load()
for y in range(SQ):
    k = y / (SQ - 1)
    col = tuple(int(top[i] + (bottom[i] - top[i]) * k) for i in range(3)) + (255,)
    for x in range(SQ):
        px[x, y] = col

# 角色：按不透明区域裁出来，等比放进底板，水平居中、稍微压住下沿
pet = Image.open(SRC).convert("RGBA")
pet = pet.crop(pet.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox())
scale = min((SQ * 0.78) / pet.width, (SQ * 0.80) / pet.height)
pet = pet.resize((round(pet.width * scale), round(pet.height * scale)), Image.LANCZOS)
layer = Image.new("RGBA", (SQ, SQ), (0, 0, 0, 0))
layer.alpha_composite(pet, ((SQ - pet.width) // 2, SQ - pet.height - round(SQ * 0.06)))
bg.alpha_composite(layer)
bg.putalpha(Image.composite(bg.getchannel("A"), Image.new("L", (SQ, SQ), 0), mask))

icon = Image.new("RGBA", (N, N), (0, 0, 0, 0))
# 轻微的投影，统一从上方打光
shadow = Image.new("RGBA", (N, N), (0, 0, 0, 0))
sh = Image.new("RGBA", (SQ, SQ), (0, 0, 0, 70)); sh.putalpha(mask.point(lambda v: v * 70 // 255))
shadow.alpha_composite(sh, (OFF, OFF + 12))
icon.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(14)))
icon.alpha_composite(bg, (OFF, OFF))
icon.save(OUT)
