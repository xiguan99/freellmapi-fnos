#!/bin/bash
# freellmapi-fnos 构建脚本（参照 deepseek.harness.fnos / fnos-hermes-agent-web 版式）
# 流程: 上游 npm ci -> 全量构建 -> prune 生产依赖 -> 组装 fnpack/app 运行时树 -> fnpack 出 .fpk
# 运行环境: NAS 本机（native 模块 better-sqlite3 就地编译，天然对 x86_64 Linux + node24）
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

UPSTREAM="${UPSTREAM_DIR:-$ROOT/upstream}"
FP_BIN="$ROOT/scripts/fnpack-1.2.3-linux-amd64"
# 版本号 = 上游版本.构建号（上游版本来自 desktop/package.json）
UP_VER="$(node -e "console.log(require('$UPSTREAM/desktop/package.json').version)")"
BUILD_NUM="$(cat "$ROOT/VERSION" | tr -d '[:space:]' | rev | cut -d. -f1 | rev)"
VERSION="${UP_VER}.${BUILD_NUM}"
[ -f "$ROOT/VERSION" ] && echo "$VERSION" > "$ROOT/VERSION"
echo "═══ 构建 freellmapi v$VERSION ═══"

# ── 上游安装与构建（可增量：设 SKIP_INSTALL=1 跳过 npm ci，设 SKIP_BUILD=1 跳过构建）──
if [ "${SKIP_INSTALL:-0}" != "1" ]; then
  echo "[1/5] npm ci ..."
  ( cd "$UPSTREAM" && npm ci --no-audit --no-fund )
fi
if [ "${SKIP_BUILD:-0}" != "1" ]; then
  echo "[2/5] 构建 server+cli+client ..."
  ( cd "$UPSTREAM" && npm run build )
fi

echo "[3/5] 生产依赖剪枝（保留 native 模块）..."
( cd "$UPSTREAM" && npm prune --omit=dev )

echo "[4/5] 组装运行时树 fnpack/app ..."
APP="$ROOT/fnpack/app"
for item in node_modules server client shared desktop package.json package-lock.json; do rm -rf "${APP:?}/$item"; done
cp "$UPSTREAM/package.json" "$UPSTREAM/package-lock.json" "$APP/"
cp -a "$UPSTREAM/node_modules" "$APP/node_modules"
mkdir -p "$APP/server" "$APP/client" "$APP/desktop" "$APP/shared"
cp -a "$UPSTREAM/server/node_modules" "$APP/server/node_modules" 2>/dev/null || true
cp "$UPSTREAM/server/package.json" "$APP/server/"
cp -a "$UPSTREAM/server/dist" "$APP/server/dist"
cp -a "$UPSTREAM/client/dist" "$APP/client/dist"
cp -a "$UPSTREAM/shared/." "$APP/shared/" 2>/dev/null || true
cp "$UPSTREAM/desktop/package.json" "$APP/desktop/package.json"
mkdir -p "$APP/server/data"
# 断链清理：安装器设目录权限会遍历全树 acl_get_file，断链直接导致「设置目录权限失败」(errno 实测)
n=$(find "$APP" -xtype l | wc -l); [ "$n" -gt 0 ] && { find "$APP" -xtype l -delete; echo "  清理断链 $n 个"; }

echo "[x] 隐私扫描 ..."
# 注：sk- 阈值 20+（实测客户端 bundle 里斯洛伐克语 chunk 名 sk-XXXXXXXX 会撞 8 位阈值，误报过一次）
if grep -rIl -e '/vol[0-9]\+/@app\(home\|data\)/' -e 'sk-[A-Za-z0-9]\{20,\}' -e 'token=[A-Za-z0-9]' "$APP" --exclude-dir=node_modules 2>/dev/null | grep -v '\.map$' | head -5 | grep -q .; then
  echo "✗ 疑似泄漏本机路径/密钥，中止（自行 grep 处理）"; exit 1
fi

# 图标与脚本权限（fnOS 应用中心以组身份读取 ICON.PNG，组无读权限会静默退回默认占位图）
chmod 644 "$ROOT/fnpack/ICON.PNG" "$ROOT/fnpack/ICON_256.PNG"
find "$ROOT/fnpack/cmd" -type f -name '*' -exec chmod 755 {} \; 2>/dev/null || true

echo "[5/5] fnpack 打包 ..."
# 更新 manifest / ui config 里的版本
sed -i "s/^version .*=.*/version               = $VERSION/" "$ROOT/fnpack/manifest"
cd "$ROOT/fnpack"
"$FP_BIN" build
mv -f freellmapi.fpk "$ROOT/fnpack/dist/freellmapi_v${VERSION}_x86.fpk"
ls -la dist/ 2>/dev/null || ls -la *.fpk 2>/dev/null || true
# ── 出包后硬断言：图标必须 644（否则应用中心显示占位图）──
CHK="$(mktemp -d)"
tar -xzf "$ROOT/fnpack/dist/freellmapi_v${VERSION}_x86.fpk" -C "$CHK" ICON.PNG ICON_256.PNG || true
for ic in ICON.PNG ICON_256.PNG; do
  m=$(stat -c%a "$CHK/$ic" 2>/dev/null || echo missing)
  [ "$m" = "644" ] || { echo "✗ $ic 权限=$m（必须 644，否则应用中心显示占位图）"; rm -rf "$CHK"; exit 1; }
done
rm -rf "$CHK"
echo "  ✓ 图标权限 644 断言通过"
echo "═══ 完成：产物见 fnpack/ 或 dist/ ═══"
