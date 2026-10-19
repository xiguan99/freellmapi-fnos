#!/bin/bash
# freellmapi-fnos 自动同步上游构建脚本（方案 B：NAS 端）
# 流程: 查上游最新 tag → 检出 → 重放 CSP 补丁 → 测试门禁 → 构建 → 发布 → 维护树提交推送 → 备份 → 飞书
# 无事可做时静默退出（不推飞书）；发布成功或失败才推。可 crontab 每日跑，也可手动执行。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[ -f "$ROOT/scripts/.secrets.env" ] && . "$ROOT/scripts/.secrets.env"   # cron 环境无 DSH secrets
export PATH="/var/apps/nodejs_v24/target/bin:$PATH"                       # cron 环境无 node/npm
CLONE="/vol1/1000/work/deepseek/src/upstream-full/freellmapi"   # 上游完整克隆（走 gh-proxy 只读）
PERSIST="/vol1/1000/work/deepseek/fnos-apps/freellmapi"          # 持久副本
FEISHU="/vol1/@appdata/deepseek.harness/dsh-data/skills/feishu-push/send.mjs"
PUSH_URL="https://xiguan99:${DSH_SECRET_GITHUB_PAT_PUSH:-$GITHUB_TOKEN}@github.com/xiguan99/freellmapi-fnos.git"
TOKEN="${DSH_SECRET_GITHUB_PAT_PUSH:-$GITHUB_TOKEN}"
MARKER="$ROOT/scripts/.last-synced-tag"
LOCK="$ROOT/scripts/.sync.lock"
export GITHUB_TOKEN="$TOKEN"

# 单例锁（cron 与手动互斥）
exec 9>"$LOCK"
flock -n 9 || { echo "另一个同步在跑，退出"; exit 0; }

notify() { node "$FEISHU" --text "$1" >/dev/null 2>&1 || true; }
fail() { echo "❌ $1"; notify "❌ freellmapi 自动同步失败（未发布）：$1
上游最新 tag: ${LATEST:-未取到}
下一步：手动跑 $0 FORCE=1 或人工处理"; exit 1; }

cd "$CLONE"
git fetch --tags --quiet origin || fail "fetch 上游 tag 失败（gh-proxy?）"
LATEST="$(git tag | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1)"
[ -n "$LATEST" ] || fail "取不到上游 tag"
LASTSYNC="$(cat "$MARKER" 2>/dev/null || true)"
if [ "$LATEST" = "$LASTSYNC" ] && [ "${FORCE:-0}" != "1" ]; then
  echo "无新上游版本（最新 $LATEST，已同步）"; exit 0
fi
echo "═══ 同步 $LASTSYNC → $LATEST ═══"

git checkout -q "$LATEST" || fail "checkout $LATEST 失败"

# ── 重放维护补丁（唯一源码补丁：CSP frame-ancestors 环境变量覆盖）──
PATCH="$ROOT/scripts/patches/csp-frame-ancestors.patch"
git apply --check "$PATCH" || fail "补丁应用到 $LATEST 失败（上游动了 app.ts/测试文件），需人工重做补丁"
git apply "$PATCH"

# ── 安装 + 测试门禁 ──
npm ci --no-audit --no-fund --silent || fail "npm ci 失败"
echo "测试门禁: npm test --workspace server ..."
timeout 1200 npm test --workspace server --silent >/tmp/freellmapi-sync-test.log 2>&1 || fail "测试门禁未通过，见 /tmp/freellmapi-sync-test.log 末尾"
tail -3 /tmp/freellmapi-sync-test.log

# ── 版本号 = 上游版本.1（每个上游版本构建号从 1 起）──
UVER="${LATEST#v}"
echo "$UVER.1" > "$ROOT/VERSION"

# ── 构建（npm ci/测试已完成，跳过安装直接 构建→prune→组装→扫描→打包）──
UPSTREAM_DIR="$CLONE" SKIP_INSTALL=1 "$ROOT/scripts/build.sh" || fail "build.sh 失败"

# ── 发布 ──
NOTES="同步上游 $LATEST（自动构建：补丁重放 + 测试门禁通过）。

维护内容（全版本沿革）：
- CSP frame-ancestors 环境变量覆盖（\`FREELLMAPI_FRAME_ANCESTORS\`，打包默认 *）
- node 绝对路径解析、包内断链清理、安装/升级/卸载回调、数据目录方案
- 官方图标 + 署名（开发者 tashfeenahmed / 发布者 xiguan99）"
NOTES="$NOTES" GITHUB_TOKEN="$TOKEN" "$ROOT/scripts/publish.sh" || fail "publish.sh 失败"

# ── 维护树：更新 force-add 文件 + 产物 + marker，提交并推送 ──
cp "$CLONE/server/src/app.ts" "$ROOT/upstream/server/src/app.ts"
cp "$CLONE/server/src/__tests__/routes/csp-security.test.ts" "$ROOT/upstream/server/src/__tests__/routes/csp-security.test.ts"
echo "$LATEST" > "$MARKER"
cd "$ROOT"
git add -f upstream/server/src/app.ts upstream/server/src/__tests__/routes/csp-security.test.ts
git add VERSION scripts/.last-synced-tag
git commit -q -m "sync: 上游 $LATEST（重放 CSP 补丁）→ v${UVER}.1"
ok=0; for i in 1 2 3 4 5; do
  git push "$PUSH_URL" ghmain:main >/dev/null 2>&1 && { ok=1; break; }
  sleep 10
done
[ "$ok" = "1" ] || echo "⚠ GitHub 推送 5 次都失败，提交留本地，稍后手动重推"

# ── 持久副本 + 时间戳备份（保留最近 3 份）──
rsync -a --delete --exclude 'upstream/' --exclude '.git/' --exclude '.bak-*' "$ROOT/" "$PERSIST/"
ts=$(date +%Y%m%d-%H%M%S)
tar czf "$PERSIST/.bak-$ts.tgz" --exclude='upstream' --exclude='.git' --exclude='fnpack/app' -C "$ROOT" .
ls "$PERSIST"/.bak-*.tgz 2>/dev/null | sort | head -n -3 | xargs -r rm --
SHA="$(sha256sum "$ROOT/fnpack/dist/freellmapi_v${UVER}.1_x86.fpk" | cut -c1-16)"

notify "✅ freellmapi 自动同步完成：上游 $LATEST → v${UVER}.1
下载：https://github.com/xiguan99/freellmapi-fnos/releases/download/v${UVER}.1/freellmapi_v${UVER}.1_x86.fpk
sha256 ${SHA}…（测试门禁通过，GitHub 推送 $( [ "$ok" = "1" ] && echo 成功 || echo 未成-需重推 )），持久副本已备份。"
echo "═══ 同步完成 v${UVER}.1 ═══"
