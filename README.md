# freellmapi-fnos

FreeLLMAPI 的飞牛 OS（fnOS）原生应用打包仓库，参照 deepseek.harness.fnos / fnos-hermes-agent-web 的维护模式。

- 上游：https://github.com/tashfeenahmed/freellmapi （本仓库是它的 fork；克隆在 `upstream/`，已 gitignore）
- 版本号规则：`上游版本.构建号`（见 `VERSION`），当前 0.16.2.1

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
