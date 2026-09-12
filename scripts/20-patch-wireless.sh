#!/usr/bin/env bash
# 把 MSG1500 X.00 的无线驱动从默认的开源 kmod-mt7615e 改为 K2P 风格的闭源 kmod-mt7615d + luci-app-mtwifi，
# 并修复闭源驱动(mt_wifi)下的两个共性问题：
#   1) MT7615 是 DBDC（双频并发）芯片，但 mt7615d 的 config.in 里 MTK_DBDC_MODE 无 default，
#      导致编译出的驱动只建 2.4G 的 ra0、不建 5G 的 rai0。这里强制 MTK_DBDC_MODE 默认开，
#      让 rai0（5G）接口被创建（对 K2P 同样受益）。
#   2) 从开源 mt76 驱动升级/切换后，可能残留引用 radio0/radio1 的旧 /etc/config/wireless，
#      mtwifi 的 detect 因文件已存在而不重新生成，导致 ra0/rai0 既不定义也不挂 lan 桥。
#      写入 /etc/uci-defaults/99-mtwifi-lan：首次启动清理旧开源 wireless 配置（让 detect 重建），
#      并确保所有 mt7615 wifi-iface 都挂到 lan，使无线客户端能拿到 IP。
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

echo "[*] force MTK_DBDC_MODE (5G rai0) default y for mt7615d"
if grep -q 'bool "dbdc mode support"' package/emortal/mt-drivers/mt7615d/config.in; then
  sed -i 's|^\(\s*\)bool "dbdc mode support"|\0\n\1default y if MTK_CHIP_MT7615E|' package/emortal/mt-drivers/mt7615d/config.in
  echo "[+] config.in MTK_DBDC_MODE default y patched"
else
  echo "[!] 未找到 dbdc mode support 行，跳过（可能已默认开启）"
fi

echo "[*] install uci-defaults: 99-mtwifi-lan"
mkdir -p files/etc/uci-defaults
cat > files/etc/uci-defaults/99-mtwifi-lan <<'EOF'
#!/bin/sh
# 切换/启用 MTK 闭源驱动(mt_wifi)后，清理残留的开源 mt76 wireless，并让 ra0/rai0 挂到 lan
if [ -f /etc/config/wireless ] && { grep -Eq 'radio0|type mac80211|kmod-mt76|mt76x' /etc/config/wireless || ! grep -q 'rai0' /etc/config/wireless; }; then
    rm -f /etc/config/wireless
fi
i=0
while uci get wireless.@wifi-iface[$i] >/dev/null 2>&1; do
    dev=$(uci get wireless.@wifi-iface[$i].device 2>/dev/null)
    case "$dev" in
        mt7615*|mt76*) uci set wireless.@wifi-iface[$i].network='lan' ;;
    esac
    i=$((i+1))
done
uci commit wireless
exit 0
EOF
chmod +x files/etc/uci-defaults/99-mtwifi-lan
echo "[+] 99-mtwifi-lan installed"
