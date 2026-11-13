# 竞品调研：macOS 菜单栏「喝水 + 站立/久坐提醒」App

- 调研日期：2026-11-12
- 目标产品：macOS 菜单栏常驻的喝水 + 站立/久坐提醒 App，核心卖点「提醒效果强烈、无法忽略」，面向个人用户
- 取证方式：官网 / Mac App Store 页面 / GitHub / Hacker News（Algolia API）/ V2EX / 少数派 / Reddit（RSS）/ Sensor Tower / Statcounter
- 引用纪律：本文只写检索到的内容并附 URL；凡属推断一律标注「推测」；查不到的一律写「未找到」

> 术语注记：本调研沿用市场通称「喝水 + 站立/久坐」分类；产品里的第二个场景叫「活动」（定时起身舒展），本期不做久坐检测。

---

## 0. 结论速览

1. **macOS 端没有「喝水 + 站立」合体的强势产品**。喝水类（TakeSip、DWR、WaterMinder、Mochi Genie）几乎都是「安静的通知」，明确宣称「温和、不打扰」；休息类（LookAway、Time Out、Stretchly）卖点在「智能避让、不打断」。**「强烈到无法忽略」在营销叙事上是逆风位**——现有头部把自己定位成「不打搅的礼貌助手」。
2. **「强制阻断」功能其实已经存在**，只是都做成了可选项而非卖点：BreakTime（enforce）、MacBreakZ 5.45+（整屏锁定）、LookAway/DeskRest（lock screen）、Time Out（禁止跳过按钮若干秒）、Stretchly（Strict Mode / Break Health Mode 暗角渐强）。
3. **Mac App Store 的评价基数极小**：Time Out、BreakTime、LookAway、久坐提醒、中场休息在美区/中区 Mac 页面均显示「尚未收到足够的评分或评论」。说明这个品类在 Mac 上「用的人不少、留评的人极少」，不能拿 iOS 的热度类推。
4. **唯一拿到的收入硬数据**：LookAway 开发者在 HN 自述 2025-01 时约「$5k/月净收入」，主要靠口碑增长（见 §4）。这基本是该品类 Mac 独立开发的头部量级参照。
5. **付费模式高度分裂**：开源免费（Stretchly / BreakTimer / Give Me A Break / Shui）、买断 $4.99（BreakTime / HazeOver）、买断 $19–29（LookAway / MacBreakZ）、买断 $49.99（Viraam）、订阅 $1.49–4.99/月（Flow / Session / Viraam）、国内终身 ¥68（中场休息）。
6. **中文区「强制全屏」已被验证可卖**：少数派把「全屏提醒，强制你休息，绝对不会错过」当作卖点写推荐文；这说明中文用户对「硬提醒」的接受度高于英文区头部产品的定位。

---

## 1. 直接竞品清单

> 阅读提示：Mac App Store 的评分/评价数大多不展示（样本不足），下表「评分」列写「未展示」即为 Apple 页面原文「尚未收到足够的评分或评论」。

### 1.1 休息/久坐提醒（主战场）

| 产品 | 形态 | 平台 | 价格 / 商业模式 | 最近更新 | 评分/评价数 | 核心机制（间隔 / 可跳过 / 遮挡方式） |
|---|---|---|---|---|---|---|
| **Stretchly** | 菜单栏（Electron） | macOS 13+ / Win / Linux | 免费开源；GitHub Sponsors / Patreon 赞助解锁 Contributor 偏好 | 仓库内标注 Release 1.22.1（2026-08-13）；2026-11-11 仍有提交 | App Store 无（官网/GitHub 分发）。GitHub 星数未取得（API 限流） | 默认 20s Mini break / 10min、5min Long break / 30min；可推迟 1 次（2/5 分钟），之后才可跳过；**Strict Mode**、**Break Health Mode**（跳过越多，休息窗口边缘暗角越强，仿游戏低血量）；全屏窗口、可全屏到所有显示器、macOS 支持背景模糊；命令行 `stretchly` 可交互；应用排除规则 |
| **Time Out (Dejal)** | 菜单栏 + Dock | macOS 26+（4.0） | 核心功能永久免费；Supporter $4.99/3 月、$9.99/6 月、$19.99/12 月；Lifetime $59.99；另有 Mac App Store 版（含月/年 Premium 订阅）与 Setapp | v4.0（2026 年，v3 于 2026-05 发布） | 未展示 | 默认 Normal 10min/60min + Micro 15s/15min；休息时全屏主题，可选「禁止跳过/推迟」、按钮在休息开始后禁用数秒、隐藏易绕过命令；Break Actions 支持 AppleScript/shell/Python/Automator、系统音量、闪屏、语音播报；Rules 支持按 App / 日历 / Focus / 全屏 / 会议（FaceTime、Teams、Zoom）推迟 |
| **LookAway** | 菜单栏（原生 Swift） | macOS 13+ | 直售 $19（1 台）/ $29（2 台）/ $99（终身更新）；App Store 另有内购版；Setapp 收录 | v2.4.11（2026-10-22），更新极频繁 | 未展示 | 短/长休息 + 眨眼 + 姿势提醒；Smart Pause 自动避让会议/录屏/视频/全屏游戏/深专注 App/输入中/空闲；**可选休息时锁屏**；休息可「必须按 End Break 才结束」；跳过上限、提前跳过；AppleScript/Shortcuts 自动化；Live Activities 同步 iPhone |
| **DeskRest** | 菜单栏 | macOS 14.2+ | 免费下载 + 内购（具体档位未核实） | 1.18.x（2026，含锁屏） | 未展示 | 20s 短休息 + 3min 长休息，可自定义；光标跟随倒计时；视频通话/会议/Focus 检测；**1.18 起支持 Lock Screen 休息**；姿势闪屏提醒；Clock Out（强制下班）；Apple Shortcuts |
| **Viraam** | 菜单栏 | macOS 14+（另有 iOS/iPadOS 18+ 独立 app） | Mac：$2.99/月、$19.99/年、$49.99 买断；14 天试用 | 官网在售（版本号未核实） | 官网引用多条 5 星（数量未核实） | 6 类提醒（护眼 20-20-20 / 站立伸展 / **喝水** / 走路 / 呼吸 / 姿势·眨眼）；三档呈现：Subtle / Gentle / **Immersive（全屏接管）**；会议与全屏视频避让、休息合并、工作日/周末、Pomodoro 专注段 |
| **MacBreakZ 5** | 菜单栏 | macOS 13+（另提供旧系统包） | 买断 $24.95（官网；MacUpdate 曾标 $29.95） | v5.48（2026-03-09） | 无 App Store（2014 年已下架） | 键鼠活动监测 + 「活动水平」自适应休息；42 个拉伸动作；微休息；**v5.45（2022-07）起由「透明浮窗」改为「锁定整个屏幕」**，并保留旧版下载给不适应者；可设为不可手动跳过；stealth 模式 |
| **BreakTime** | Dock/菜单栏 | macOS 10.7+（沙盒，2.4 MB） | 买断 $4.99 | **v2.5.2（2015-10-24），约 11 年未更新** | 未展示（有评论「Last updated 9 years ago / No support」） | 可开 **enforce**：休息结束前不允许操作其他程序；休息前 10 秒菜单栏预警，随后**屏幕缓慢变暗**；Magic Rescheduling 依据键鼠使用重排；AppleScript 可 start/end/reschedule |
| **Take a Break** | 菜单栏 | macOS | 免费下载 + $1.99 Pro 解锁 | 最后可见更新 2025-01-03 | 未核实 | 20-20-20 + 站立休息；可自动锁屏；菜单栏倒计时；看视频自动暂停（以上据第三方对比文，未逐一验证） |
| **Give Me A Break** | 菜单栏（开源） | macOS 14+ | 开源；Mac App Store + 官网 DMG | 在售（版本未核实） | 未核实 | 休息（全屏遮罩）、姿势检查、站/坐交替；间隔 5min–2h；可选 Apple Intelligence 生成提醒文案；零网络请求 |
| **Aware** | 菜单栏 | macOS | 价格未核实（App Store id1082170746） | 未核实 | 未展示 | **只累计「连续使用时长」，刻意不做弹窗/闹钟**；检测键鼠活动，空闲即暂停计时。属于「提醒的对照面」 |
| **久坐提醒（川 戴）** | 菜单栏 | macOS 11+ | 免费（页面未显示内购） | v1.4.1，商店显示「3月11日」（按 Apple 当年省略年份惯例推测为 2026-03-11） | 未展示 | 每 20min **全屏强制提醒**，「防止误触解锁」；**全屏提醒渐变动画 + 高斯模糊背景**；站立模式 60min/5min；自定义图片；状态栏倒计时；另有一次性/周期性自定义提醒事项 |
| **中场休息（ClyApp）** | 菜单栏 | macOS 10.13+ | 免费下载 + **终身 Pro ¥68** | v0.15（2024-07-27），已超 1 年未更新 | 未展示（有若干中文评论） | 固定时刻或间隔提醒；**全屏提醒「你不可以再工作了」**；可阻止屏保；随机国画 + 古诗；休息统计；忽略时段 |
| **BalmyTime** | 菜单栏 | macOS + Windows | 免费 + 一次性买断解锁 Pro（价格未核实） | V2EX 首发 2024-06-24，帖内持续更新至 2025-08 | 无 | 不做番茄钟，改为**固定「休息点」**（如每小时 50 分），灵感来自 Apple Watch 站立提醒；屏幕使用时间记录；日历式回顾 |
| **Shui（开源）** | 菜单栏（Tauri） | macOS | 免费开源 | 2025-04 发布 | 无 | 喝水目标 + 工作时间 + 间隔；**定时全屏提醒、支持多显示器**；白名单 App（看视频/游戏/会议）自动暂停；锁屏暂停；菜单栏倒计时 |
| **BreakTimer** | 菜单栏（开源，Electron） | macOS / Win / Linux | 免费开源 | 维护中（版本未核实） | 无 | 工作时段、日程、颜色/文案自定义；休息前「智能通知」以便跳过或延后；定位为「轻量日程器」 |
| **Stand Up!（iOS 对照）** | iPhone/iPad app | iOS（**非 macOS**） | 免费 + 一次内购解锁全部铃声（含打赏档） | **v1.4.10（2018-03-27）** | **4.5K 评价，4.7 分** | 5min–2h 任意 5 分钟档；设起止时间与星期；「站立时长」计时；GPS 限定办公地点；多次「insistent」铃声 + 随机铃声模式；交互式通知可锁屏确认 |
| **EyeLeo（Windows 对照）** | 桌面 | Windows 7/8/10 | 免费 | 仓库最后提交 **2020-10-25**，79 stars，**无正式 Release** | 无 | 短休息 + 长休息 + 眼保健操；短休息强制遮挡屏幕；官网 `eyeleo.com` 现已不提供产品内容（返回博彩页），可判定项目停摆 |
| **Flow（番茄钟对照）** | 菜单栏 | macOS / iOS / iPad / Watch | 免费 + Pro **$1.49/月**（年付） | 维护中 | **4.8 分，25k+ 评论**（官网自述；App Store 全平台） | 固定专注/休息间隔、App/网页屏蔽、Apple 日历同步；官网称 1,000,000+ 下载、100,000+ 日活 |
| **Session（番茄钟对照）** | 菜单栏 + iOS | macOS / iOS | 免费 + Pro **$4.99/月 / $39.99/年**（$3.33/月） | 维护中 | 未核实 | 专注 + 休息；网页/App 屏蔽；Slack 静音；AppleScript / Shortcuts 自动化；Apple 日历写入 |
| **Rest** | — | — | — | — | — | **未找到**名为「Rest」的 macOS 休息提醒产品；仅在 publicspace 站点导航里见到其自家 **“Rest Time”** 入口（另一款产品，未展开核实） |

### 1.2 喝水提醒（相邻品类，macOS）

| 产品 | 形态 | 价格 | 最近更新 | 机制要点 |
|---|---|---|---|---|
| **TakeSip** | 菜单栏 | 免费（Mac App Store） | 维护中 | 15/30/60 分钟间隔，只发「温和通知」；**明确不做饮水量记录**；官网自述「10,000+ 用户」 |
| **DWR (Daily Water Reminder)** | 菜单栏 | 免费 | 最后更新 2025-06（第三方核对） | 5–60 分钟间隔、免打扰时段、通知内一键记录、日/月统计 |
| **WaterMinder** | 菜单栏 + iOS + Watch | 免费 + 高级内购 | 维护中 | 按体重设目标、记录每杯、填充小人像；偏「追踪器」而非「提醒器」 |
| **Just Drink** | 桌面 | 订阅 / 终身（欧元计价，试用需绑卡） | 维护中 | Mac + Windows 极简补水提醒 |
| **Mushroom** | 桌面宠物 | **$9.99 买断**（7 天试用） | 维护中 | 像素小蘑菇常驻桌面，按键盘活跃度计时，提醒喝水/零食/休息/护眼；仅 Apple Silicon + macOS 15+ |
| **Mochi Genie** | 桌面宠物 | **$12.99 买断**（7 天试用，不绑卡） | 维护中（1.0.1） | 每 45 分钟举瓶喝一口，点「Done」会欢呼；含水/伸展/护眼/姿势/走路/休息 6 类；麦克风·摄像头·全屏时自动等待 |

### 1.3 相关但不属于提醒（相关品类）

| 产品 | 说明 | 价格 |
|---|---|---|
| **HazeOver** | 「Distraction Dimmer」：把非前台窗口压暗以聚焦，属于「屏幕遮罩/调暗」技术同源产品，不是休息提醒 | 买断 **$4.99**，另有 Setapp、官网直售、学生折扣 |

---

## 2. 「强烈提醒效果」的具体实现手法

### 2.1 手法 → 谁在用

| 手法 | 现有产品 | 证据 |
|---|---|---|
| **系统通知（Notification Center）** | TakeSip、DWR、Stand Up!、Stretchly（休息前 10s/30s 预警）、LookAway（Heads-up） | Stand Up! 用户评论描述「banner notification + 长而响的铃声」；Stretchly README 明确 10s/30s 预警 |
| **全屏遮罩窗口** | Stretchly（`fullscreen`、`allScreens`）、Time Out（休息主题铺满）、MacBreakZ、久坐提醒、中场休息、Viraam（Immersive）、Give Me A Break | 久坐提醒商店页「全屏强制提醒，防止误触解锁」；中场休息「全屏提醒，你不可以再工作了」 |
| **强制倒计时 / 禁止提前结束** | Time Out（休息开始后禁用跳过按钮数秒、限制推迟/跳过次数、隐藏绕过命令）、LookAway（「必须按 End Break 才结束」）、Stretchly（Strict Mode、`*ManualFinish`） | Time Out 官网「Set limits on postponing and skipping… briefly disable the buttons at the start of a break」 |
| **阻止操作其他程序（真·锁定）** | BreakTime `enforce`、MacBreakZ 5.45+（锁整个屏幕）、DeskRest 1.18（Lock Screen）、LookAway（可选锁屏） | BreakTime 商店页「won't allow you to work on anything else until you've finished your entire break」；MacBreakZ 版本历史 5.45「now locks the entire screen(s)」 |
| **屏幕变暗 / 灰度 / 模糊** | BreakTime（缓慢变暗）、Time Out（渐进变灰 + 模糊背景）、Stretchly（macOS `blurredBackground`）、久坐提醒（高斯模糊背景）、HazeOver（压暗非前台窗口） | 用户评论「the gradual and subtle greying of the screen」；久坐提醒商店页「高斯模糊背景」 |
| **边缘暗角随「违规」加重** | Stretchly **Break Health Mode**（跳过/推迟越多，休息屏边缘越红越强，自然完成则回落） | README「Inspired by the screen-edge vignette used in video games to indicate low health」 |
| **声音 / 渐强铃声** | Stretchly（start/end 音效、音量可调）、Stand Up!（多档「insistent」铃声、随机铃声防脱敏）、Time Out（Break Actions 播放声音/调系统音量） | Stand Up! 商店页「Many custom alarms, some quite insistent. And there's a random mode to keep you on your toes」 |
| **语音播报** | Time Out（Break Actions「hear a spoken reminder」/speak text） | 官网原文 |
| **闪屏** | Time Out（flash the screen）、DeskRest（姿势「screen flashes」） | 各自官网 |
| **锁屏** | LookAway、DeskRest、Take a Break（据第三方对比）、MacBreakZ（等效） | LookAway 商店页「Optionally lock your screen when a break begins」 |
| **AppleScript / shell / Shortcuts 钩子** | Time Out（AppleScript/shell/Python/Automator）、LookAway（AppleScript/Shortcuts）、BreakTime（AppleScript）、Session（AppleScript）、DeskRest/Viraam（Shortcuts）、Stretchly（`stretchly` CLI） | 各自官网/商店页 |
| **多显示器全覆盖** | Stretchly（`allScreens`、可指定 `breakContentScreen`）、Shui（明确「支持多显示器，确保提醒不会被遗漏」）、LookAway（可选「在哪个屏幕显示提醒」）、Time Out（每个显示器独立主题） | 各自文档 |
| **摄像头确认 / 人在场检测** | **未找到**任何本品类产品做「摄像头确认」或「人脸/姿势验证后才算休息」；仅见摄像头/麦克风**占用检测**（用于暂停提醒，而非确认） | LookAway 2.4.10 更新日志提到 microphone/camera detection 的修复；Mochi Genie、Viraam 用摄像头/麦克风占用做「避让」 |

### 2.2 macOS 平台侧限制（决定了「强制」能做到多硬）

| 能力 | 平台机制 | 限制与现实约束 |
|---|---|---|
| 本地通知 | `UNUserNotificationCenter` | 需用户授权；可被专注模式/勿扰压制；通知可被一次点击划掉，「无法忽略」做不到 |
| 全局键鼠/前台 App 监测 | Accessibility（TCC 辅助功能授权）、`CGEventTap` | 需用户手动在系统设置里勾选；LookAway 2.4.4 更新日志称「打字检测与全屏 App 检测已不再需要辅助功能权限」，说明这类权限是可用性痛点，厂商在主动摆脱它 |
| 覆盖其他 App 的窗口 | 普通 App 可创建置顶无边框窗口（`NSWindow.level`），无需特殊权限 | 但无法阻止用户按 Esc/切 Space/⌘-Tab 离开；「真锁屏」要么调用系统锁屏，要么拦住输入（后者更接近恶意软件行为，App Store 审核与用户信任都有风险） |
| 检测/排除录屏与共享 | ScreenCaptureKit；隐藏自身窗口不被捕获 | 需**屏幕录制**权限；否则「在共享屏幕时自动隐藏提醒」这类体验无法实现（Viraam 宣称提醒自动排除在截图/录屏/共享之外） |
| 控制其他 App / 系统（暂停音乐、锁屏、DND） | Apple Events / Automation 权限、`Shortcuts`、`NSWorkspace` | 需逐 App 授权；macOS 26+ 对自动化权限弹窗更严格 |
| App Store 沙盒 | Mac App Store 版本受沙盒限制 | LookAway 存在 MAS 版与官网直售版的**功能差异**（Reddit 用户转述「2-3 个小功能因沙盒缺失」）；MacBreakZ 2014 年直接退出 MAS，理由是「sandboxing requirements」 |
| 分发包 | 公证（notarization） | Stretchly 只做 ad-hoc 签名，官方文档要求用户 `xattr -d com.apple.quarantine` 或在系统设置里「仍要打开」；Homebrew 主 cask 因未签名计划于 2026-09-01 停用 |

> 结论（推测）：在 macOS 上做「无法忽略」的上限是「锁屏级阻断 + 全屏遮罩 + 反复回升的提醒」，再往上就是恶意软件语义；真正的产品空间不是「更硬」，而是「在正确的时刻硬、在错误的时刻让」——而这恰是 LookAway/Time Out 已占的位。

---

## 3. 用户抱怨点（带原话与链接）

### 3.1 「提醒被我关掉 / 我自己把 App 关了」

- 中区 App Store，中场休息评论（用户痛点：节假日也想关）：
  > 「界面简洁，功能强大，希望能增加节假日跳过提醒的设置」
  https://apps.apple.com/cn/app/id6470251574
- HN 用户 Cider9986 谈 LookAway：
  > "This app was good but I ended up disabling it and they forgot to turn it back on."
  https://news.ycombinator.com/item?id=48665530
- HN 用户 Kovah（订阅 Setapp 用户）：
  > "ever so often I am in deep focus and get really annoyed when the 'long break starting in 1 minute' notification pops up. Most of the time I am in the middle of writing when the break starts, and I click it away fast to not loose my thoughts."
  https://news.ycombinator.com/item?id=48666034
- Reddit r/macapps 用户 MaxGaav：
  > "Years ago I bought a license for TimeOut … But I actually never used it in practise. Just a simple timer does the job for me."
  https://www.reddit.com/r/macapps/comments/1p9p0cn/take_a_break_mac_apps_help_me_choose_one/

### 3.2 「遮挡太狠 / 时机太差 → 卸载」

- HN 用户 tedmiston：
  > "Time Out is okay but extremely annoying in that it always seems to pop up and take over the screen at the worst possible times even with configuration to make it less interruptive. I stopped using it in favor of just closing my laptop for a bit."
  https://news.ycombinator.com/item?id=48677252
- HN 用户 dalfonso（Time Out 用户）：
  > "The hardest scenario is if I'm in 'the zone' and super focused on fixing a bug… I end up feeling antagonistic towards the break reminder."
  https://news.ycombinator.com/item?id=22780478
- Reddit 用户 spacedjunkee（同时买过 LookAway 与 DeskRest）：
  > "LookAway just felt a little too annoying I just couldn't stand it after a while. DeskRest in comparison feels a lot more friendlier for some reason."
  https://www.reddit.com/r/macapps/comments/1p9p0cn/take_a_break_mac_apps_help_me_choose_one/
- HN 用户 tedmiston（对品类整体）：
  > "They work in that they induce taking more breaks (20/20/20 rule) but they're also annoying in that they interrupt deep focus."
  https://news.ycombinator.com/item?id=48677316

### 3.3 「提醒太弱 → 我根本没注意到」（与卖点最相关的一类差评）

- 美区 App Store，Stand Up! 评论：
  > "The alert volume is very low. I have it on the highest setting and still miss my alerts. The alarm will only go off once… It doesn't keep beeping until you've acknowledged the reminder either. So I've often missed two to three timers in a row and never noticed."
  https://apps.apple.com/us/app/stand-up-the-work-break-timer/id828244687
- 同类另一条 Stand Up! 评论：
  > "The only reason I left a star off is the notification sounds. The one included in the free version is VERY quiet. I rarely hear it and, if my phone is off to the side, don't see the screen light up."
  同上链接
- BreakTime 评论（App 被无意关掉，几小时没休息）：
  > "if you working at this time … and press on the space bar, it disable the app altogether… you might notice that you had no breaks, only after a few hours."
  https://apps.apple.com/us/app/breaktime/id427475982?mt=12

### 3.4 「不能配置休息日 / 周末 / 节假日」

- 中场休息中区评论（见 3.1 引文）：明确要求「节假日跳过提醒」。
- Time Out 官网把「limit them to particular hours and days」做成功能说明，说明这是被反复提的需求（官网原文）。
  https://www.dejal.com/timeout/
- 补充：MacBreakZ 提供「禁用 2 小时 / 4 小时 / 今天剩余时间」（版本历史 4.6，2007 年就有），说明「临时全关」是 20 年历史的刚需。

### 3.5 「订阅太贵 / 定价让人不适」

- HN 用户 hailtothechimp 对 LookAway：
  > "Looks nice, but hate that pricing."
  https://news.ycombinator.com/item?id=48667905
- HN 用户 sosodev：
  > "The license scheme makes me sad. It reads like a subscription pretending to be a one-time purchase."
  https://news.ycombinator.com/item?id=48666837
- Reddit 用户 macnatic0：
  > "LookAway is overall more mature with beautiful animations. However, I find LookAway's regular price difficult to justify."
  https://www.reddit.com/r/macapps/comments/1p9p0cn/take_a_break_mac_apps_help_me_choose_one/
- 中区 App Store，中场休息评论：
  > 「收费怎么不在下载的时候就提示收费呢」
  https://apps.apple.com/cn/app/id6470251574

### 3.6 「和番茄钟不能共存 / 形态是番茄钟」

- V2EX「BalmyTime」帖作者（做了 249 回复的长帖）：
  > 「我找了一下现在有的大部分休息工具，发现它们大多都是以『番茄钟』的形式存在的。先要你设置一个专注的时长，然后等倒计时结束后就来提醒你。它们更像是一个让你保持专注的约束，而不是一个希望你自己能规律 Break 的工具。」
  https://www.v2ex.com/t/1052074
- 该帖 32 楼用户：
  > 「试用了一下, 感觉不错, 比 stretchly 强」
  同上链接
- 番茄钟阵营自身的问题（Session 定价被吐槽）——以下为该帖内一条评论，仅通过检索摘要读到，未打开原帖逐字核对：
  > "I love Session, but the free tier is not enough for me and I can't afford a $40 subscription."
  https://www.reddit.com/r/macapps/comments/11745yo/request_looking_for_a_pomodoro_app_an_alternative/

### 3.7 「质量/信任问题」（中区特有）

- 中区 App Store，久坐提醒（id6736850788）唯一可见评论：
  > 「他会给你设置网络策略，并且无法移除，一直出现信任弹窗」标题：「不要下载不要下载不要下载」
  https://apps.apple.com/cn/app/id6736850788
- 停更焦虑（HN，2026-05，Time Out v3 讨论）：
  > "I tried a couple of these break reminders… However after some time, they end up being unmaintained."
  https://news.ycombinator.com/item?id=48125467

### 3.8 拿不到证据的渠道（明确写「未找到」）

- **小红书**：本次未检索到可引用的具体笔记（平台内容不便直接抓取，也未取到可验证原话）。**未找到**。
- **r/productivity**：未检索到针对 macOS 休息提醒的具体高赞抱怨帖，仅有 r/macapps 内容。**未找到**。
- Reddit 全量评论抓取受接口限制（未登录仅能取单帖 RSS，且多次 429 限流），本文引用的 Reddit 原话来自成功抓取的 1 个帖子（r/macapps, 2025-11-29）。**样本有限，不代表全站观点**。

---

## 4. 市场规模的硬数据

| 指标 | 数据 | 来源与年份 |
|---|---|---|
| 健康健美品类 IAP 收入（全球，iOS+Google Play） | **$45 亿**，同比 **+13%**，创历史新高 | Sensor Tower《State of Mobile 2026》博文，2026-02。**非 macOS 数据**，仅作品类天花板参照 |
| 健康健美品类下载量（同上口径） | **39.6 亿次**，同比仅 +0.8% | 同上 |
| 该品类头部 Mac 产品的收入 | LookAway 开发者自述：「I've been building a break reminder app for mac since slightly more than a year… It currently nets **$5k a month**」（靠口碑增长，卖永久授权 + 首年后更新收费） | Hacker News 评论，2025-01-20，https://news.ycombinator.com/item?id=42765274 |
| 苹果活跃设备总数 | **25 亿台**（2026-01 财报电话会），2025-01 为 23.5 亿台 | AppleInsider 引述财报会，2026-01-29，https://appleinsider.com/articles/26/01/29/apple-reaches-25-billion-active-devices-after-record-breaking-quarter ；MacRumors，2025-01-30，https://www.macrumors.com/2025/01/30/apple-active-devices-worldwide-record/ |
| Mac 具体装机量 | **未找到**（苹果不单独披露 Mac 台数；无可靠第三方公开数字） | — |
| macOS 桌面系统份额 | 2026-10 全球桌面：Windows 76.65%、**OS X 9.86% + macOS 5.81%（合计约 15.7%）**、Linux 5.63% | Statcounter，2026-10，https://gs.statcounter.com/os-market-share/desktop/worldwide/ |
| macOS 桌面份额（美国） | OS X 15.92% + macOS 8.51%（合计约 24.4%） | Statcounter，2026-10，https://gs.statcounter.com/os-market-share/desktop/united-states-of-america |
| 开源竞品的社区体量 | Stretchly：61 个 tag、2,004 次提交、仓库 2026-11-11 仍有提交（活跃）；EyeLeo：79 stars、2020 年后无提交 | GitHub 仓库页 |
| 该品类付费转化率 / 下载→付费常识 | **未找到**任何可引用的公开数据（无 Appfigures/Sensor Tower 对该细分品类的公开拆解） | — |
| Mac App Store 头部产品收入估计（Sensor Tower/Appfigures 口径） | **未找到**（本次未能取得该细分品类的公开收入榜单或估算；Sensor Tower 的 Top Charts 需登录） | — |

> 推导（推测，仅供参考）：若 LookAway 2025-01 净收入约 $5k/月，按 $19 单 license 毛估约 300–400 单/月；考虑渠道抽成与退款，年流水量级大致在「数万美元～低十万级」。这基本是「Mac 单人独立开发 + 单一小工具」的现实天花板区间，不是 SaaS 曲线。

---

## 5. 定价参照

### 5.1 同品类实际价格（本次核实到的）

| 档位 | 产品与价格 |
|---|---|
| 免费开源 | Stretchly、BreakTimer、Give Me A Break、Shui |
| 免费 + 小额内购 | Take a Break（$1.99 Pro）；中场休息（**¥68 终身**）；WaterMinder（免费 + 高级内购） |
| 免费 + 订阅/打赏混合 | Time Out（$4.99 / $9.99 / $19.99 支持者档，Lifetime **$59.99**；MAS 版另有月/年订阅）；Stand Up!（一次性内购解锁铃声 + 打赏档） |
| 纯买断（小工具带） | **HazeOver $4.99**、**BreakTime $4.99** |
| 纯买断（中高价带） | **MacBreakZ $24.95**、**LookAway $19 / $29 / $99**、**Viraam $49.99 终身**、Mochi Genie $12.99、Mushroom $9.99 |
| 订阅 | **Session $4.99/月 或 $39.99/年**；**Flow $1.49/月（年付）**；**Viraam $2.99/月 或 $19.99/年**；Time Out MAS 版 Premium 订阅（具体价格未核实） |
| Setapp 分发 | Time Out、LookAway、HazeOver 均在 Setapp |

### 5.2 价格带观察

- **Mac 小工具「买断制」的普遍价格带（据本次样本）**：**$4.99（简单工具）→ $19–29（成熟独立产品）→ $49.99（含终身更新的「Believer」档）**。超过 $30 的纯买断在该品类很少见，$49.99 基本是「终身更新」的溢价位。
- **订阅价格带**：$1.49–4.99/月，$19.99–39.99/年。该品类的订阅接受度明显低于番茄钟（Session $39.99/年 被用户公开吐槽「付不起」）。
- **国内定价带**：终身 ¥68 是本次唯一核实到的中区买断价（中场休息 Pro）；中区头部（久坐提醒）直接免费无内购——说明国内该品类仍在「免费换量」阶段。
- **更新收费模式**：LookAway 用「永久授权 + 首年后更新收费」；Dejal 用「非订阅的支持者档 + Lifetime」；两者都在回避「订阅」这个词——因为用户对订阅的反应是负面的（见 §3.5）。

---

## 6. 空白点总结（≤200 字）

**已被做烂**：全屏遮罩、渐进变暗/模糊、休息前预警、跳过/推迟限额、会议与录屏避让、姿势与眨眼提醒、统计与连续天数、AppleScript/Shortcuts——七家以上产品功能高度重叠。

**空白且技术可行**：① 「硬提醒」被当成可选项而非身份，没人把它做成一眼可辨的差异化定位（Stretchly 的 Break Health Mode 最接近，但藏在一个 JSON 开关里）；② 喝水与站立至今分属两个品类，无人做「一体但分强度」的组合；③ 「摄像头/在场确认才算休息」无人实现，且 macOS 权限允许；④ 「违规记账 → 逐级升级阻断」无人产品化；⑤ 中文区「强制全屏」有明确需求，但只有停更的免费小工具在接。

---

## 7. 数据缺口清单（明确「未找到」）

1. Mac App Store 各产品评分与评价数：除 Stand Up!（iOS，4.5K/4.7）与 Flow（4.8/25k+）外，其余 Mac 产品页面均未展示评分（样本不足）。**未找到**。
2. 该品类头部产品在 Sensor Tower / Appfigures 口径下的收入估算：**未找到**（仅取得开发者自述数据）。
3. macOS 装机台数：**未找到**可靠数字。
4. 健康/久坐类 Mac App 的付费转化率常识：**未找到**。
5. 小红书原话：**未找到**。
6. r/productivity 具体抱怨帖：**未找到**（仅 r/macapps）。
7. Aware、Take a Break、BalmyTime、DeskRest、Give Me A Break 的精确价格与最近更新时间：部分**未核实**（已在表中逐项标注）。
8. Stretchly GitHub stars / 总下载量：GitHub API 限流，**未取得**。

---

## 附录 A：竞品来源索引（§1 各表格行的 URL）

### 休息/久坐提醒
- Stretchly：https://github.com/hovancik/stretchly ｜ README（Strict Mode / Break Health Mode / 全部偏好项）：https://github.com/hovancik/stretchly/blob/trunk/README.md ｜ 下载与 macOS 签名说明：https://hovancik.net/stretchly/downloads/
- Time Out：https://www.dejal.com/timeout/ ｜ 商店页：https://apps.apple.com/us/app/time-out-break-reminders/id402592703
- LookAway：https://lookaway.com/ ｜ 定价：https://lookaway.com/pricing ｜ 商店页（含版本历史与锁屏说明）：https://apps.apple.com/us/app/lookaway-break-reminder/id6747192301
- LookAway 自撰竞品对比（**厂商口径，仅作索引，不作中立事实**）：https://lookaway.com/blog/2026/04/24/best-break-reminder-apps-for-mac-in-2026/
- DeskRest：https://deskrest.com/ ｜ 商店页：https://apps.apple.com/us/app/deskrest-smart-break-reminder/id6751417411 ｜ 锁屏版本说明：https://deskrest.com/blog/deskrest-1-18-0-lock-screen-stability-updates/
- Viraam：https://www.viraam.app/ （含三档定价与 Immersive 模式、隐私与录屏排除说明）
- MacBreakZ：https://www.publicspace.net/MacBreakZ/index.html ｜ 版本历史（5.45 整屏锁定）：https://www.publicspace.net/MacBreakZ/version.html
- BreakTime：https://apps.apple.com/us/app/breaktime/id427475982?mt=12
- Take a Break：https://apps.apple.com/us/app/take-a-break-timer-reminder/id1457158844 （价格与更新时间为厂商对比文核对，未直接验证）
- Give Me A Break：https://givemeabreak.app/ ｜ https://github.com/jxucoder/give-me-a-break ｜ 商店页：https://apps.apple.com/us/app/give-me-a-break-health-timer/id6759898658
- Aware：https://awaremac.com/ ｜ 商店页：https://apps.apple.com/us/app/aware/id1082170746
- 久坐提醒（川 戴）：https://apps.apple.com/cn/app/id6736850788 ｜ 少数派推荐文（「全屏提醒，强制你休息，绝对不会错过」）：https://sspai.com/post/94065
- 中场休息（ClyApp）：https://apps.apple.com/cn/app/id6470251574
- BalmyTime：https://www.v2ex.com/t/1052074 ｜ https://balmytime.app/
- Shui：https://www.v2ex.com/t/1127305 ｜ https://github.com/rock-zhang/Shui
- BreakTimer：https://breaktimer.app/
- Stand Up!（iOS）：https://apps.apple.com/us/app/stand-up-the-work-break-timer/id828244687
- EyeLeo：https://github.com/Yamatao/eyeleoapp （最后提交 2020-10-25；无 release）｜ 官网 eyeleo.com 已不提供产品内容
- Flow：https://www.flow.app/pricing ｜ https://www.flow.app/ （1,000,000+ 下载、100,000+ 日活均为厂商自述）｜ 商店页：https://apps.apple.com/us/app/flow-focus-pomodoro-timer/id1423210932
- Session：https://www.stayinsession.com/pricing ｜ 商店页：https://apps.apple.com/us/app/session-pomodoro-focus-timer/id1521432881

### 喝水提醒
- 跨产品对比（**厂商口径**，作者自荐 Mochi Genie）：https://mochigenie.com/water-reminder-mac.html
- TakeSip：https://takesip.com/ ｜ 商店页：https://apps.apple.com/us/app/takesip-best-water-reminder/id6479617048
- DWR：https://apps.apple.com/us/app/dwr-daily-water-reminder/id6746666018
- WaterMinder：https://apps.apple.com/us/app/waterminder-water-tracker/id1415257369
- Just Drink：https://just-drink.app/
- Mushroom：https://www.getmushroom.app/
- Mochi Genie：https://mochigenie.com/water-reminder-mac.html

### 相关品类
- HazeOver：https://hazeover.com/buynow.html ｜ 商店页：https://apps.apple.com/us/app/hazeover-distraction-dimmer/id430798174

### 市场数据与平台机制
- Sensor Tower《State of Mobile 2026》品类博文：https://sensortower.com/blog/health-and-fitness-apps-ai
- Statcounter 桌面系统份额（全球）：https://gs.statcounter.com/os-market-share/desktop/worldwide/
- Statcounter 桌面系统份额（美国）：https://gs.statcounter.com/os-market-share/desktop/united-states-of-america
- Apple 活跃设备 25 亿：https://appleinsider.com/articles/26/01/29/apple-reaches-25-billion-active-devices-after-record-breaking-quarter
- Apple 活跃设备 23.5 亿：https://www.macrumors.com/2025/01/30/apple-active-devices-worldwide-record/
- LookAway 开发者自述月收入 $5k：https://news.ycombinator.com/item?id=42765274
- Stretchly 作者自述赞助收入（2018 年，Patreon 约 $11/月）：https://news.ycombinator.com/item?id=18361350
- ScreenCaptureKit（屏幕捕获 / 窗口排除的框架基础）：https://developer.apple.com/documentation/screencapturekit
