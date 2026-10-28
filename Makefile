# 常用命令：make（编译）、make test、make install、make hooks、make uninstall、make backup
# App 标识（钥匙串、开机自启都用它）：默认 io.github.hebiu；想用自己的，写进 local.mk（不进 git）：BUNDLE_ID = com.你的名字.hebiu
-include local.mk
BUNDLE_ID ?= io.github.hebiu
export BUNDLE_ID

.PHONY: build dev test install install-dev hooks uninstall backup restore art clean icon help

build:            ## 编译通用版（Apple 芯片 + Intel）到 build/Hebiu.app
	scripts/build.sh

dev:              ## 只编本机架构，开发时更快
	ARCH=native scripts/build.sh

test:             ## 跑单元测试（不碰 ~/.hebiu）
	swift test

install:          ## 编译通用版、装到 ~/Applications、打开开机自启并启动
	scripts/install.sh

install-dev:      ## 只编本机架构再安装，改代码时更快
	ARCH=native scripts/install.sh

hooks:            ## 接上 Claude Code（改 ~/.claude/settings.json，先备份）
	scripts/install-hooks.sh

uninstall:        ## 卸载（保留 ~/.hebiu 里的数据）
	scripts/uninstall.sh

backup:           ## 备份数据到桌面（台词设置、待办、来源脚本），换电脑用
	scripts/backup.sh

restore:          ## 从备份恢复：make restore FILE=~/Desktop/hebiu-backup-xxx.tar.gz
	scripts/restore.sh "$(FILE)"

art:              ## 重画默认形象 Biu 的所有帧（要 Chrome 和 node，见 art/biu/README.md）
	cd art/biu && node render.mjs out && python3 -c "from PIL import Image; import glob,os; [Image.open(f).save('../../Resources/characters/default/frames/'+os.path.basename(f)[:-4]+'.webp','WEBP',quality=92) for f in glob.glob('out/*.png')]" && rm -rf out

icon:             ## 重新生成 App 图标（默认用 Biu；换成自己的：make icon ICON_SRC=帧图路径）
	cd icon && python3 make_icon.py $(or $(ICON_SRC),../Resources/characters/default/frames/wave.webp) icon_1024.png
	cd icon && rm -rf AppIcon.iconset && mkdir AppIcon.iconset && for s in 16 32 128 256 512; do \
	  sips -z $$s $$s icon_1024.png --out AppIcon.iconset/icon_$${s}x$${s}.png >/dev/null; \
	  sips -z $$((s*2)) $$((s*2)) icon_1024.png --out AppIcon.iconset/icon_$${s}x$${s}@2x.png >/dev/null; done && \
	  iconutil -c icns AppIcon.iconset -o AppIcon.icns && rm -rf AppIcon.iconset

clean:
	rm -rf build .build

help:             ## 列出所有命令
	@grep -E '^[a-z-]+:.*## ' Makefile | sed 's/:.*## /\t/'
