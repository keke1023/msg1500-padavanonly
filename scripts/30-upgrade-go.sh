#!/usr/bin/env bash
# 把 padavanonly/packages(openwrt-18.06) 的 golang 升级到 1.27.1，
# 以编译 helloworld master 的 xray-core 26.5.9（go.mod 要求 go 1.26）。
#
# 关键约束：18.06 的 golang Makefile 是「源码两段式引导」：
#   go1.4 源码 -> Bootstrap-1.17(go1.17.13 源码, 用 go1.4 编) -> 主版本(用 go1.17.13 编)
# Go 引导规则：编 N 版本需 N-2 的引导器，故 go1.17.13 最多只能编出 go1.21。
# 要编 go1.27.1 必须换掉 Bootstrap-1.17 的引导器：
#   把 BOOTSTRAP_1_17_SOURCE 从「go1.17.13 源码」换成「预编译的 go1.26.8」
#   （go1.26.8 可直接编 go1.27.1，且 >= 1.25 满足 bootstrap 要求）。
# 预编译包解压即完整 go，无需、也不能再跑 make.bash（否则会用 go1.4 引导器重建而失败），
#   故把 GoCompiler/Bootstrap-1.17/Make 覆盖成 no-op，让解压好的 go1.26.8 直接当 GOROOT_BOOTSTRAP。
#
# 权威 hash（取自 https://go.dev/dl/?mode=json）：
#   go1.27.1.src.tar.gz      = 4e408abae126d916b6164627193f2c54f0e3ca1312d693b86db45f862ab238b1
#   go1.26.8.linux-amd64.gz  = d0f743b33e8d8945e6b1f432edd15785c70507121d6e2a723b21285eddf8b57b
set -euo pipefail
cd "$(dirname "$0")/../openwrt"

F=feeds/packages/lang/golang/golang/Makefile
if [ ! -f "$F" ]; then
  echo "!! 未找到 golang Makefile：$F"
  exit 1
fi

echo "[*] upgrade golang -> 1.27.1 (was 1.20.2) + precompiled bootstrap go1.26.8"

# --- 主版本：1.27.1 ---
sed -i 's/^GO_VERSION_MAJOR_MINOR:=1.20/GO_VERSION_MAJOR_MINOR:=1.27/' "$F"
sed -i 's/^GO_VERSION_PATCH:=2/GO_VERSION_PATCH:=1/' "$F"
sed -i 's|^PKG_HASH:=.*|PKG_HASH:=4e408abae126d916b6164627193f2c54f0e3ca1312d693b86db45f862ab238b1|' "$F"

# --- Bootstrap-1.17：换成预编译 go1.26.8（不再从源码编 go1.17.13）---
sed -i 's|^BOOTSTRAP_1_17_SOURCE:=.*|BOOTSTRAP_1_17_SOURCE:=go1.26.8.linux-amd64.tar.gz|' "$F"
sed -i 's|^BOOTSTRAP_1_17_HASH:=.*|BOOTSTRAP_1_17_HASH:=d0f743b33e8d8945e6b1f432edd15785c70507121d6e2a723b21285eddf8b57b|' "$F"

# --- 覆盖 Bootstrap-1.17/Make 为 no-op（预编译包无需 make.bash）---
# 追加到 Makefile 末尾，parse 顺序晚于 AddProfile，故覆盖生效。
printf '\n# === PATCH: 预编译 go1.26.8 直接作为 bootstrap，跳过 make.bash ===\n' >> "$F"
printf 'define GoCompiler/Bootstrap-1.17/Make\n' >> "$F"
printf '\ttrue\n' >> "$F"
printf 'endef\n' >> "$F"

echo "[*] 验证 golang Makefile："
grep -E '^GO_VERSION_MAJOR_MINOR|^GO_VERSION_PATCH|^PKG_HASH|^BOOTSTRAP_1_17_SOURCE|^BOOTSTRAP_1_17_HASH' "$F"
echo "[*] 末尾 Bootstrap-1.17/Make 覆盖："
tail -n 4 "$F"
