#!/bin/bash
# freellmapi-fnos 发布脚本（GitHub API 版，照 fnos-hermes-agent-web）
# 创建 Release 并上传 dist/*.fpk。依赖：GITHUB_TOKEN 环境变量
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
REPO="${GITHUB_REPOSITORY:-xiguan99/freellmapi-fnos}"
GITHUB_TOKEN="${GITHUB_TOKEN:?需要设置 GITHUB_TOKEN 环境变量}"
CUR_VERSION="$(cat VERSION | tr -d '[:space:]')"
TAG="v$CUR_VERSION"
DIST="${DIST_DIR:-$ROOT/fnpack/dist}"
# ── 同步提醒 ────────────────────────────────────────────────
# 下面这段“从 manifest 派生应用名/标题”的逻辑，另外两个仓库里也有同一份：
#   xiguan99/strata-fnos/scripts/publish.sh
#   xiguan99/qwenpaw-fnos/scripts/publish.sh
# 三处内容必须一致，改就三处一起改（不抽公共脚本/submodule：8 行 sed 不值得多一层维护，
# 同步靠这条注释 + 台账 checklist）。
# ───────────────────────────────────────────────────────────
# 应用名/显示名从 manifest 读，不硬编码
# （2026-10-25：strata 的 publish.sh 照抄 qwenpaw 版，把 Release 标题硬编码成 "QwenPaw …" 没改）
MANIFEST="$ROOT/fnpack/manifest"
APPNAME="$(sed -n 's/^appname[[:space:]]*=[[:space:]]*//p' "$MANIFEST" | head -1 | tr -d '[:space:]')"
DISPLAY_NAME="$(sed -n 's/^display_name[[:space:]]*=[[:space:]]*//p' "$MANIFEST" | head -1 | sed 's/[[:space:]]*$//')"
if [ -z "$APPNAME" ] || [ -z "$DISPLAY_NAME" ]; then
  echo "✗ 读不到 $MANIFEST 的 appname/display_name，拒绝创建标题不明的 Release"
  exit 1
fi
# 标题格式沿用本仓库历史（"freellmapi 0.16.9.1"，小写、不带 v），只为去掉硬编码
RELEASE_TITLE="${RELEASE_TITLE:-$APPNAME $CUR_VERSION}"
echo "  应用=$APPNAME 显示名=$DISPLAY_NAME 标题=$RELEASE_TITLE"
echo "═══ 发布 $CUR_VERSION 到 $REPO ═══"
[ -d "$DIST" ] && [ -n "$(ls "$DIST"/*.fpk 2>/dev/null)" ] || { echo "✗ $DIST 无 fpk，先跑 scripts/build.sh"; exit 1; }

EXISTING_ID="$(curl -sS -H "Authorization: token $GITHUB_TOKEN" "https://api.github.com/repos/$REPO/releases/tags/$TAG" 2>/dev/null | grep -m1 '"id"' | grep -oE '[0-9]+' || true)"
if [ -n "$EXISTING_ID" ]; then
  echo "Release 已存在（id=$EXISTING_ID），删除重建"
  curl -sS -X DELETE -H "Authorization: token $GITHUB_TOKEN" "https://api.github.com/repos/$REPO/releases/$EXISTING_ID" >/dev/null 2>&1 || true
fi

NOTES_DEFAULT="## ${APPNAME}-fnos $CUR_VERSION"$'\n\n'"上游版本 $(echo "$CUR_VERSION" | cut -d. -f1-3)，fnOS 原生打包。"
BODY_JSON="$(python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "${NOTES:-$NOTES_DEFAULT}")"
RELEASE_JSON="$(curl -sS -X POST -H "Authorization: token $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" -H "Content-Type: application/json" "https://api.github.com/repos/$REPO/releases" -d "{\"tag_name\":\"$TAG\",\"name\":\"$RELEASE_TITLE\",\"body\":$BODY_JSON,\"draft\":false,\"prerelease\":false}")"
RELEASE_ID="$(echo "$RELEASE_JSON" | grep -m1 '"id"' | grep -oE '[0-9]+')"
[ -n "$RELEASE_ID" ] || { echo "✗ 创建 Release 失败: $RELEASE_JSON"; exit 1; }
for f in "$DIST/freellmapi_v${CUR_VERSION}_x86.fpk" $( [ -e "$DIST/freellmapi_v${CUR_VERSION}_x86.fpk" ] || ls "$DIST"/*.fpk 2>/dev/null ); do
  echo "上传 $(basename "$f") ..."
  UP="$(curl -sS -X POST -H "Authorization: token $GITHUB_TOKEN" -H "Content-Type: application/octet-stream" "https://uploads.github.com/repos/$REPO/releases/$RELEASE_ID/assets?name=$(basename "$f")" --data-binary @"$f")"
  echo "$UP" | grep -q '"id"' && echo "  ✓ $(echo "$UP" | grep -m1 '"browser_download_url"' || true)" || { echo "  ✗ $UP"; exit 1; }
done
echo "═══ 发布完成: https://github.com/$REPO/releases/tag/$TAG ═══"
