#!/usr/bin/env bash
# 一键推送本项目到 GitHub（请在本地 Git Bash 中运行，沙箱环境无法联网）
#
# 用法 A（用个人访问令牌 PAT，推荐）：
#   GITHUB_TOKEN=ghp_xxxx GITHUB_USER=keke1023 bash push.sh
#
# 用法 B（已 gh auth login 后）：
#   GITHUB_USE_GH=1 bash push.sh
#
# 推送完成后到 Actions 页面 Run workflow：
#   https://github.com/keke1023/msg1500-padavanonly/actions
set -euo pipefail
cd "$(dirname "$0")"

REPO="keke1023/msg1500-padavanonly"
REMOTE="https://github.com/${REPO}.git"

# 用法 B：优先走 gh（自动处理鉴权与仓库创建）
if [ -n "${GITHUB_USE_GH:-}" ] && command -v gh >/dev/null 2>&1; then
  echo "[*] 使用 gh 推送"
  gh repo create "$REPO" --public \
    --description "MSG1500 X.00 自动编译 (padavanonly/immortalwrt)" 2>/dev/null || true
  git init -q 2>/dev/null || true
  git remote remove origin 2>/dev/null || true
  git remote add origin "$REMOTE"
  git add -A
  git commit -m "feat: MSG1500 X.00 自动编译项目 (padavanonly/immortalwrt)" || echo "（无新提交）"
  git branch -M master
  git push -u origin master
  echo "[+] 完成 -> https://github.com/${REPO}/actions"
  exit 0
fi

# 用法 A：用 PAT 拼接鉴权 URL
TOKEN="${GITHUB_TOKEN:?请设置环境变量 GITHUB_TOKEN（个人访问令牌，需 repo 权限）}"
USER="${GITHUB_USER:-keke1023}"
AUTH_REMOTE="https://${USER}:${TOKEN}@github.com/${REPO}.git"

echo "[*] 用 PAT 推送（用户：${USER}）"
git init -q 2>/dev/null || true
git remote remove origin 2>/dev/null || true
git remote add origin "$AUTH_REMOTE"

git add -A
git commit -m "feat: MSG1500 X.00 自动编译项目 (padavanonly/immortalwrt)" || echo "（无新提交）"
git branch -M master
git push -u origin master

# 推送成功后清掉带凭据的 remote，避免令牌残留在 .git/config
git remote set-url origin "$REMOTE"
echo "[+] 完成 -> https://github.com/${REPO}/actions"
