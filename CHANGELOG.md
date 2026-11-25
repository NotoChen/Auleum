# Changelog

本项目使用语义化版本号。0.x 版本仍可能调整配置字段和界面结构。

## 0.0.1 — 2026-11-25

首个公开版本。仓库名称统一为 `Auleum`；此前没有公开 release，也没有保留旧版本号或 CI 配置。

### 核心能力

- 幕帘默认使用展示窗口（幕帘底色 + 数字时钟），可切换为输出层 gamma 纯色幕帘；普通 ScreenCaptureKit 采集仍能看到真实桌面。
- 设备控制和数据访问权限 + 录屏权限；Touch ID 是默认正常出口。
- 可选密码验证兜底（默认关闭）：没有可用 Touch ID 或指纹验证失败时改用系统密码面板，密码由 macOS 处理；面板期间物理键鼠放行给系统，合成输入仍被拦截。开启后没有 Touch ID 的 Mac 也能起幕。菜单栏和状态面板会按当前方式显示「等待 Touch ID」或「等待密码验证」。
- 起幕前检查可用验证方式；既没有 Touch ID、也没有开启密码兜底时拒绝起幕，避免开启后无法正常退出。
- 认证期间覆盖层留在 Dock/菜单栏之上、系统 Touch ID 面板之下，验证前不会露出 Dock 或菜单栏。
- 撤幕认证改为幕帘内的自定义 Touch ID 卡片（`LAAuthenticationView`），不再弹系统认证面板；指纹比对仍由系统完成，卡片居中显示，Esc 取消。
- 双击 Esc、长按 Esc、全局快捷键和 `auleumctl off` 都进入同一认证流程。
- 撤幕审计记录请求来源；Touch ID 不可用时普通出口保持幕帘，只有 `panic` / 结束进程可应急撤幕。
- 失败路径严格保持幕帘：输入 tap 失效、权限撤销、系统睡眠、展示窗口或 gamma 覆盖失败都不再自动撤幕，而是记录降级并重试；锁屏/切换用户时临时让出登录界面，解锁后重建；`safetyTimeoutSeconds` 也改为发起 Touch ID。只有 Touch ID、`panic` 或进程退出会撤幕。
- 降级可观测：`status` 返回 `degraded` / `degraded_reason`，`doctor` 在降级时列出最近原因，菜单栏提示和状态面板同步显示；恢复后自动清空。
- 设置页新增「开机自启」开关，效果等同 `auleumctl install-agent` / `uninstall-agent`；变更写入 `launch_agent_changed` 审计，失败时保留窗口并提示原因。
- 认证失败或取消后，展示模式会短暂提示「Touch ID / 密码未通过 · 再按 Esc 重试」或「已取消验证 · 幕帘保持」，不会静默回到时钟。
- 配置损坏不再静默重置：原文件自动备份为 `config.corrupt-<时间戳>.json`，默认配置继续运行，`status` / `doctor` 与审计记录报告备份位置。
- 内置更新检查与自动升级：启动后和每 6 小时检查 GitHub Releases；下载 zip 后校验 SHA-256、Bundle ID、版本和代码签名，幕帘关闭且未录制时安装并重启。设置页和状态面板都可手动检查。
- 物理输入拦截、系统手势拦截、失效保持幕帘和主线程看门狗。
- 截图、录屏、区域截图、多屏截图和审计哈希链。

### 自动化与展示

- 空闲自动起幕、每日定时保护、跨午夜和按星期保护时段。
- 保护时长倒计时；到时只发起验证（默认 Touch ID），不直接露出桌面。
- 主屏/副屏可分别选择 gamma 黑幕或展示窗口。
- 展示模式默认开启：居中卡片、右下角、极简、自由四种版式，内置深色渐变默认背景，自定义背景、焦点、缩放、暗化，数字/表盘/日历时钟，以及秒、农历、计时组件的独立开关；关闭后使用 gamma 输出层幕帘。
- 自由版式可在设置预览中直接拖动时钟卡片、场景提示和预计返回时间，位置按屏幕宽高归一化保存，多屏一致。
- `auleumctl message` 可在不撤幕的情况下更新展示模式上的单行进度消息，最多 200 字；起幕/撤幕自动清除，审计只记录长度和是否可见。
- 展示组件底板可选自动、玻璃或透明；纯色幕布按亮度切换深/浅文字和铜色强调，不再叠加为图片准备的明暗渐变。
- 离开、会议、访客、专注四个完整场景配置包。
- 四个场景独立全局快捷键，默认 `⌃⌥⌘1`–`⌃⌥⌘4`，可在设置页录制。
- `auleumctl protect`、`auleumctl scene` 和 `auleum://` URL 控制。
- 设置窗口按屏幕自适应，支持未保存状态、快捷键和关闭确认。

### 命名与分发

- 应用、命令行、Bundle ID 和配置目录统一为 Auleum：`Auleum.app`、`auleumd`、`auleumctl`、`AuleumKit`、`io.github.notochen.auleum`、`~/Library/Application Support/Auleum`。
- GitHub 仓库名统一为 `NotoChen/Auleum`；移除无实际发布作用的 CI workflow，由本地 `Scripts/test.sh` 和 `Scripts/package_release.sh` 完成验证与打包。
- 配置字段和状态 JSON 使用 `veil` 作为「幕帘」的英文名，例如 `veilColor`、`"veil": "off"`。
- 不保留旧名称的配置迁移、URL scheme、环境变量或命令兼容入口。
- 首个公开版本为 0.0.1，提供 zip、DMG 和 SHA-256 校验文件；`./Scripts/test.sh` 为 **89 tests / 16 suites** 全通过。

### 已知边界

- 当前使用 ad-hoc 签名，没有 Apple Developer ID 公证。首次打开需要右键应用并选择「打开」。
- 重装或重新构建后，macOS 可能要求重新确认两项隐私权限。
- 展示模式只保证常规 ScreenCaptureKit 路径不采集窗口；HDMI、采集卡和私有采集 API 不保证。
- 真实合盖行为仍取决于 macOS 电源策略和外接屏配置。
- 目标系统为 macOS 14+；公开验证主要来自 Apple Silicon 和当前 macOS 版本。

完整验证记录见 [README](README.md)。
