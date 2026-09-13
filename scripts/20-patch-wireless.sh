#!/usr/bin/env bash
# 把 MSG1500 X.00 的无线驱动从默认的开源 kmod-mt7615e 改为 K2P 风格的闭源 kmod-mt7615d + luci-app-mtwifi。
# 注意：HWNAT(kmod-ramips_hnat) 不在此注入——它已随 mt7621 target 的 DEFAULT_PACKAGES 进镜像；
# 实证种子/DEVICE_PACKAGES 显式 pin（尤其 =m）反而会导致 ipk 编了却不装进镜像（mtkhnat.ko MISSING）。
# 修复闭源驱动(mt_wifi)下的三个问题：
#   1) MT7615 是 DBDC 芯片，mt7615d config.in 的 MTK_DBDC_MODE 无 default → 强制默认开，保证双频接口都建。
#   2) netifd 不认识 type mt7615 的无线，ra0/rax0 不会自动挂 br-lan：
#      a) uci-defaults 把 ra0/rax0/rai0 写进 /etc/config/network 的 br-lan 端口列表（netifd 原生管理）；
#         驱动由 /lib/preinit/91_load_wifi.sh 在 preinit 阶段加载（早于 netifd S20），netifd 建 br-lan 时端口已存在。
#      b) init.d/mtwifi-bridge（START=99）兜底 brctl addif，带 syslog 日志便于排查。
#   3) Turbo ACC「流量分载」显示 MediaTek HWNAT 的条件是 mtkhnat.ko 已加载（debugfs hnat_version 出现）：
#      init.d/mtkhnat-load（START=60）显式 modprobe 并把结果写 syslog，失败原因可直接 logread 查看。
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

echo "[*] enable HWNAT node in msg1500 dts"
# mt7621.dtsi 里 hnat 节点默认 status="disabled"，必须在设备 dts 里显式打开才会 probe
# （模块 modprobe 成功≠probe 执行；k2p 的 dts 自带 &hnat 块所以 HWNAT 正常，msg1500 没有 →
#   dmesg 零 hnat/ppe 输出、无 debugfs hnat_version、Turbo ACC 显示未运行）。
# 属性依据 hnat.c/hnat_nf_hook.c 源码：wan/ppd 经 dev_get_by_name 按名取 netdev，必须写实际存在的接口；
# ext-devices 为参与 offload 的 wifi 接口列表（不存在者被跳过，无害）；单网口 max-gmac=1。
DTS=target/linux/ramips/dts/mt7621_raisecom_msg1500-x-00.dts
if [ ! -f "$DTS" ]; then
  echo "!! 未找到 msg1500 dts: $DTS"
  exit 1
fi
if ! grep -q '&hnat' "$DTS"; then
cat >> "$DTS" <<'EOF'

&hnat {
	mtketh-wan = "eth0.2";
	mtketh-ppd = "eth0";
	mtketh-lan = "eth0";
	ext-devices = "ra0","rax0","rai0","apcli0","apclix0","apclii0";
	mtketh-max-gmac = <1>;
	status = "okay";
};
EOF
echo "[+] hnat node appended (status=okay)"
else
echo "[=] hnat node already present, skip"
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
# MTK 闭源驱动(mt_wifi)兜底（老式 swconfig 风格 network：option type bridge + option ifname）：
# 1) 把 ra0/rax0 追加进 lan 的 ifname（netifd 建桥时挂入，持久化、reload 不掉）；
#    rax0 必须无条件写入：2.4G 射频初始化比 5G 慢，uci-defaults 执行时可能尚未创建，
#    按存在性过滤会漏掉（实测踩坑）；老式 netifd 对暂不存在的端口会跳过，无害。
#    rai0 仅双芯片 MT7615E 设计才有（第二颗芯片 5G），单芯片 DBDC 不存在，只在真实存在时追加并清理残留。
# 2) wifi-iface 强制 network=lan；
# 3) 清理开源 mt76 驱动残留的旧 wireless 配置。
[ -f /etc/config/wireless ] && grep -Eq 'type mac80211|radio[0-9]+' /etc/config/wireless && rm -f /etc/config/wireless

wifi_ports="ra0 rax0"
[ -e /sys/class/net/rai0 ] && wifi_ports="$wifi_ports rai0"
cur=$(uci -q get network.lan.ifname || true)
add=""
for p in $wifi_ports; do
    case " $cur " in *" $p "*) ;; *) add="$add $p" ;; esac
done
# rai0 仅存在于双芯片 MT7615E 设计（第二颗芯片的 5G）；msg1500 为单芯片 DBDC（ra0=5G/rax0=2.4G），
# 永远不会有 rai0——若旧配置有残留则清除，避免 lan 绑定里出现不存在的接口。
if [ ! -e /sys/class/net/rai0 ]; then
    uci -q del_list network.lan.ifname="rai0"
fi
if [ -n "$add" ]; then
    uci set network.lan.ifname="$cur$add"
    echo "mtwifi: appended$add to lan ifname" | logger -t 99-mtwifi-lan
fi

i=0
while uci -q get wireless.@wifi-iface[$i] >/dev/null 2>&1; do
    dev=$(uci -q get wireless.@wifi-iface[$i].device)
    case "$dev" in
        mt7615*|mt76*) uci set wireless.@wifi-iface[$i].network='lan' ;;
    esac
    i=$((i+1))
done

uci commit network
uci commit wireless
exit 0
EOF
chmod +x files/etc/uci-defaults/99-mtwifi-lan
echo "[+] 99-mtwifi-lan installed"

echo "[*] install persistent init: mtwifi-bridge (brctl 兜底 + syslog 日志)"
mkdir -p files/etc/init.d
cat > files/etc/init.d/mtwifi-bridge <<'EOF'
#!/bin/sh /etc/rc.common
# 兜底：确保 ra0/rax0/rai0 在 br-lan 里（正常情况 99-mtwifi-lan 的 netifd 端口配置已搞定，
# 这里处理 netifd 因端口当时不存在而跳过的边缘情况），所有动作写 syslog 便于 logread 排查。
START=99

boot() {
    local i dev
    # 多轮重试不提前退出：早期轮次加入后可能被 netifd 按（当时缺端口的）旧配置重建 br-lan 逐出，
    # 持续补挂到窗口结束，保证最终稳在桥里。
    for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
        if [ -e /sys/class/net/br-lan ]; then
            for dev in ra0 rax0 rai0; do
                [ -e /sys/class/net/$dev ] || continue
                [ -e /sys/class/net/br-lan/brif/$dev ] && continue
                ifconfig "$dev" up 2>/dev/null
                if brctl addif br-lan "$dev" 2>/dev/null; then
                    logger -t mtwifi-bridge "added $dev to br-lan (round $i)"
                else
                    logger -t mtwifi-bridge "FAILED to add $dev to br-lan (round $i)"
                fi
            done
        fi
        sleep 2
    done
}

start() { boot; }
EOF
chmod +x files/etc/init.d/mtwifi-bridge
echo "[+] mtwifi-bridge installed"

echo "[*] install init: mtkhnat-load (显式加载 HWNAT + syslog 日志)"
cat > files/etc/init.d/mtkhnat-load <<'EOF'
#!/bin/sh /etc/rc.common
# 显式加载 MediaTek HWNAT（mtkhnat.ko 来自 kmod-ramips_hnat，mt7621 target 默认包含）。
# Turbo ACC「流量分载」显示 MediaTek HWNAT 的条件：mtkhnat 已加载 → debugfs 出现 hnat_version。
# turboacc 自身的 modprobe 是静默失败，这里显式加载并把结果/原因写 syslog。
START=60

boot() {
    if [ ! -e "/lib/modules/$(uname -r)/mtkhnat.ko" ]; then
        logger -t mtkhnat "mtkhnat.ko MISSING in /lib/modules/$(uname -r)/"
        return 0
    fi
    # debugfs 未挂载时 hnat_version 永远不存在（会误判 probe 失败），先确保挂载
    [ -d /sys/kernel/debug ] && ! grep -q ' /sys/kernel/debug ' /proc/mounts 2>/dev/null && \
        mount -t debugfs none /sys/kernel/debug 2>/dev/null
    grep -q '^mtkhnat' /proc/modules || modprobe mtkhnat 2>/tmp/mtkhnat.err \
        || logger -t mtkhnat "modprobe FAILED: $(head -n1 /tmp/mtkhnat.err)"
    grep -q '^mtkhnat' /proc/modules && logger -t mtkhnat "loaded ok"
    if [ -e /sys/kernel/debug/hnat/hnat_version ]; then
        logger -t mtkhnat "hnat_version present: $(cat /sys/kernel/debug/hnat/hnat_version 2>/dev/null)"
    else
        logger -t mtkhnat "hnat_version MISSING after load; dmesg dump follows:"
        dmesg 2>/dev/null | grep -iE 'hnat|ppe|hnat_init|extif|gdm' | tail -n 20 | \
            while IFS= read -r line; do logger -t mtkhnat "dmesg: $line"; done
    fi
}

start() { boot; }
EOF
chmod +x files/etc/init.d/mtkhnat-load
echo "[+] mtkhnat-load installed"
