# Auleum 0.0.1

Auleum（幕帘）是一个 macOS 菜单栏可见性开关：它用输出层 gamma 纯色或展示窗口盖住显示器，拦下物理键鼠，但让拥有录屏权限的 Agent 继续通过 ScreenCaptureKit 截图、录屏和合成输入。

这不是锁屏。系统锁屏会把会话切到 loginwindow，第三方采集会失效；Auleum 是在解锁会话里的遮挡层，所以 Agent 才能继续工作。

## 下载

- `Auleum-0.0.1.dmg`：推荐安装包。
- `Auleum-0.0.1.zip`：应用压缩包。
- `*.sha256`：对应单个产物的 SHA-256。
- `Auleum-0.0.1.SHA256SUMS`：zip 与 DMG 的合并校验清单。

要求 macOS 14 或更高版本。当前使用 ad-hoc 签名，没有 Apple Developer ID 公证。

## 首次打开

首次打开可能在 Gatekeeper 处被拦截，二选一：

1. 在 Finder 中右键 `Auleum.app`，选择「打开」。
2. 放入 `/Applications` 后执行：

```bash
xattr -dr com.apple.quarantine /Applications/Auleum.app
```

首次启动后，在「系统设置 → 隐私与安全性」完成两项授权：

- **录屏与系统录音**：截图和录屏。
- **设备控制和数据访问**：事件拦截；旧版 macOS 在「辅助功能」中授权。

两项权限都变绿后，权限浮窗会自动收起。重装或重新构建后，ad-hoc 代码身份会变化，macOS 可能再次要求确认权限。

## 这个版本包含

### 遮挡与采集

- 展示模式默认开启：内置深色渐变、数字时钟和场景提示；支持居中卡片、右下角、极简和自由版式，自由版式可拖动时钟、提示和返回时间。
- 数字、表盘、日历三种时钟；秒、农历、已保护计时可以分别关闭。
- 背景图支持焦点、缩放、暗化和全屏试看；组件底板可选自动、玻璃或透明。
- 输出层 gamma 纯色幕帘：不改变 framebuffer，本机截图、录屏和远程采集仍能得到真实桌面。
- 主屏和副屏可以分别选择展示窗口或 gamma 黑幕；混合角色切换时先遮后换。
- 常规 ScreenCaptureKit 采集不会包含展示窗口；HDMI、采集卡和私有采集 API 不在保证范围内。

### 输入与出口

- 按事件来源区分物理和合成输入：物理键鼠、滚轮、触控板和系统手势被拦截，Agent 的合成点击和键盘正常送达。
- 双击 Esc、长按 Esc、全局快捷键、`auleumctl off` 进入同一个验证流程。
- 默认出口是幕帘内的自定义 Touch ID 卡片，指纹比对由系统完成；不再弹系统认证面板。
- 可选密码兜底（默认关闭）：Touch ID 不可用或验证失败时使用系统密码面板，密码由 macOS 处理，Auleum 不接触明文。
- 认证期间覆盖层留在 Dock 和菜单栏之上、系统认证面板之下，验证前不会露出 Dock 或菜单栏。
- 没有可用验证方式时拒绝起幕，避免开启后无法正常退出。
- 失败路径严格保持幕帘：tap 失效、权限撤销、睡眠、展示窗口或 gamma 失败都保持遮挡、记录降级并重试；锁屏时临时让出系统登录界面，解锁后补涂。
- 只有认证通过、`panic` 或进程退出会撤幕；`panic` 和结束进程是应急出口。

### 自动化与场景

- 离开、会议、访客、专注四个完整场景，分别保存时长、展示方式、背景、时钟、提示文字、预计返回时间和主/副屏角色。
- 四个可配置的场景全局快捷键，默认 `⌃⌥⌘1`–`⌃⌥⌘4`。
- 空闲自动起幕、每日定时保护、按星期保护时段和默认保护时长。
- 保护到点只发起验证，不直接露出桌面。
- `auleumctl message` 可在不撤幕的情况下更新展示模式上的单行进度消息，最多 200 字。

### 控制面与诊断

- 本地 unix socket 控制面，Agent 通过 `auleumctl` 截图、录屏、状态、诊断、审计和 URL 控制。
- 截图/录屏审计记录真实调用方和父进程链。
- 审计日志带 `prev` / `hash` 哈希链，`auleumctl audit --verify` 可定位中途修改或删除。
- `status` 和 `doctor` 报告认证方式、密码兜底、动态消息、降级原因、配置问题、更新状态和 audit 链。
- 配置损坏自动备份为 `config.corrupt-<时间戳>.json`，单个字段类型错误只回退该字段。
- 崩溃自恢复：gamma 属于当前进程，进程退出后 macOS 自动恢复；正常撤幕还会主动恢复原 gamma。
- 单实例、LaunchAgent 开机自启、主线程卡死看门狗和 tap 失效 watchdog。

### 更新

- 启动后 8 秒检查一次 GitHub Releases，此后每 6 小时检查。
- 发现新版本后下载 `Auleum-<version>.zip`，校验 Release 提供的 SHA-256，再校验 Bundle ID、版本号和代码签名。
- 默认自动下载并安装；只有幕帘关闭且未录制时才会替换应用，安装后自动重启。
- 正在保护时更新会保持「已就绪」，撤幕或结束录制后安装。
- 「设置 → 更新」和状态面板都可以手动检查、下载和安装；自动检查可以关闭。
- 更新只从 `https://github.com/NotoChen/Auleum/releases` 获取，不上传设备信息。

### 命令行

```bash
auleumctl on [--minutes N]
auleumctl protect --minutes 30
auleumctl scene away --minutes 120
auleumctl message "正在跑测试"
auleumctl off
auleumctl panic
auleumctl status
auleumctl doctor
auleumctl capture --out shot.png
auleumctl record start --out rec.mp4
auleumctl record stop
auleumctl audit --verify
auleumctl install-agent
auleumctl uninstall-agent
```

## 升级

0.0.1 是第一个公开版本，没有更早的公开版本可升级。之后版本会自动检查、下载并安装；也可以手动安装新版本的 DMG/zip 覆盖 `/Applications/Auleum.app`。更新会改变 ad-hoc 代码身份，可能需要在系统设置里重新确认两项权限。

## 已知限制

- 不是锁屏，也不隔离同一用户下的进程；同用户可以调用 `panic`、结束进程或自行申请 TCC。
- 不是软件安全边界；只区分物理输入和合成输入。
- gamma 改的是显示输出，不是 framebuffer；远程屏幕共享仍可能看到真实桌面。
- 展示窗口对常规 ScreenCaptureKit 采集透明，但 HDMI、采集卡和私有采集 API 不保证。
- 幕布不是半透明遮罩；展示窗口必须不透明。
- 挡不住电源键、长按强关和 USB 设备接入。
- 自动化不会自动解锁；失败不会自动撤幕。
- 审计哈希链能发现中途修改，不能防同一用户重写整份文件或截断末尾。
- ad-hoc 签名和缺少公证意味着首次打开需要手动放行，更新后也可能重新确认权限。
