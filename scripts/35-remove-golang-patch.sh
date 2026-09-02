#!/bin/bash
# 升级 golang 到 1.21.x 后必须删除的“过时补丁”
#
# 背景（已在诊断 run 33642847224 实锤）：
#   padavanonly/immortalwrt 的 packages feed（openwrt-18.06）里，golang 包带一个本地补丁
#   001-cmd-link-use-gold-on-ARM-ARM64-only-if-gold-is-available.patch，
#   它只改 src/cmd/link/internal/ld/lib.go 里「仅 ARM/ARM64 目标」才会进入的代码分支，
#   让 go 链接器在 ARM/ARM64 上改用 gold。
#   - 该补丁是给 go1.20.x 写的；升到 go1.21.13 后源码那一段行号/上下文变了，
#     导致 `make` prepared 阶段 `Hunk #1 FAILED at 1535` 直接挂掉（ERROR: golang [host] failed to build）。
#   - 我们的构建是 amd64 host + ramips/MIPS target，根本不会走这条 ARM/ARM64 路径，补丁毫无作用。
#   - go1.21 上游已自带此修复（openwrt 23.05 的 golang 包完全没有任何本地 patches 目录）。
# 结论：升级 golang 后删除该补丁即可，删掉对最终固件零影响。
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENWRT_DIR="${OPENWRT_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)/openwrt}"

PATCH="001-cmd-link-use-gold-on-ARM-ARM64-only-if-gold-is-available.patch"
FOUND=0

# 两个可能的位置：feeds 源目录（真实构建所用）、feeds install 后的符号/拷贝目录
for d in \
  "$OPENWRT_DIR/feeds/packages/lang/golang/golang/patches" \
  "$OPENWRT_DIR/package/feeds/packages/golang/patches" ; do
  if [ -f "$d/$PATCH" ]; then
    echo "删除过时 golang 补丁: $d/$PATCH"
    rm -f "$d/$PATCH"
    FOUND=1
  else
    echo "（无 $d/$PATCH，跳过）"
  fi
done

if [ "$FOUND" = "0" ]; then
  echo "提示：未找到该补丁，说明 golang 包已无此过时补丁（或版本已变），无需处理。"
fi
echo "remove-golang-patch: done."
