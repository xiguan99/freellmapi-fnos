# freellmapi-fnos

FreeLLMAPI 的飞牛 OS（fnOS）原生应用打包仓库。

- 上游：https://github.com/tashfeenahmed/freellmapi （本仓库是它的 fork；克隆在 `upstream/`，已 gitignore）
- 版本号规则：`上游版本.构建号`（见 `VERSION`），当前 0.16.5.2

## 首次启动（Getting Started）

首次启动需要创建管理员账号：
- **在 NAS 本机的浏览器**打开（http://NAS_IP:3003）可直接完成设置，无需代码。
- 从**其它设备**打开时，需要填一个一次性的「启动代码」（setup code）——它在服务启动日志里，搜 `First-run setup code` 这一行；可在应用中心的应用日志页看，或 `tail ${TRIM_PKGVAR}/info.log`（本实例通常是 `/vol1/@appdata/freellmapi/info.log`）。

## Fork 补丁（唯一源码改动，`upstream/` 内以 `git add -f` 入库）

- `server/src/app.ts`：helmet CSP 新增 `frameAncestors` 覆盖——环境变量 `FREELLMAPI_FRAME_ANCESTORS`（空格分隔的 CSP source 列表）存在时替换默认 `'self'`，未设置时行为与上游完全一致。用途：fnOS 桌面入口是跨端口 iframe，默认 `'self'` 会把页面拦在框架外；打包默认在 cmd/main 里设 `*`（可在 `${TRIM_PKGVAR}/freellmapi.env` 收紧，如 `FREELLMAPI_FRAME_ANCESTORS="'self' http://NAS_IP:5666"`）。
- 对应测试：`server/src/__tests__/routes/csp-security.test.ts` 末尾新增 describe（覆盖生效/默认不两路，20/20 通过）。

## 仓库布局

    VERSION                  # 上游版本.构建号（publish 从此读取）
    scripts/                 # build.sh / publish.sh / fnpack CLI
    upstream/                # 上游克隆（gitignore，构建输入）
    fnpack/                  # 打包树
      manifest               # 应用元数据（appname=freellmapi，端口 3003）
      wizard_install.json    # 安装向导（存储位置 + 运行权限）
      wizard_uninstall.json  # 卸载向导（数据保留选项）
      config/                # privilege / resource(data-share)
      cmd/                   # 生命周期脚本（start/stop/status + 各回调）
      app/                   # 运行时树：ui/ 跟踪；node_modules、server/dist、client/dist 等构建产物不跟踪
      dist/                  # 构建产物 *.fpk（gitignore）

## 构建与发布（在 NAS 上跑）

    scripts/build.sh     # 上游 npm ci/build/prune → 组装 → fnpack 出 fpk
    GITHUB_TOKEN=$DSH_SECRET_GITHUB_PAT_PUSH scripts/publish.sh

## 运行时

- 服务：`node server/dist/index.js`，默认端口 **3003**（env `PORT` 可覆盖）
- 数据：`server/data/` 是指向 `${TRIM_PKGVAR}/data` 的符号链接（应用中心升级不丢数据）
- 环境变量：`.env` 自动从应用根目录读取；`.env` 外的覆盖放 `${TRIM_PKGVAR}/freellmapi.env`（cmd/main 会 source）
- ENCRYPTION_KEY：生产模式必需，cmd/main 首启自动生成到 `${TRIM_PKGVAR}/data/.encryption-key`（实测冒烟确认）
- 日志：`${TRIM_PKGVAR}/info.log`；pid 文件 `${TRIM_PKGVAR}/app.pid`
- 运行依赖：应用中心 `nodejs_v24`（install_dep_apps）
