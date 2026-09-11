#!/usr/bin/env bash
# 在 padavanonly/immortalwrt 的 feeds.conf.default 中加入 helloworld(master) feed 并更新 feeds。
#
# ⚠️ 关键点：helloworld 必须排在【 src-git packages 之前 / 文件最前】，绝不能追加到末尾！
# 原因：padavanonly 自带的 luci fork（openwrt-18.06-k5.4）在 applications/ 下 vendored 了一份
#       luci-app-ssr-plus（PKG_VERSION=186，旧版）。OpenWrt `feeds install -a` 按 feeds.conf 顺序、
#       靠前的 feed 优先；若 helloworld 追加到末尾，则 luci feed 的 186 会覆盖 helloworld master 的 190，
#       导致编出的 ssr-plus 是旧版 186 而非 helloworld master 的 190。
#       把 helloworld 插到最前，其 ssr-plus(190)/v2ray/xray 等代理包即优先于 luci/packages fork 的旧版。
#
# 只做 update 不 install —— install 放到 rust 剔除 + golang 升级之后统一执行，
# 保证 feeds install -a 看到的是"改造后"的 feed。
set -euo pipefail
cd "$(dirname "$0")/../openwrt"

HW_BRANCH="${HELLOWORLD_BRANCH:-master}"

# 无论之前在哪，都先移除旧的 helloworld 行，再插到 src-git packages 之前（最前），保证优先级
sed -i "/^src-git helloworld/d" feeds.conf.default
sed -i "/^src-git packages/i src-git helloworld https://github.com/fw876/helloworld.git;${HW_BRANCH}" feeds.conf.default

./scripts/feeds update -a

echo "[*] feeds 更新完成，helloworld 行位于最前："
grep -n "^src-git" feeds.conf.default
