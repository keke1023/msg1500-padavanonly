#!/usr/bin/env bash
# 把 padavanonly/immortalwrt 自带的 Phicomm K2P（mt7621，原厂 16MB SPI NOR）改成 32MB 闪存版 K2P-32M。
# 重要：本仓库底座是 padavanonly/immortalwrt，其 K2P 定义与"官方 OpenWrt"不同，网上流传的改法在这套 base 上不对症：
#   * K2P 的 IMAGE_SIZE 是 16064k（不是 15744k），且全文件 16064k 出现 36 次 —— 必须用「设备块范围 sed」只改 K2P 那块；
#   * firmware 分区是 <0x50000 0xfb0000>（不是 <0xa0000 0xf60000>），扩成 <0x50000 0x1fb0000>；
#   * K2P 的 DEVICE_PACKAGES 默认就是 kmod-mt7615d luci-app-mtwifi（闭源 MTK mt_wifi），无需再 patch 无线。
set -euo pipefail
cd "$(dirname "$0")/../openwrt"

MK=target/linux/ramips/image/mt7621.mk
DTS=target/linux/ramips/dts/mt7621_phicomm_k2p.dts

echo "[*] patch Phicomm K2P -> K2P-32M (32MB flash)"

# 1) IMAGE_SIZE：仅改 K2P 设备块（define Device/phicomm_k2p .. endef 范围内）
sed -i '/define Device\/phicomm_k2p/,/endef/s/IMAGE_SIZE := 16064k/IMAGE_SIZE := 32128k/' "$MK"

# 2) DTS 模型名（LuCI/界面显示为 K2P-32M）
sed -i 's/"Phicomm K2P";/"Phicomm K2P-32M";/g' "$DTS"

# 3) DTS 在 spi-max-frequency 之后插入 broken-flash-reset（2 个 tab 缩进，与 flash 节点对齐）
sed -i '/spi-max-frequency/a\		broken-flash-reset;' "$DTS"

# 4) DTS firmware 分区扩到 32M（占满整颗闪存）
sed -i 's/<0x50000 0xfb0000>/<0x50000 0x1fb0000>/g' "$DTS"

# ---- 校验（任一失败立即退出，避免编出坏固件）----
grep -q "IMAGE_SIZE := 32128k" "$MK" || { echo "!! IMAGE_SIZE 未改成 32128k"; exit 1; }
grep -q '"Phicomm K2P-32M";' "$DTS" || { echo "!! DTS 模型名未改成 K2P-32M"; exit 1; }
grep -q "broken-flash-reset;" "$DTS" || { echo "!! broken-flash-reset 未注入"; exit 1; }
grep -q "<0x50000 0x1fb0000>" "$DTS" || { echo "!! firmware 分区未扩到 32M"; exit 1; }
echo "[+] K2P-32M patch OK"
