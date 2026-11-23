#!/bin/sh
# QuietSnap 一键推送脚本（在设备上以 root 运行）
# Token 只在本机使用，脚本结束后会从 remote URL 中移除。
set -eu

cd "$(dirname "$0")/.."

printf 'GitHub 用户名: '
read -r GH_USER
[ -n "$GH_USER" ] || { echo "用户名不能为空"; exit 1; }

printf '仓库名（默认 QuietSnap）: '
read -r GH_REPO
[ -n "$GH_REPO" ] || GH_REPO="QuietSnap"

printf 'Token（输入不显示）: '
stty -echo 2>/dev/null || true
read -r GH_TOKEN
stty echo 2>/dev/null || true
printf '\n'
[ -n "$GH_TOKEN" ] || { echo "Token 不能为空"; exit 1; }

echo "== 1. 尝试创建仓库（已存在则跳过） =="
if command -v python3 >/dev/null 2>&1; then
    REPO_NAME="$GH_REPO" GH_USER="$GH_USER" GH_TOKEN="$GH_TOKEN" python3 - <<'PY' || true
import json, os, urllib.request, urllib.error
user = os.environ["GH_USER"]; repo = os.environ["REPO_NAME"]; token = os.environ["GH_TOKEN"]
req = urllib.request.Request(
    "https://api.github.com/user/repos",
    data=json.dumps({"name": repo, "private": True}).encode(),
    headers={"Authorization": "token " + token,
             "Accept": "application/vnd.github+json",
             "User-Agent": "QuietSnap-push"})
try:
    with urllib.request.urlopen(req, timeout=30) as r:
        print("created:", json.load(r).get("html_url"))
except urllib.error.HTTPError as e:
    print("create skipped:", e.code)
except Exception as e:
    print("create skipped:", e)
PY
else
    echo "无 python3，跳过自动创建；请先在浏览器建好仓库 $GH_REPO"
fi

echo "== 2. 初始化并提交 =="
git config --global user.name "$GH_USER"
git config --global user.email "${GH_USER}@users.noreply.github.com"
git init
git add -A
git commit -m "QuietSnap init" || echo "没有新改动，继续推送"
git branch -M main 2>/dev/null || true

echo "== 3. 推送 =="
git remote remove origin 2>/dev/null || true
git remote add origin "https://${GH_USER}:${GH_TOKEN}@github.com/${GH_USER}/${GH_REPO}.git"
git push -u origin main

echo "== 4. 清理 remote 中的 token =="
git remote set-url origin "https://github.com/${GH_USER}/${GH_REPO}.git"

echo
echo "完成。打开查看构建："
echo "https://github.com/${GH_USER}/${GH_REPO}/actions"
