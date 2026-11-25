# 架构与可靠性

## 进程与组件

```text
auleumd            菜单栏常驻进程（唯一持有 TCC 权限的进程）
  Shield           gamma 输出层纯色；认证时临时恢复 gamma 并使用黑窗
  InputGuard       HID 事件拦截（物理/合成二分）+ 双击/长按 Esc 手势
  PresentationOverlay  展示模式全屏窗口
  CaptureBroker    SCScreenshotManager / SCStream
  AuthGate         Touch ID（默认出口）/ 可选系统密码兜底
  Sentinel         防显示器休眠 / 系统睡眠
  HealthWatchdog   后台 tap/权限检查 + 主线程卡死看门狗
  ScreenSnapshot   用 displayID 锁定屏幕身份，不用数组下标
  ControlServer    unix socket 控制面 + JSONL 审计
auleumctl          瘦客户端，不需要任何权限
```

设计前提：**权限只授予 `auleumd` 一处**。Agent 通过 `auleumctl` 连接本地 socket，自己不持有屏幕录制权限；谁能截、截给谁集中在 broker 里。这条边界只区分用户，不隔离同一用户下的进程。

## 输入策略

- 主事件 tap 挂在 `kCGHIDEventTap`：来源 PID 为 0 的事件按物理输入处理并吞掉，带来源 PID 的合成事件放行。不维护进程名单。
- 另一个 session tap 拦截 Mission Control、Space 切换、Dock control 等系统手势，避免滑动时露出桌面。
- 物理键盘、鼠标、滚轮、平板事件在幕帘期间全部被拦截；合成点击和键盘仍可送达应用，Agent 的操作路径不受影响。
- 退出入口做在事件 tap 内部，因为幕帘期间菜单点不到。双击 Esc、长按 Esc、全局快捷键、`auleumctl off` 都进入同一个验证流程。
- 默认认证界面是幕帘内的自定义 Touch ID 卡片：Apple 的 `LAAuthenticationView` 把指纹图标和验证状态画在卡片窗口（层级 102），不再弹系统认证面板；覆盖层降到 Dock（20）和菜单栏（24）之上（101），全屏遮挡仍在。认证失败或取消后回到幕帘。
- 可选密码兜底默认关闭。开启后，Touch ID 不可用（无硬件、被锁定或暂时不可用）或验证失败时改用 `LAContext.evaluatePolicy(.deviceOwnerAuthentication)` 的系统密码面板；用户按 Esc 取消不会触发回退。密码由 `coreautha` 处理，Auleum 不接触明文。面板期间物理键鼠放行给系统，合成键鼠仍被拦截，系统手势继续拦截，Esc 取消认证；鼠标指针临时显示。
- 起幕前检查可用验证方式：有 Touch ID，或开启密码兜底且系统验证可用；两者都没有时拒绝起幕，避免开启后无法正常退出。
- 权限撤销、tap 失效、覆盖窗口创建失败和睡眠都保持幕帘：记录降级、持续重试，恢复后自动补涂。只有 Touch ID/密码验证、`panic` 或进程退出会真正撤幕。
- **降级可观测**：`status` 返回 `degraded` / `degraded_reason`，`doctor` 在降级时列出原因，菜单栏提示和状态面板的「保护降级」卡片也带上最近一次失败原因；恢复后清空。
- **配置损坏保护**：字段级解码容错，单个字段类型错误只回退该字段；整份文件无法解析时不静默重置，而是先把原文件复制为 `config.corrupt-<时间戳>.json`（0600），再用默认配置继续运行；`status` / `doctor` 和审计 `config_load_failed` 都会报告备份位置。
- **诊断线程边界**：`doctor` 在控制面队列上执行耗时检查，但配置、快捷键和电源状态先在主线程快照；避免跨线程读取 AppKit 状态。
- 锁屏/切换用户时先移除覆盖层，让系统登录界面可见；幕帘状态不撤销，`sessionDidBecomeActive` 后重建并补涂。锁屏期间桌面由 loginwindow 遮挡。
- 严格出口意味着输入 tap 失效时画面仍被遮挡，但物理键鼠可能已经不被拦截；这是为避免“未验证就露出桌面”而接受的取舍。

## 显示与采集

### 输出层幕帘

把每块屏的 gamma 表写成统一纯色。gamma 作用于显示输出，不改变 framebuffer，因此本机截图、录屏和远程读取 framebuffer 的采集仍然得到真实桌面。

- 启动、睡眠唤醒、显示器重配后持续补涂；补涂失败只上报降级，幕帘状态保持并重试。
- 按显示器实际采样点数保存/恢复原 gamma（本机为 1024 点），避免撤幕后色偏。
- gamma 没有空间信息，所以不能显示文字、图标或图片。

### 展示模式

用 `sharingType = .none` 的 `CGShieldingWindowLevel` 全屏窗口显示背景、时钟和场景提示。

- 常规 ScreenCaptureKit 截图/录屏尊重窗口共享排除，画面中不含展示窗口。
- HDMI、采集卡、私有采集 API 不受此保证，它们看到的是背景和时钟。
- 每块屏可以独立选择 `black` 或 `presentation`；混合角色变化时先给新增黑屏补 gamma，再移除不再需要的展示窗口，避免露出一帧桌面。
- 自由版式把时钟卡片、提示和返回时间拆成三个画布子视图，位置按屏幕比例归一化保存；拖拽只在设置预览里开启，真实幕帘和全屏试看不接收编辑手势。
- 纯色幕布会隐藏为图片准备的明暗渐变，并按幕布相对亮度在深色/浅色文字与铜色强调之间切换；组件底板由 `auto` / `glass` / `clear` 决定，分辨率不依赖屏幕像素。
- 展示窗口和 gamma 黑幕共用同一个验证出口与输入拦截。
- 展示模式支持 `auleumctl message` 动态进度消息：单行、最多 200 字，折叠空白和控制字符；起幕/撤幕清空，回落到场景提示。gamma 幕帘无法显示文字，命令会返回 `visible: no`。

## 可靠性设计

- **单实例**：`flock` 守门，第二个实例发现已有健康实例就静默退出；LaunchAgent 的 `RunAtLoad` 也走这条路。
- **开机自启**：LaunchAgent + `KeepAlive`，进程被杀会被 launchd 拉起；`doctor` 显示加载状态，设置页可以直接安装或移除。
- **录制抗崩溃**：`movieFragmentInterval = 2s`，进程被强杀后 mp4 仍可播放。
- **审计完整性**：每条记录带 `prev` 与 `hash`，`auleumctl audit --verify` 能定位中途修改或删除。它不是密码学防篡改，不能防同用户重写整份文件或截断末尾。`auleumctl audit` 只读日志尾部最多 8 MB，避免长日志整份载入内存。
- **稳定屏幕身份**：gamma 黑幕、认证窗口、截图和录屏都按 `CGDirectDisplayID` 定位，热插拔/重排不会把第 0 块屏指向另一块屏。
- **采集透明**：启动、睡眠唤醒和显示器重配后持续补涂 gamma；补涂失败不会偷偷换成普通黑窗，也不会自动撤幕，而是保持遮挡、记录降级并重试。
- **崩溃自恢复**：gamma 属于当前进程，Auleum 退出/崩溃时 macOS 会自动恢复；正常撤幕还会用启动前保存的 gamma 表主动恢复。
- **输入失效保护**：后台 watchdog 每 500ms 检查主 tap、手势 tap 和两项权限；任一失效都保持幕帘，记录降级并持续重试，不会自动撤幕。
- **反复失效熔断**：tap 在 10 秒内被系统禁用并重试 5 次仍不稳定时，按降级处理并保持幕帘；稳定 30 秒后清除熔断状态。
- **权限撤销保护**：幕帘期间撤销录屏或设备控制权限不会自动撤幕；保持遮挡，权限恢复后自动重挂 tap 并补涂。
- **空闲输入来源**：自动起幕读取 `IOHIDSystem.HIDIdleTime`，只把真实 HID 操作视为“有人在用”，Agent 合成事件不会让空闲阈值永远达不到。
- **主线程故障保护**：主线程连续 8 秒没有心跳时，后台 watchdog 结束进程，让 macOS 恢复 gamma 和物理输入；已安装 LaunchAgent 时会自动拉起。
- **分辨率**：截图/录屏按 `backingScaleFactor` 还原真实像素。

## 更新

更新由 `UpdateController` 在 `auleumd` 内完成，不引入 Sparkle 或第三方框架：

- 启动后 8 秒和之后每 6 小时请求 `api.github.com/repos/NotoChen/Auleum/releases/latest`；User-Agent 只带当前版本号，使用 ephemeral URLSession，不读取浏览器 Cookie 或缓存。
- 选择 `Auleum-<version>.zip`，下载 Release 提供的 SHA-256 清单并校验 zip；解压后校验 `CFBundleIdentifier`、`CFBundleShortVersionString` 和 `codesign --verify --deep --strict`。
- 安装脚本在 support 目录生成，等待当前进程退出后把旧 `Auleum.app` 移到备份路径、复制新包、删除 quarantine、再次校验签名并 `open`。新进程在 10 秒内没有出现时自动回滚旧包。
- 自动安装只在幕帘关闭、没有认证、没有录制、没有全屏试看时进行；否则更新保持「已就绪」，等 `turnOff` 或 `recordStop` 后继续。
- 更新检查失败不会取消幕帘或影响控制面；`status` / `doctor` 暴露 `update_phase`、`update_latest` 和自动更新开关。
- ad-hoc 签名没有发布者身份，SHA-256 是从 GitHub Release 到本地安装的信任锚点；它不能防 GitHub 账号被攻破。

## 与相关项目

这个方向已有先行者，但没有一个开源成品同时满足「人看不到、Agent 的 framebuffer 采集仍然透明、Touch ID 是默认出口（密码兜底默认关闭）」：

- [Lockpaw](https://github.com/sorkila/lockpaw)：覆盖层、agent hook、Touch ID/密码 fallback、合盖模式和签名分发更完整；它的锁屏是可被采集到的 overlay，Agent 提示光效也会进入画面。Auleum 学习它的热键、可靠性和分发设计，但不接 agent hook，也不复制可见覆盖层和 root helper；密码 fallback 只作为默认关闭的可选项。
- [acamarata/curtain](https://github.com/acamarata/curtain)：面向 macOS Screen Sharing 的物理/远程输入分流，重点是远程会话，不是本机 Agent 的截图透明性。
- [iwaller/curtain](https://github.com/iwaller/curtain)：同样使用 gamma 输出层和 Touch ID，验证记录扎实；它有密码 fallback、系统锁屏恢复和更重的 watchdog 结构。Auleum 采用它的显示重配置和失败保护经验，密码 fallback 默认关闭且只在 Touch ID 不可用时启用。

可复用的是策略和实现经验，不是把现有 app 改个名字。
