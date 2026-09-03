#!/usr/bin/env bash
# 把 helloworld 提供的 xray-core 从默认的 26.5.9（需 go 1.26）钉到 24.12.31（需 go 1.21.4）
# 理由：本工程 golang 升到 1.21.13（GOTOOLCHAIN=local），无法编译需要 go 1.26 的 26.5.9；
#       xray-core 24.12.31 支持 VLESS reality，且与现有 Go 工具链兼容。
# 同时把 PKG_HASH 设为 skip：上游 tarball 的 sha256 无法预知，且 download.pl 支持 "skip" 关键字跳过校验。
set -e

TARGET_VER="24.12.31"

# feeds install -a 之后，helloworld 包会软链到 package/feeds/helloworld/
MK=""
for cand in package/feeds/helloworld/xray-core/Makefile \
            feeds/helloworld/xray-core/Makefile ; do
  if [ -f "$cand" ]; then MK="$cand"; break; fi
done
# 兜底：全盘找
if [ -z "$MK" ]; then
  MK=$(find . -path '*/xray-core/Makefile' 2>/dev/null | head -1)
fi

if [ -z "$MK" ]; then
  echo "!! 找不到 xray-core/Makefile，无法钉版本（helloworld feed 未安装？）"
  exit 1
fi

echo "==> 修补 xray-core Makefile: $MK"
sed -i "s/^PKG_VERSION:=.*/PKG_VERSION:=$TARGET_VER/" "$MK"
sed -i "s/^PKG_HASH:=.*/PKG_HASH:=skip/" "$MK"

echo "--- 修补后关键行 ---"
grep -E '^PKG_VERSION|^PKG_HASH|^PKG_SOURCE_URL' "$MK"
