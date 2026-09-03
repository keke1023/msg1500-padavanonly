#!/usr/bin/env bash
# 把 padavanonly/packages(openwrt-18.06) 的 golang 升级到 1.27.1，
# 以编译 helloworld master 的 xray-core 26.5.9（go.mod 要求 go 1.26）。
#
# 关键约束：18.06 的 golang Makefile 是「源码两段式引导」：
#   go1.4 源码 -> Bootstrap-1.17(go1.17.13 源码, 用 go1.4 编) -> 主版本(用 go1.17.13 编)
# Go 引导规则：编 N 版本需 N-2 的引导器，故 go1.17.13 最多只能编出 go1.21。
# 要编 go1.27.1 必须换掉引导器。
#
# 做法：把 BOOTSTRAP_1_17_SOURCE 换成「预编译的 go1.26.8」（>=1.24.6，可直接引导 go1.27.1），
# 并就地改写 Host/Compile 定义，让主版本 go1.27.1 直接用预编译 go1.26.8 作 GOROOT_BOOTSTRAP，
# 彻底跳过 go1.4 / go1.17.13 两段源码引导（它们用旧引导器必然失败）。
#
# 关键坑（已踩）：不能在文件末尾追加覆盖 GoCompiler/Bootstrap-1.17/Make 等宏 ——
#   HostBuild 在 Host/Compile 之后立刻把配方烘焙定型，末尾追加对 AddProfile 生成的宏无效；
#   必须就地改写 Host/Compile 本体（Python 精确替换），位于 $(eval $(call HostBuild)) 之前。
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

# --- 就地改写 Host/Compile：只用预编译 go1.26.8 引导主版本，跳过两段源码引导 ---
python3 - "$F" <<'PY'
import sys, re
path = sys.argv[1]
src = open(path, encoding='utf-8').read()

T = "\t"
new_block = (
    "define Host/Compile\n"
    + T + "# 预编译 go1.26.8 已由 BOOTSTRAP_1_17_UNPACK 解压到 $(BOOTSTRAP_1_17_BUILD_DIR)\n"
    + T + "# 直接用它作为主版本 go1.27.1 的 GOROOT_BOOTSTRAP，跳过 go1.4/go1.17.13 源码引导\n"
    + T + "$(call GoCompiler/Host/Make, \\\n"
    + T*2 + 'GOROOT_BOOTSTRAP="$(BOOTSTRAP_1_17_BUILD_DIR)" \\\n'
    + T*2 + '$(if $(HOST_GO_ENABLE_PIE),GO_LDFLAGS="-buildmode pie") \\\n'
    + T*2 + "$(HOST_GO_VARS) \\\n"
    + T + ")\n"
    "endef"
)

# 正则：从 define Host/Compile 到其后第一个 endef（避免精确匹配对空白敏感而失败）
pattern = re.compile(r"define Host/Compile\n.*?\nendef\n", re.S)
if not pattern.search(src):
    raise SystemExit("!! 未匹配到 Host/Compile 块，可能 Makefile 结构已变化")
src = pattern.sub(new_block + "\n", src, count=1)
open(path, 'w', encoding='utf-8').write(src)
print("[*] Host/Compile 已改为仅用预编译 go1.26.8 引导主版本")
PY

echo "[*] 验证 golang Makefile："
grep -E '^GO_VERSION_MAJOR_MINOR|^GO_VERSION_PATCH|^PKG_HASH|^BOOTSTRAP_1_17_SOURCE|^BOOTSTRAP_1_17_HASH' "$F"
echo "[*] Host/Compile 改写确认："
awk '/^define Host\/Compile/{f=1} f{print} /^endef/&&f{f=0}' "$F"
