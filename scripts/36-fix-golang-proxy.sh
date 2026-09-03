#!/usr/bin/env bash
# 修复：padavanonly 18.06 的 golang 构建把 GOPROXY 列为 "Unmodified"（不设置），
# 直接继承 CI runner 的 GOPROXY 环境变量。当该值变成无效串（如仅分隔符 ","）时，
# go 解析后报 "GOPROXY list is not the empty string, but contains no entries"，
# 导致任何依赖 Go 模块的包（frp / ngrokc / ssr-plus 等）在编译阶段拉不到依赖而失败。
#
# 修法：在 golang 构建上下文（golang-values.mk 末尾）强制 export 一个有效的 GOPROXY，
# 并关闭 sumdb 校验（避免 sum.golang.org 不可达拖慢/失败）。带 direct 兜底，
# 即便 proxy 被墙也能走 git 直连（runner 本身能访问 github）。

set -e

# 优先官方 proxy.golang.org，其次 goproxy.cn，最后 direct（git 直连 github）
PROXY="https://proxy.golang.org,https://goproxy.cn,direct"

BLOCK='
# [padavanonly-msg1500-patch] 强制有效 GOPROXY，修复 frp/ngrokc 等模块下载失败
export GOPROXY:='"$PROXY"'
export GOSUMDB:=off
export GONOSUMDB:=*
export GOPRIVATE:=
'

# 同时修补 feeds/ 源与 package/feeds/ 安装副本，确保构建期一定生效
mapfile -t FILES < <(find . -path '*/lang/golang/golang-values.mk' 2>/dev/null)
echo "found golang-values.mk: ${FILES[@]:-NONE}"

for f in "${FILES[@]}"; do
  if ! grep -q 'padavanonly-msg1500-patch' "$f"; then
    printf '%s\n' "$BLOCK" >> "$f"
    echo "patched: $f"
  else
    echo "already patched: $f"
  fi
done

echo "--- 验证 GOPROXY 注入 ---"
grep -h 'GOPROXY' "${FILES[@]}" | grep -v '^#' | head
