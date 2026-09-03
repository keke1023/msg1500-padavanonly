#!/usr/bin/env bash
# 剔除 helloworld feed 中所有 rust 实现的包（已确认 master 分支共 3 个）：
#   - shadowsocks-rust
#   - dns2socks-rust
#   - shadow-tls（rust 实现，且 DEPENDS 本就不含 mipsel）
#
# 判定标准：目录名含 rust，或 Makefile 引用 rust-package.mk / rust/host / Cargo.toml。
# luci-app-ssr-plus 本体只在"可选项"里提到 rust 包名，不含上述标记，不会被误删；
# 其 rust 相关 INCLUDE 选项已在种子配置中显式关闭，且校验步骤会兜底。
set -euo pipefail
cd "$(dirname "$0")/../openwrt"

removed=()
for mk in feeds/helloworld/*/Makefile; do
  dir=$(dirname "$mk")
  name=$(basename "$dir")
  # ssr-plus 本体必须保留
  [ "$name" = "luci-app-ssr-plus" ] && continue
  if [[ "$name" == *rust* ]] || grep -qE 'rust-package\.mk|rust/host|Cargo\.toml' "$mk"; then
    removed+=("$name")
    rm -rf "$dir"
    rm -f "package/feeds/helloworld/$name"
  fi
done

if [ "${#removed[@]}" -eq 0 ]; then
  echo "!! 未发现任何 rust 包 —— helloworld 布局可能已变化，请人工检查 feeds/helloworld"
  exit 1
fi

echo "[*] 已剔除 rust 包："
printf '  - %s\n' "${removed[@]}"
