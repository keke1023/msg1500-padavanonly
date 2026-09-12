#!/usr/bin/env bash
# 把 MSG1500 X.00 的无线驱动从默认的开源 kmod-mt7615e 改为 K2P 风格的闭源 kmod-mt7615d + luci-app-mtwifi，
# 并补上 kmod-ramips_hnat（MediaTek HWNAT 内核模块 mtkhnat.ko，Turbo ACC 的“硬件流量分载”依赖它，
# k2p 默认带、msg1500 的 DEVICE_PACKAGES 原本不含，故显式注入）；同时用常驻 init 脚本确保 ra0/rax0 进 br-lan。
# 另修复闭源驱动(mt_wifi)下的两个共性问题：
#   1) MT7615 是 DBDC（双频并发）芯片，但 mt7615d 的 config.in 里 MTK_DBDC_MODE 无 default，
#      导致编译出的驱动只建 2.4G 的 ra0、不建 5G 的 rai0。这里强制 MTK_DBDC_MODE 默认开，
#      让 rai0（5G）接口被创建（对 K2P 同样受益）。
#   2) 从开源 mt76 驱动升级/切换后，可能残留引用 radio0/radio1 的旧 /etc/config/wireless，
#      mtwifi 的 detect 因文件已存在而不重新生成，导致 ra0/rai0 既不定义也不挂 lan 桥。
#      写入 /etc/uci-defaults/99-mtwifi-lan：首次启动清理旧开源 wireless 配置（让 detect 重建），
#      并确保所有 mt7615 wifi-iface 都挂到 lan，使无线客户端能拿到 IP。
set -euo pipefail
cd "$(dirname "$0")/../openwrt"

echo "[*] patch MSG1500 X.00 wireless -> closed-source mt7615d (K2P style) + HWNAT"
sed -i 's/kmod-mt7615e kmod-mt7615-firmware/kmod-mt7615d luci-app-mtwifi kmod-ramips_hnat/' target/linux/ramips/image/mt7621.mk

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

echo "[*] install persistent init script: mtwifi-bridge (确保 ra0/rax0/rai0 加入 br-lan)"
# mt7615_up() 里虽有 brctl addif br-lan ra0 rax0 rai0，但在部分机型上因启动时序
# (br-lan 尚未建好 / 2.4G rax0 射频尚未就绪) 而失效，导致无线客户端拿不到 IP。
# 这里在 boot 末期(START=99)重试加入，不依赖 detect 时序。
mkdir -p files/etc/init.d files/etc/rc.d
cat > files/etc/init.d/mtwifi-bridge <<'EOF'
#!/bin/sh /etc/rc.common
# 确保 MTK 闭源驱动(mt_wifi)的无线接口 ra0/rax0/rai0 加入 br-lan。
# 部分机型 mt7615_up 的 brctl addif 因启动时序(br-lan 未建好/2.4G 射频未就绪)失效，
# 这里在 boot 末期重试，保证无线客户端能拿到 IP。
START=99

boot() {
    local i dev
    for i in $(seq 1 20); do
        [ -d /sys/class/net/br-lan ] || { sleep 1; continue; }
        for dev in ra0 rax0 rai0; do
            [ -d /sys/class/net/$dev ] || continue
            ifconfig "$dev" up 2>/dev/null
            brctl addif br-lan "$dev" 2>/dev/null
        done
        sleep 1
    done
}

start() { boot; }
EOF
chmod +x files/etc/init.d/mtwifi-bridge
ln -sf ../init.d/mtwifi-bridge files/etc/rc.d/S95mtwifi-bridge
echo "[+] mtwifi-bridge installed + enabled (START=99)"
