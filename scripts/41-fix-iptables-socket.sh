#!/usr/bin/env bash
# 给 18.06 基线源码补 iptables-mod-socket 兼容元包
#
# 背景（与 openwrt-r6220 仓库同款问题）：
#   helloworld master 的 luci-app-ssr-plus/root/etc/init.d/shadowsocksr 启动时会做一次
#   纯静态自检，检查 /usr/lib/opkg/info/<pkg>.control 是否存在：
#     dep_list="iptables-mod-tproxy iptables-mod-socket iptables-mod-iprange
#               iptables-mod-conntrack-extra kmod-ipt-nat"
#   缺任一即 echolog "警告：iptables 透明代理缺失基础依赖 <pkg>！"
#
#   而 padavanonly/immortalwrt（18.06 基线，iptables 1.8.7）的
#   package/network/utils/iptables/Makefile 里 **没有 Package/iptables-mod-socket**：
#     · socket match（libxt_socket.so）由 BuildPlugin(iptables-mod-tproxy,
#       $(IPT_TPROXY-m)) 一并拷进 iptables-mod-tproxy；
#     · 内核 xt_socket.ko / nf_socket_ipv4 / nf_socket_ipv6 也都在 kmod-ipt-tproxy
#       （include/netfilter.mk 的 IPT_TPROXY 组）；
#     · 23.05 起才拆成独立的 iptables-mod-socket + kmod-ipt-socket。
#   → 功能一个都不缺，只是包名代差导致的误报。
#
# 做法：注入一个**空元包** iptables-mod-socket，DEPENDS:=+iptables-mod-tproxy，
#   安装后仅生成 /usr/lib/opkg/info/iptables-mod-socket.control 让自检命中；
#   刻意**不安装任何文件**，否则会与 iptables-mod-tproxy 争抢 libxt_socket.so，
#   触发 opkg 的 check_data_file_clashes。
#
# 判据：仅当主源 iptables Makefile 无 Package/iptables-mod-socket（=18.06 系）时注入；
#       23.05+ 自带真包时自动跳过，不会重名冲突。
set -euo pipefail
cd "$(dirname "$0")/../openwrt"

IPT_MK="package/network/utils/iptables/Makefile"
COMPAT_DIR="package/network/utils/iptables-mod-socket-compat"

if [ ! -f "$IPT_MK" ]; then
  echo "!! 未找到 $IPT_MK —— 源码布局异常，中止（否则 ssr-plus 会持续误报）"
  exit 1
fi

if grep -q "Package/iptables-mod-socket" "$IPT_MK"; then
  echo "[*] 主源自带 iptables-mod-socket（23.05+ 系），无需注入兼容元包"
  exit 0
fi

if [ -f "$COMPAT_DIR/Makefile" ]; then
  echo "[*] iptables-mod-socket 兼容元包已存在，跳过"
  exit 0
fi

echo "[*] 注入 iptables-mod-socket 兼容元包（18.06 系：socket match 实际在 iptables-mod-tproxy 内）"
mkdir -p "$COMPAT_DIR"
cat > "$COMPAT_DIR/Makefile" <<'MKEOF'
# 兼容元包：18.06 系源码没有独立的 iptables-mod-socket 包。
# 真正的 socket match（libxt_socket.so）与内核 xt_socket.ko / nf_socket_ipv4/ipv6
# 都在 iptables-mod-tproxy / kmod-ipt-tproxy 里，本包只提供包名，不安装任何文件。
include $(TOPDIR)/rules.mk

PKG_NAME:=iptables-mod-socket
PKG_RELEASE:=1

include $(INCLUDE_DIR)/package.mk

define Package/iptables-mod-socket
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=Firewall
  TITLE:=Socket match iptables extensions (compat meta package)
  DEPENDS:=+iptables-mod-tproxy
  PKGARCH:=all
endef

define Package/iptables-mod-socket/description
Compatibility meta package for 18.06 based sources. The iptables socket
match (libxt_socket.so) and the xt_socket kernel modules are shipped
inside iptables-mod-tproxy / kmod-ipt-tproxy on this branch.
endef

define Build/Prepare
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/iptables-mod-socket/install
endef

$(eval $(call BuildPackage,iptables-mod-socket))
MKEOF

echo "[*] 已写入 $COMPAT_DIR/Makefile"
echo "[*] 依赖链：iptables-mod-socket -> iptables-mod-tproxy -> kmod-ipt-tproxy（xt_socket/nf_socket_* + libxt_socket.so）"
