#!/usr/bin/env bash
# 用 helloworld(master) 的 xray-core recipe (26.7.28) 覆盖 packages feed 里的旧版 (1.8.1)。
#
# 背景（run 33741726043 失败根因）：
#   packages feed 的 xray-core 是 1.8.1，其 wireguard 功能依赖 2022 年的旧 gvisor，
#   而 gvisor 旧版的 pkg/gohacks 在 linux/mipsle(softfloat) 下所有 Go 文件都被 build
#   constraints 排除 -> 空包 -> 依赖链断裂 -> xray-core 编译失败
#   （日志：imports gvisor.dev/gvisor/pkg/gohacks: build constraints exclude all Go files）。
#   helloworld 的 xray-core 已是 26.7.28，改用新 wireguard 实现，不再有此问题，且需 go1.26，
#   已由 30-upgrade-go.sh 把宿主 go 升到 1.27.1 满足。
#
# 做法：feeds update 已把 helloworld clone 到 feeds/helloworld/，直接把它的
#   xray-core/Makefile 复制覆盖 packages feed 的 net/xray-core/Makefile 即可。
#   覆盖后无论 install -a 选 packages 还是 helloworld 的 xray-core，最终都是 26.7.28。
set -euo pipefail
cd "$(dirname "$0")/../openwrt"

SRC=feeds/helloworld/xray-core/Makefile
DST=feeds/packages/net/xray-core/Makefile

if [ ! -f "$SRC" ]; then
  echo "!! 未找到 helloworld xray-core recipe：$SRC（请确认 helloworld feed 已 update）"
  exit 1
fi
if [ ! -d "$(dirname "$DST")" ]; then
  echo "!! 未找到 packages feed 的 xray-core 目录：$(dirname "$DST")"
  exit 1
fi

echo "[*] 用 helloworld 的 xray-core 26.7.28 覆盖 packages feed 旧版 (1.8.1)"
cp -v "$SRC" "$DST"
echo "[*] 覆盖后 xray-core recipe 版本："
grep -E "^PKG_VERSION|^PKG_HASH" "$DST"
