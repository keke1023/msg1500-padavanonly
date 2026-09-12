#!/usr/bin/env bash
# 把 MSG1500 X.00 的无线驱动从默认的开源 kmod-mt7615e 改为 K2P 风格的闭源 kmod-mt7615d + luci-app-mtwifi，
# 并修复闭源驱动(mt_wifi)下的两个共性问题：
#   1) MT7615 是 DBDC（双频并发）芯片，但 mt7615d 的 config.in 里 MTK_DBDC_MODE 无 default，
#      导致编译出的驱动只建 2.4G 的 ra0、不建 5G 的 rai0。这里强制 MTK_DBDC_MODE 默认开，
#      让 rai0（5G）接口被创建（对 K2P 同样受益）。
#   2) 从开源 mt76 驱动升级/切换后，可能残留引用 radio0/radio1 的旧 /etc/config/wireless，
#      mtwifi 的 detect 因文件已存在而不重新生成，导致 ra0/rai0 既不定义也不挂 lan 桥。
#      写入 /etc/uci-defaults/99-mtwifi-lan：首次启动清理旧 wireless 配置（让 detect 重建）、
#      用 ROM 修正版刷新被驱动运行时改写的 l1profile/.dat，并确保所有 mt7615 wifi-iface 挂 lan。
#   3) 【关键修复】DBDC 双频接口命名错乱（2.4G 被建成 rax0、5G 被建成 ra0）。
#      根因在 mt_wifi 包的 7615d.l1profile.dat：原把 5G profile 排第一且
#      INDEX0_main_ifname=ra0;rax0（rax 是多卡前缀表第 4 项，被错当 band1 前缀），
#      驱动据此建出 ra0(5G)+rax0(2.4G)。修正为 2.4G profile 排第一、5G 第二，
#      且 ifname 前缀用 ra/rai（而非 ra/rax），即 2.4G=ra0、5G=rai0。
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

echo "[*] fix 7615d.l1profile.dat: 让 DBDC 双频命名正确（2.4G=ra0, 5G=rai0）"
# 根因：原 l1profile 把 5G profile 排第一且 INDEX0_main_ifname=ra0;rax0，
#       导致驱动建出 ra0(5G) + rax0(2.4G)（rax 是 MediaTek 多卡前缀表第 4 项，被错当 band1 前缀）。
# 修正：2.4G profile 排第一、5G 第二，且 ifname 前缀用 ra/rai（而非 ra/rax）。
L1=package/emortal/mt-drivers/mt_wifi/files/7615d.l1profile.dat
if [ -f "$L1" ]; then
  sed -i 's#^INDEX0_profile_path=.*#INDEX0_profile_path=/etc/wireless/mt7615/mt7615.1.2G.dat;/etc/wireless/mt7615/mt7615.1.5G.dat#' "$L1"
  sed -i 's#^INDEX0_main_ifname=.*#INDEX0_main_ifname=ra0;rai0#' "$L1"
  sed -i 's#^INDEX0_ext_ifname=.*#INDEX0_ext_ifname=ra;rai#' "$L1"
  sed -i 's#^INDEX0_wds_ifname=.*#INDEX0_wds_ifname=wds;wdsi#' "$L1"
  sed -i 's#^INDEX0_apcli_ifname=.*#INDEX0_apcli_ifname=apcli;apclii#' "$L1"
  echo "[+] 7615d.l1profile.dat fixed (2.4G=ra0 / 5G=rai0)"
else
  echo "[!] 未找到 7615d.l1profile.dat，跳过（DBDC 命名修正可能未生效，请检查 mt_wifi 包结构）"
fi

echo "[*] install uci-defaults: 99-mtwifi-lan"
mkdir -p files/etc/uci-defaults
cat > files/etc/uci-defaults/99-mtwifi-lan <<'EOF'
#!/bin/sh
# 切换/启用 MTK 闭源驱动(mt_wifi)后，清理残留旧无线状态，让 ra0(2.4G)/rai0(5G) 正确挂到 lan。
# 1) 用 ROM 里修正版覆盖被驱动运行时改写的 l1profile 与 .dat（overlay 残留会盖掉 ROM 修正版）。
#    用 cp 而非 rm：避免 overlayfs 对 ROM-only 文件产生 whiteout，导致驱动加载时找不到 l1profile。
if [ -d /rom/etc/wireless/mt7615 ]; then
    cp -f /rom/etc/wireless/l1profile.dat /etc/wireless/l1profile.dat 2>/dev/null || true
    cp -rf /rom/etc/wireless/mt7615/. /etc/wireless/mt7615/ 2>/dev/null || true
fi
# 2) 删除旧单频/错误命名(rax0/ra0)的 wireless 配置（缺 rai0 即认为需重建），
#    让 mtwifi detect 用正确 ra0/rai0 重新生成 /etc/config/wireless
if [ -f /etc/config/wireless ] && ! grep -q 'rai0' /etc/config/wireless; then
    rm -f /etc/config/wireless
fi
# 3) 双保险：所有 mt7615 / mt76 wifi-iface 强制挂 lan
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
