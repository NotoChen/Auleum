# 配置参考

配置文件：

```text
~/Library/Application Support/Auleum/config.json
```

设置窗口保存时会以 `0600` 权限写入。未知字段会被忽略，非法值会回退到安全默认值；单个字段类型写错只影响该字段。手工编辑后重启 `auleumd` 或重新保存设置即可生效。如果整份文件无法读取或解析，Auleum 会先把原文件备份为同目录下的 `config.corrupt-<时间戳>.json`，再以默认配置启动；`auleumctl status` 的 `config_issue` 和 `doctor` 会给出备份文件名。

## 默认配置

```json
{
  "holdToAuthSeconds": 2,
  "doubleEscapeSeconds": 0.7,
  "safetyTimeoutSeconds": 0,
  "hideCursorDuringVeil": true,
  "allowPasswordFallback": false,
  "veilColor": "#000000",
  "hotkeyKeyCode": 8,
  "hotkeyModifiers": 1835008,
  "sceneHotkeys": {},
  "hasShownOnboarding": false,
  "presentationModeEnabled": true,
  "presentationImagePath": "",
  "presentationVideoPath": "",
  "presentationAmbientStyle": "off",
  "presentationClockStyle": "digital",
  "presentationLayout": "centered",
  "presentationCustomLayout": {
    "clock": { "x": 0.5, "y": 0.5 },
    "message": { "x": 0.5, "y": 0.18 },
    "returnTime": { "x": 0.5, "y": 0.82 }
  },
  "presentationComponentBackground": "auto",
  "presentationDefaultBackdrop": true,
  "presentationShowSeconds": true,
  "presentationShowLunar": true,
  "presentationShowElapsed": true,
  "mainDisplayRole": "presentation",
  "secondaryDisplayRole": "presentation",
  "presentationFocusX": 0.5,
  "presentationFocusY": 0.5,
  "presentationZoom": 1,
  "presentationDim": 0,
  "idleAutoVeilEnabled": false,
  "idleAutoVeilSeconds": 600,
  "scheduleEnabled": false,
  "scheduleStartMinutes": 540,
  "scheduleEndMinutes": 1080,
  "scheduleWeekdays": 127,
  "scheduleAutoExit": false,
  "defaultProtectionMinutes": 0,
  "sceneProfiles": {},
  "clamshellModeEnabled": false,
  "automaticUpdateChecksEnabled": true,
  "automaticUpdateInstallsEnabled": true,
  "remoteCompatibilityEnabled": true,
  "remoteAutoDetectEnabled": true
}
```

## 幕帘与会话

| 字段 | 范围 / 取值 | 说明 |
|---|---|---|
| `holdToAuthSeconds` | 1–5 秒 | 长按 Esc 多久后发起 Touch ID。默认 2。 |
| `doubleEscapeSeconds` | 0.3–1.5 秒 | 双击 Esc 的判定窗口。默认 0.7。 |
| `safetyTimeoutSeconds` | 0–86400 秒 | 开发兜底：到时发起 Touch ID，不直接撤幕。`0` 关闭，默认关闭。 |
| `hideCursorDuringVeil` | 布尔 | 幕帘期间隐藏鼠标指针，不影响 Agent 截图。密码面板显示期间和远程兼容模式下会强制显示指针。 |
| `allowPasswordFallback` | 布尔 | Touch ID 不可用或验证失败时允许系统密码验证。默认 `false`。密码由系统的 `coreautha` 面板处理，Auleum 不接触明文；面板期间物理键鼠放行，合成输入仍被拦截。 |
| `veilColor` | `#RRGGBB` | 展示模式未选择图片且关闭默认背景时使用；关闭展示模式时作为 gamma 输出层纯色。不含透明度。 |
| `defaultProtectionMinutes` | 0–1440 分钟 | 普通起幕的默认倒计时；`0` 表示不限时。到点只发起验证，不自动撤幕。 |
| `clamshellModeEnabled` | 布尔 | 请求屏幕/系统防休眠断言。真实合盖是否继续运行仍由 macOS 电源策略决定。 |

gamma 幕帘不支持图片或文字：gamma 表没有空间信息，任何可见内容都会进入 framebuffer，破坏 Agent 采集透明性。

## 远程兼容

| 字段 | 默认值 | 说明 |
|---|:---:|---|
| `remoteCompatibilityEnabled` | `true` | 幕帘期间放行已知远控进程的输入、显示鼠标指针并放行系统手势；本机物理键鼠仍然拦截。 |
| `remoteAutoDetectEnabled` | `true` | 扫描 `UURemote`、`SunloginClient`、`AnyDesk`、`RustDesk`、`ToDesk`、`TeamViewer`、`Screen Sharing`、`ARDAgent`、Chrome Remote Desktop、VNC、NoMachine、Splashtop、LogMeIn 等进程，检测到时自动进入远程兼容模式。 |

远程兼容模式只改变远控输入的放行方式，不会放行物理键鼠。真实幕帘的展示窗口始终忽略指针事件：物理点击由事件 tap 拦截，远控和 Agent 的合成点击会落到下层应用；只有全屏试看会接住点击，避免误点后面的应用。展示窗口不会成为 key/main 窗口；远控模式下切幕后 Auleum 会主动让出应用焦点，保证远控键盘有前台应用可接收。手动开关可用状态面板的「远程兼容」卡片或命令行：

```bash
auleumctl remote on      # 手动开启
auleumctl remote off     # 手动关闭
auleumctl remote auto    # 清除手动覆盖，回到自动识别
auleumctl remote status  # 查看模式、检测到的工具和 HID SPI 状态
```

只有远程设置本身变化时，保存设置才会清除手动覆盖并重新按配置计算。撤幕方式按来源选择：本机物理输入优先 Touch ID；远控输入发起的撤幕在开启密码兜底且系统验证可用时使用系统密码面板，未开启兜底时保持幕帘并提示；状态面板、定时任务、`auleumctl` 等非输入来源沿用旧规则，在远程模式且开启密码兜底时优先密码。密码面板期间放行已知远控来源和物理键鼠，普通合成输入仍然拦截。

远程模式下，已知远控来源和可识别的虚拟 HID 可以双击 Esc 或按撤幕快捷键发起验证。远控输入触发的撤幕受密码兜底开关限制：只有开启密码兜底才会进入系统密码面板，否则保持幕帘并提示；本机物理输入仍优先 Touch ID。普通合成输入不会触发认证。全局快捷键由 Carbon 注册、拿不到事件来源，按非输入来源处理。

事件来源判定：

- 来源 PID 非 0 且属于已知远控进程：放行。
- 来源 PID 非 0 的其他进程：按合成输入放行（与旧行为一致）。
- 来源 PID 0、HID stateID 为 1、没有软件 userData 标记：物理输入。严格模式拦截；远程模式仍拦截，除非底层 IOHIDEvent 能识别为虚拟 HID 设备。
- 底层设备是虚拟 HID：严格模式拦截；远程模式放行。Karabiner 等重映射设备的虚拟 HID 在两种模式下都拦截。
- 其他 stateID 或 userData 非 0：按合成/远控输入放行。

虚拟 HID 识别使用私有 SPI `CGEventCopyIOHIDEvent` / `IOHIDEventGetSenderID`，失败时按物理输入处理。`auleumctl doctor` 的 `remote_hid_spi` 会显示 SPI 是否可用。

`auleumctl status` 与 `doctor` 会给出幕帘期间的输入计数：`input_physical_blocked`、`input_remote_passed`、`input_virtual_passed`、`input_virtual_blocked`、`input_denied_blocked`。如果远控键盘仍不可用，先看 `remote_tools` 是否识别到工具、`remote_hid_spi` 是否可用，再看 `input_physical_blocked` 是否随按键增长——增长说明该远控事件被当成了物理输入。

## 快捷键

| 字段 | 说明 |
|---|---|
| `hotkeyKeyCode` / `hotkeyModifiers` | 起幕和撤幕共用的全局快捷键。默认 `⌃⌥⌘C`。必须包含 Control、Option 或 Command。 |
| `sceneHotkeys` | 键为场景 rawValue，值为 `{ "keyCode": Int64, "modifiers": UInt64 }`。缺省时使用 `⌃⌥⌘1`–`⌃⌥⌘4`。非法值回退到场景默认快捷键。 |

设置窗口会阻止主快捷键与场景快捷键、以及场景快捷键之间重复。

## 展示模式

| 字段 | 取值 | 说明 |
|---|---|---|
| `presentationModeEnabled` | 布尔 | 默认 `true`。关闭后所有屏幕使用 gamma 幕帘。 |
| `presentationImagePath` | 路径 | 自定义背景图。空字符串时使用默认背景或幕帘底色。 |
| `presentationVideoPath` | 路径 | 循环播放的背景视频。设置后优先于背景图；始终静音。支持常见视频容器（`.mov` / `.mp4` / `.m4v` 等），选择时按文件类型和可播放性校验；起幕时不可读则记录 `presentation_video_unavailable` 并回退到图片或默认背景。 |
| `presentationAmbientStyle` | `off` / `aurora` / `ember` | 内置动态光影：关闭、极光、暖焰。没有图片或视频时生效。非法值回退 `off`。 |
| `presentationClockStyle` | `digital` / `analog` / `editorial` | 数字、表盘、日历三种时钟。非法值回退 `digital`。 |
| `presentationLayout` | `centered` / `corner` / `minimal` / `custom` | 居中卡片、右下角、极简、自由。非法值回退 `centered`。 |
| `presentationCustomLayout` | 对象 | 自由版式下三个组件的归一化中心点，见下文。 |
| `presentationComponentBackground` | `auto` / `glass` / `clear` | 时钟底板。`auto` 在纯色幕布上透明，图片和渐变上保留玻璃底板。非法值回退 `auto`。 |
| `presentationDefaultBackdrop` | 布尔 | 没有自定义图片时是否绘制内置深色渐变。默认 `true`。 |
| `presentationShowSeconds` | 布尔 | 时钟是否显示秒。默认 `true`。 |
| `presentationShowLunar` | 布尔 | 是否显示中文农历。默认 `true`。 |
| `presentationShowElapsed` | 布尔 | 是否显示「已保护」计时徽标。默认 `true`。 |
| `mainDisplayRole` | `black` / `presentation` | 主屏角色。默认 `presentation`。 |
| `secondaryDisplayRole` | `black` / `presentation` | 其余屏幕角色。默认 `presentation`。 |
| `presentationFocusX` / `presentationFocusY` | 0–1 | 背景图焦点，默认居中。 |
| `presentationZoom` | 1–2 | 背景图放大倍数。 |
| `presentationDim` | 0–0.8 | 背景图额外暗化。 |

没有自定义图片且 `presentationDefaultBackdrop` 为 `true` 时，画布会绘制内置深色渐变；关闭后使用 `veilColor` 的纯色。展示模式关闭时，主/副屏角色都会被强制为 `black`。

背景按优先级选择：场景背景图（场景提供时）→ `presentationVideoPath` → `presentationImagePath` → `presentationAmbientStyle` → 内置深色渐变（`presentationDefaultBackdrop`）→ `veilColor` 纯色。视频每块屏一个播放器、静音循环；起幕验证期间暂停，验证结束恢复。视频文件读取失败或校验不通过时，起幕会记录 `presentation_video_unavailable` 并回退到下一层背景，不会撤幕。场景设置了独立背景图时优先于全局视频。

纯色幕布不会再叠加图片用的明暗渐变。文字和铜色强调会按 `veilColor` 的相对亮度自动选择深色或浅色，`presentationComponentBackground` 控制是否保留时钟底板：

- `auto`：纯色幕布上不使用底板，文字直接落在幕布颜色上；图片和内置渐变保留半透明底板。
- `glass`：始终保留底板；浅色幕布上使用浅色玻璃。
- `clear`：始终不使用底板。

`veilColor` 没有透明度。gamma 输出层只能改显示颜色，不能透出桌面；展示窗口也必须保持不透明，否则桌面会直接露给人和未经排除的采集路径。

### 自由版式

`presentationLayout` 为 `custom` 时，时钟卡片、场景提示和预计返回时间分别定位。位置是组件中心点的归一化坐标：

- `x`：`0` 贴左，`1` 贴右。
- `y`：`0` 贴顶，`1` 贴底。

画布会按组件实际尺寸再做一次内缩，避免拖到屏幕外；多块屏使用同一组比例坐标。设置窗口里直接在预览中拖动即可，无需手写 JSON。缺少的坐标或非法值会回退到内置位置（时钟居中、提示偏上、返回时间偏下）。

```json
{
  "presentationLayout": "custom",
  "presentationCustomLayout": {
    "clock": { "x": 0.62, "y": 0.54 },
    "message": { "x": 0.24, "y": 0.2 },
    "returnTime": { "x": 0.78, "y": 0.86 }
  }
}
```

## 自动化

| 字段 | 说明 |
|---|---|
| `idleAutoVeilEnabled` / `idleAutoVeilSeconds` | 物理输入空闲达到阈值后自动起幕。范围 60–86400 秒；真实输入后重新计时。 |
| `scheduleEnabled` | 启用每日定时保护。 |
| `scheduleStartMinutes` / `scheduleEndMinutes` | 从 00:00 起的分钟数。开始晚于结束表示跨午夜；相同表示选中日期的全天。 |
| `scheduleWeekdays` | 周一至周日对应 bit 0–6，默认 127（每天）。启用定时时至少选择一天。 |
| `scheduleAutoExit` | 时段结束时只发起验证，不自动露出桌面。 |
| `defaultProtectionMinutes` | 见「幕帘与会话」。 |

所有自动路径只负责起幕或发起验证，不会自动解锁。

## 更新

| 字段 | 默认值 | 说明 |
|---|---|---|
| `automaticUpdateChecksEnabled` | `true` | 启动后 8 秒检查一次，此后每 6 小时检查 `github.com/NotoChen/Auleum/releases/latest`。关闭后不自动检查，但仍可在设置或状态面板手动检查。 |
| `automaticUpdateInstallsEnabled` | `true` | 发现新版本后自动下载 `Auleum-<version>.zip`，校验 Release 的 SHA-256、Bundle ID、版本号和代码签名，并在幕帘关闭且未录制时安装、重启。关闭后只检查，安装需要手动触发。 |

更新目录位于 `~/Library/Application Support/Auleum/updates/`，安装日志写入 `update.log`。安装脚本会等待 Auleum 退出，备份旧 app、复制新 app、再次校验签名并启动；新版本未启动时自动回滚。ad-hoc 代码身份会随版本变化，更新后可能需要重新确认 TCC 权限。

## 场景

`sceneProfiles` 的键为 `away`、`meeting`、`guest`、`focus`；未写入的键使用场景默认值。场景只影响本次会话，不修改全局展示模式。

| 字段 | 说明 |
|---|---|
| `protectionMinutes` | 0–1440；`0` 表示不限时。 |
| `usesPresentation` | 是否使用展示模式；`false` 时用 gamma 黑幕。 |
| `backgroundImagePath` | 场景独立背景图；空字符串跟随全局背景。 |
| `clockStyle` | 场景独立时钟样式；空字符串跟随全局。 |
| `message` | 显示在时钟上方的提示文字，最长 160 字。 |
| `showsReturnTime` | 是否按保护时长显示预计返回时间。 |
| `mainDisplayRole` / `secondaryDisplayRole` | 覆盖全局屏幕角色；缺省表示跟随全局。 |

场景默认值：

| 场景 | 默认时长 | 展示方式 | 提示文字 |
|---|---|---|---|
| `away` | 120 分钟 | 展示模式 | 离开中 |
| `meeting` | 60 分钟 | gamma 黑幕 | 会议中 |
| `guest` | 30 分钟 | 展示模式 | 访客模式 |
| `focus` | 90 分钟 | gamma 黑幕 | 专注中 |

示例：

```json
{
  "sceneProfiles": {
    "away": {
      "protectionMinutes": 120,
      "usesPresentation": true,
      "backgroundImagePath": "/Users/me/Pictures/office.heic",
      "clockStyle": "analog",
      "message": "离开中",
      "showsReturnTime": true
    }
  }
}
```

## 其它

- `hasShownOnboarding`：首次引导是否已显示。
- 审计日志：`~/Library/Application Support/Auleum/audit.log`，每行一条 JSON。审计链用于发现中途修改、删除和损坏，但不能防止同一用户重写整份文件或截断末尾。
- 截图目录、帧率、码率是 `auleumctl` 参数（`--out`、`--fps`、`--bitrate`），不进配置文件。
