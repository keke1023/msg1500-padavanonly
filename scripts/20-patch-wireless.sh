#!/usr/bin/env bash
# 把 MSG1500 X.00 的无线驱动从默认的开源 kmod-mt7615e 改为 K2P 风格的闭源 kmod-mt7615d + luci-app-mtwifi。
# padavanonly 主线里 raisecom_msg1500-x-00 的 DEVICE_PACKAGES 默认是：
#   kmod-mt7615e kmod-mt7615-firmware kmod-usb3 ...
# 改为 K2P(phicomm_k2p) 同款闭源方案：
#   kmod-mt7615d luci-app-mtwifi kmod-usb3 ...
# kmod-mt7615d 在 padavanonly 主线由 package/emortal/mt-drivers/mt7615d 提供（MTK 闭源 mt_wifi），
# 与 K2P 设备完全同源，MT7621 单芯片 MT7615 DBDC 可直接用，性能优于开源 mt76。
set -euo pipefail
cd "$(dirname "$0")/../openwrt"

echo "[*] patch MSG1500 X.00 wireless -> closed-source mt7615d (K2P style)"
sed -i 's/kmod-mt7615e kmod-mt7615-firmware/kmod-mt7615d luci-app-mtwifi/' target/linux/ramips/image/mt7621.mk

if grep -q "kmod-mt7615d luci-app-mtwifi" target/linux/ramips/image/mt7621.mk; then
  echo "[+] mt7621.mk patched OK"
else
  echo "!! 未能替换 mt7621.mk 中的无线驱动，请检查 mt7621.mk 结构是否变化"
  exit 1
fi
