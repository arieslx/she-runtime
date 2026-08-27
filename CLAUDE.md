# SheRuntime — Agent 工作约定

> 给所有 AI 编码工具（Claude Code / Cursor / Copilot 等）的项目规则。
> 改代码前先读完。规则来源：团队会议要求（经转述）+ 已形成的代码实践。
> 团队：艾瑞(arieslx)=开发负责人 · Ginger=产品 · 小南=视觉 · 小花+石宝=营销/文案

## 项目是什么

个人身体学习系统（iOS App + M5Stack 硬件）。把三类信息放进同一条身体时间线：
Apple Watch/HealthKit 客观信号、圆形硬件主观感受、手机端上下文，帮用户发现自己的身体规律。

## 技术规则（必须遵守）

### 1. 文案一律走 JSON，禁止在 Swift 里写死界面文字
- 界面文案放 `apps/ios/sheRuntime/sheRuntime/copy_zh.json`
- 代码用 `C.t("页面.键名")` 读取（见 `CopyProvider.swift`），例：`Text(C.t("today.title"))`
- 新增文案时，`copy_en.json` **同步加同名键、值留空**（多语言预留；en 为空自动回退中文）
- 目的：文案(小花)改字只改 JSON，不碰代码
- 允许的例外：格式化拼接文本（如 "5 条"）、开发调试用的临时入口文字

### 2. 假数据集中放，页面代码里不藏数据
- Today 页假数据在 `TodayMockData.swift`，其余四页在 `AppMockData.swift`
- 页面 View 只负责"长什么样、怎么点"，数字/列表一律从 Mock 文件来
- 接真数据时只替换这两个文件，不动 View

### 3. 不碰底层代码（艾瑞的地盘）
以下文件不要改动，页面工作与它们无关：
- `ContentView.swift`（调试探针，入口收在「我的」页尾）
- `HealthKitManager.swift`
- `Audio*.swift` 全系列（AudioFileStore / AudioProbeView / AudioProbeViewModel / AudioRecorderService）
- `firmware/` 目录（硬件固件）

### 4. MainTabView 是临时脚手架
5-tab 框架是产品侧临时搭的，只为看整体效果。正式框架由艾瑞定（他要接蓝牙/数据/AI 通信）。
不要在 MainTabView 上叠加功能；5 个页面都是独立 View，可直接挂进任何框架。

### 5. Xcode 工程用文件夹自动同步
`.swift` / 资源文件放进 `sheRuntime/` 目录即自动纳入编译，**不需要也不要手改 pbxproj**。
JSON 文案文件直接放在 `sheRuntime/` 目录下（会打进 bundle 根，`Bundle.main.url(forResource:)` 可读）。

### 6. 编译与验证
```
cd apps/ios/sheRuntime
xcodebuild -project sheRuntime.xcodeproj -scheme sheRuntime \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build CODE_SIGNING_ALLOWED=NO
```
- 本机环境参考：Xcode 26.x / Swift 6.x，bundle id `com.arieslx.sheRuntime`
- 提交前必须编译通过
- 逐页截图排查：用 `SIMCTL_CHILD_SHOT_PAGE=0..4 xcrun simctl launch ...` 指定启动 tab（见 MainTabView）

### 7. Git 流程
- 分支走 `feat/xxx`，提 PR 到 main，**不直接推 main、不自行合并**
- commit 只加自己新建/改动的文件，不要 `git add -A` 带进无关文件

## 产品文案原则（写/改任何界面文字前必读）

> 来源：产品定位。拿不准时问产品(Ginger)，不要自行发挥。

- **学习系统，不是决策工具**：不给医学结论、不替用户做判断。口径参考现有文案：
  "仅供参考，我还在慢慢学你"、"这些是你的个人规律，不是医学结论"
- **跟自己比，不跟人群比**：一切表述基于个人基线（近 28 天），
  不出现"正常值 / 人群平均 / 你应该"这类说法
- **相关不等于因果**：描述规律用"通常对应 / 更常出现"，不用"导致 / 因为"下死结论
- 视觉依据：产品原型 `她律原型01.html`（Ginger 处）。米白底(#F4F4EF 近似)、黑主色、大圆角卡片

## 现状速览（2026-08-27）

- 5 个页面（今日/地图/洞察/问问/我的）已完成：静态页面 + 假数据，文案已 JSON 化
- PR #1：`feat/app-pages-ginger`，待 review，框架归属待艾瑞定
- 底层（HealthKit / Audio / 固件）由艾瑞推进，页面尚未接真数据
