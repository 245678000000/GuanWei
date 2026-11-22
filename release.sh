#!/bin/zsh
# 发布新版本：./release.sh 1.1.0 "更新说明"
set -e
cd "$(dirname "$0")"
VER="${1:?用法: ./release.sh <版本号> [更新说明]}"
NOTES="${2:-观微 v$VER}"
echo "$VER" > VERSION
./build.sh
git add VERSION
git commit -m "发布 v$VER" || true
git tag "v$VER"
git push && git push origin "v$VER"
gh release create "v$VER" "build/GuanWei-$VER.zip" --title "观微 v$VER" --notes "$NOTES"
