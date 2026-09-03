#!/usr/bin/env bash
# 在 padavanonly/immortalwrt 的 feeds.conf.default 末尾追加 helloworld(master) feed 并更新 feeds。
# 注意：padavanonly 的 feeds.conf.default 默认只有 packages/luci/routing/telephony，没有 helloworld 行，
# 所以这里用追加（与 lede 版"去注释"不同）。
# 只做 update 不 install —— install 放到 rust 剔除 + golang 升级之后统一执行，
# 保证 feeds install -a 看到的是"改造后"的 feed。
set -euo pipefail
cd "$(dirname "$0")/../openwrt"

HW_BRANCH="${HELLOWORLD_BRANCH:-master}"

echo "[*] 追加 helloworld(${HW_BRANCH}) feed"
grep -q "^src-git helloworld" feeds.conf.default || \
  echo "src-git helloworld https://github.com/fw876/helloworld.git;${HW_BRANCH}" >> feeds.conf.default

./scripts/feeds update -a

echo "[*] feeds 更新完成："
grep "helloworld" feeds.conf.default
