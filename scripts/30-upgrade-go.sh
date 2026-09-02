#!/usr/bin/env bash
# 把 padavanonly/packages(openwrt-18.06) 的 golang 从 1.20.2 升级到 1.21.13。
# 理由：frpc/ngrokc 等 Go 程序需要较新的 go；1.20.2 偏老，升到 1.21.13 更稳。
# 注意：padavanonly 的 golang Makefile 写死 GO_VERSION_MAJOR_MINOR:=1.20 / GO_VERSION_PATCH:=2，
# 且 bootstrap 链为 go1.4 + go1.17.13（go1.17 满足 go1.21 的 bootstrap 要求），
# 仅改版本号 + PKG_HASH 即可，bootstrap 链不动，风险极低。
# 1.21.13 的 PKG_HASH 取自 openwrt/packages openwrt-23.05 官方 Makefile（权威值）。
set -euo pipefail
cd "$(dirname "$0")/../openwrt"

F=feeds/packages/lang/golang/golang/Makefile
if [ ! -f "$F" ]; then
  echo "!! 未找到 golang Makefile：$F"
  exit 1
fi

echo "[*] upgrade golang -> 1.21.13 (was 1.20.2)"
sed -i 's/^GO_VERSION_MAJOR_MINOR:=1.20/GO_VERSION_MAJOR_MINOR:=1.21/' "$F"
sed -i 's/^GO_VERSION_PATCH:=2/GO_VERSION_PATCH:=13/' "$F"
sed -i 's|^PKG_HASH:=.*|PKG_HASH:=71fb31606a1de48d129d591e8717a63e0c5565ffba09a24ea9f899a13214c34d|' "$F"

echo "[*] 验证 golang Makefile："
grep -E '^GO_VERSION_MAJOR_MINOR|^GO_VERSION_PATCH|^PKG_HASH' "$F"
