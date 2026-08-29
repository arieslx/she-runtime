# Robo / sheRuntime “主观数据闭环”交接文档

> 交接日期：2026-08-29（Asia/Shanghai）
>
> 适用对象：新接手的 AI Agent / iOS 开发 / 服务端开发 / 产品经理
>
> 当前状态：一条安全的最小纵切已实现、已提交、已推送到独立 GitHub 分支；尚未创建 PR，尚未合并到 `main` 或 `feat/product-polish`。

## 0. 给新 Agent 的开工指令

请不要从零重做，也不要先在共享主仓库里清理文件。先完整读完本文档、仓库根目录的 `CLAUDE.md` 和本文档列出的必读产品材料，然后在下面的独立 worktree 中核对实现：

```bash
cd '/Users/kongxueli/Desktop/coding/12-女性身体运行时/tmp/she-runtime-subjective-data-loop'
git status --short --branch
git show --stat d281511
```

任务原则：

1. 以当前运行代码为事实，不把旧交接文档或旧 Agent 结论当成已实现功能。
2. 保持“原话 → 用户确认 → 结构化 → 时间对齐 → 候选观察 → 用户纠错”的分层，不可把模型回答当成用户事实。
3. 不诊断、不暗示因果、不把单条记录包装成“规律”。
4. 先检查现有改动和其他并行分支，不要覆盖、回退或带入任何与本专项无关的文件。
5. 对 Ginger（产品）汇报时先讲用户体感和产品边界，再讲技术实现；分清“已实现 / 演示或模拟 / 尚未实现”。

## 1. 项目基本信息

| 项目 | 说明 |
| --- | --- |
| 产品名称 | 面向用户的陪伴者叫 **Robo**；项目中文名常写“她律”；代码仓库名是 `she-runtime`，iOS target 是 `sheRuntime` |
| 一句话定位 | 一个长期和用户一起研究身体的伙伴：手表记录身体，她的话记录生活，Robo 把两者对上 |
| 不是什么 | 不是医生替代品，不是泛情绪陪聊，不是单纯展示 Apple Health 图表的工具 |
| 长期产物 | 身体说明书；高价值出口之一是“就医锦囊”。Robo 负责连续观察和整理，医生负责医学判断和诊断 |
| 主端 | iOS App（SwiftUI + SwiftData + HealthKit） |
| 问问服务 | Node.js / Express 服务，当前模型客户端为 DeepSeek，代码在 `server/app` |
| 硬件 | M5Stack StopWatch，代码在 `firmware/stopwatch`。本专项只消费它传来的麦克风音频；它不是额外生理传感器 |
| 页面 | 今日、地图、洞察/规律、问问、我的 |
| 团队角色 | Ginger = 产品；艾瑞（arieslx）= 开发负责人；小南 = 视觉；小花 + 石宝 = 营销/文案（以仓库 `CLAUDE.md` 为准） |

## 2. 产品去哪里看

### 2.1 看当前可运行产品

当前代码才是“已实现”的最高优先级事实。Xcode 工程：

`/Users/kongxueli/Desktop/coding/12-女性身体运行时/tmp/she-runtime-subjective-data-loop/apps/ios/sheRuntime/sheRuntime.xcodeproj`

构建方式：

```bash
cd '/Users/kongxueli/Desktop/coding/12-女性身体运行时/tmp/she-runtime-subjective-data-loop/apps/ios/sheRuntime'
xcodebuild -project sheRuntime.xcodeproj -scheme sheRuntime \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build CODE_SIGNING_ALLOWED=NO
```

主入口是 `sheRuntimeApp.swift`，页面框架是 `MainTabView.swift`。注意：仓库规则把 `MainTabView` 定义为临时脚手架，后续可能由开发负责人调整。

### 2.2 看产品原型和视觉

- 早期整体原型：`/Users/kongxueli/Desktop/coding/12-女性身体运行时/01-她律/02-产品方案/她律原型01.html`
- 高保真演示入口：`/Users/kongxueli/Desktop/coding/12-女性身体运行时/01-她律/09-设计/she-runtime-hifi/打开演示.html`
- 其余高保真文件：`/Users/kongxueli/Desktop/coding/12-女性身体运行时/01-她律/09-设计/she-runtime-hifi/`

原型可用来理解体感和视觉，但不能用来证明功能已经接通真实数据。

### 2.3 必读产品材料

以下文件在本专项开始时已完整阅读。新 Agent 仍需自己完整读取，不要只看本交接摘要：

1. `/Users/kongxueli/.claude/projects/-Users-kongxueli/sheruntime-backup/交接总文档.md`
2. `/Users/kongxueli/.claude/projects/-Users-kongxueli/memory/sheruntime-project.md`
3. `/Users/kongxueli/Desktop/coding/12-女性身体运行时/01-她律/07-AI创建的放这里/00-产品之锚_终点与不可妥协原则.md`
4. `/Users/kongxueli/Desktop/coding/12-女性身体运行时/01-她律/07-AI创建的放这里/01-AI行为规则.md`
5. `/Users/kongxueli/Desktop/coding/12-女性身体运行时/01-她律/07-AI创建的放这里/00-身体数据分析/主观数据采集方案v0.md`
6. `/Users/kongxueli/Desktop/coding/12-女性身体运行时/01-她律/07-AI创建的放这里/00-身体数据分析/苹果数据全景工作梳理.md`
7. `/Users/kongxueli/Desktop/coding/12-女性身体运行时/01-她律/07-AI创建的放这里/00-身体数据分析/10-规律解析引擎规格.md`
8. `/Users/kongxueli/Desktop/coding/12-女性身体运行时/01-她律/07-AI创建的放这里/13-规律引擎产品方案v1.md`
9. `/Users/kongxueli/Desktop/coding/12-女性身体运行时/01-她律/07-AI创建的放这里/16-zero-data-onboarding-design.md`
10. `/Users/kongxueli/Desktop/coding/12-女性身体运行时/01-她律/07-AI创建的放这里/17-Ginger原话需求与产品设计审查依据.md`
11. `/Users/kongxueli/Desktop/coding/12-女性身体运行时/01-她律/07-AI创建的放这里/19-规律四分类的产品与数据规则.md`

修改用户可见文案前，还必须完整读：

- `/Users/kongxueli/Desktop/coding/12-女性身体运行时/01-她律/07-AI创建的放这里/05-文案调性与语言风格.md`
- 仓库根目录的 `CLAUDE.md`

如果需要追查用户原话或文档冲突，按需查阅：

- `10-Ginger原话存档.md`
- `11-需求总清单-从你的180条原话提炼.md`
- `12-竞品分析-Ginger提供0828.md`
- `06-产品独特优势清单.md`
- Claude 历史：`/Users/kongxueli/.claude/projects/-Users-kongxueli/8f676ef4-5983-4419-bc01-657182c67f15.jsonl`

冲突时的优先级：**Ginger 最近原话 > 产品之锚 > 当前运行代码 > 旧交接文档/旧 Agent 结论**。

## 3. 仓库、分支和 worktree

| 项目 | 值 |
| --- | --- |
| GitHub | `https://github.com/arieslx/she-runtime.git` |
| 共享主工作目录 | `/Users/kongxueli/Desktop/coding/12-女性身体运行时/tmp/she-runtime` |
| 本专项独立 worktree | `/Users/kongxueli/Desktop/coding/12-女性身体运行时/tmp/she-runtime-subjective-data-loop` |
| 本专项分支 | `codex/subjective-data-loop` |
| GitHub 分支 | `https://github.com/arieslx/she-runtime/tree/codex/subjective-data-loop` |
| 功能实现 commit | `d2815114335251cad1041bf28b04e8e5384f2fb9` |
| commit 链接 | `https://github.com/arieslx/she-runtime/commit/d2815114335251cad1041bf28b04e8e5384f2fb9` |
| 是否已推送 | 是，只推到 `codex/subjective-data-loop` |
| 是否已合并 | 否 |
| 是否已建 PR | 否 |

### 3.1 重要的基线提醒

功能分支从本地 `feat/product-polish` 的 `84275e6` 切出，而交接时远端 `origin/feat/product-polish` 仍在 `ef13963`。本地基线比远端基线多 7 个 commit。

因此，**不要未审查就直接对远端 `feat/product-polish` 开 PR 并合并**，否则 PR 可能同时带出基线上其他人的 commit。接手开发需先确定最终目标基线：

- 如果团队就是要基于 `84275e6` 继续，可直接在当前分支审核。
- 如果必须对齐某个远端目标分支，请从那个明确的目标 commit 建新分支，优先 `cherry-pick d281511`，然后做语义级冲突审查。
- 不要对用户工作区执行 `reset --hard`、`checkout --` 或批量清理。

### 3.2 共享主工作目录的保护边界

共享目录 `/tmp/she-runtime` 交接时仍有用户和其他工作的未提交文件。尤其不得清理、覆盖、回退或提交：

- `apps/ios/sheRuntime/sheRuntime.xcodeproj/project.pbxproj`（用户签名/工程改动）
- `apps/ios/sheRuntime/sheRuntime/.!35594!copy_zh.json`（用户临时 copy 文件）

共享目录中还保留了一份本专项实现时产生的未提交重复改动。没有自动清理，是为了避免误伤用户正在进行的其他页面工作。**本专项的可审核版本以独立 worktree 中的 commit `d281511` 为准**。如需处理共享目录里的重复改动，必须先与 Ginger/开发负责人确认其中哪些仍是用户需要的改动。

## 4. 这个专项到底在做什么

这不是“再加一个输入框”，也不只是“做一个数据库”。

在修改前，用户说“我今天头痛，昨晚没睡好”，App 有可能只把它当成一次转写或一次对话。之后的 Ask 不知道这件事，规律引擎也不会真正使用它；系统甚至用固定假标签冒充 AI 理解结果。

本专项把这句话变成可追溯的一等数据：

```text
原始表达
  ↓
用户确认/修改后的原话
  ↓
结构化标注（当前无抽取服务时真实标为 pending）
  ↓
与同一本地日期的 HealthKit 客观数据对齐
  ↓
克制的事实/共现观察
  ↓
未来的重复观察、候选规律、用户确认/纠错
  ↓
未来的身体说明书/就医锦囊
```

当前实现已经走通到“事实/共现观察 + 证据下钻”，后三项还是后续任务。

### 对用户的直接变化

- 语音保存后，重启 App 仍存在。
- 用户可以改、隐藏、恢复显示或删除自己说过的话。
- 用户修改原话后，以前的 AI 标注会失效并回到待抽取，不会偷偷继续用旧结论。
- 隐藏或删除后，这条内容不再进入 Ask 上下文或主客观证据。
- Ask 可以使用最近、已确认的少量主观历史和近 28 天健康摘要，不再使用生产路径的模拟规律。
- 洞察页能展示“你说过的话”、发生时间、对齐的客观事实和证据来源。
- 如果数据不够，只告诉用户“这是一条事实/待观察”，不假装发现了规律。

### 如果没有这条链的风险

- Robo “记得用户”只是文案，无法在后续 Ask 和规律中真正使用。
- 假标签会把没有抽取的内容伪装成已理解，会直接损害信任。
- 用户撤回或纠错后，下游仍然使用旧内容，形成隐私和错误推断风险。
- Ask 如果发送多年原文，会越过最小必要的隐私边界；如果发送假上下文，又会给出伪个性化答案。
- 单条事件被说成“规律”或“原因”，会越过产品与医学安全边界。

## 5. 修改前的代码事实审计

这些是根据当时运行代码复核的结论，不是旧交接文档的转述：

1. `HealthDataAuthService.swift` 广泛枚举了约 200 个 HealthKit 对象类型，但 `HealthDataStore.swift` 真正长期落库的只有 11 个每日字段和 2 个小时字段。
2. 每日落库字段：睡眠时长、入睡时刻、HRV、静息心率、睡眠腕温、呼吸率、步数、经期布尔值、耳机时长、日照分钟、正念分钟；小时数据是平均心率和步数。
3. 旧有 `EvidenceEngine.swift` 具体配方使用睡眠时长/入睡、HRV、静息心率、腕温、经期、小时心率/步数。呼吸率、每日步数、耳机时长、日照、正念没有进入具体规律配方。
4. `SharedContracts.swift` 早已有 `SubjectiveNote`，`HealthDataStore.swift` 早已有 `SubjectiveNoteEntity/addNote`，但 UI 没有真正调用；`EvidenceEngine` 的 `notes` 参数仅影响 `hasAnyData`，不参与规律。
5. App 主 SwiftData 容器中的 `TimelineRecord` 保存语音原转写、确认文本、时间、来源、时长、隐藏/删除状态；它与 `HealthDataStore` 是两个数据岛。
6. iPhone 语音和 StopWatch 语音用固定 `mockTags`；音频转写后删除。StopWatch 当时只是麦克风录音入口。
7. 今日页精力五档只是 `@State`，不持久化；页面还混有 mock events。精力五档持久化本身不是本专项完成项。
8. Ask 原先只发送 `message/locale/timezone`，不保存对话历史，不携带真实健康/语音上下文；服务端生产路径从 `mockAskContext.js` 注入模拟规律。
9. 数据隐私页和规律页走两条不一致的 HealthKit 授权路径。这个问题仍在，但本专项没有扩张为 HealthKit 全量重构。
10. 不得对外声称“HealthKit 已全量读取并存储”；当前代码不支持这个结论。

## 6. 已经实现的最小纵切

功能实现都在 commit `d281511`，共修改 26 个文件，约 2223 行新增、114 行删除。

### 6.1 统一的主观事件契约

新增 `SubjectiveEvent.swift`，包含：

- 原话、确认文本、事件时间、时区、入口来源。
- 确认状态、抽取状态、版本、置信度、标注确认状态。
- 语义维度容器：身体感受/症状、情绪、认知状态、行为事件、环境情境、周期相关、用药/就医线索和 unknown。
- 旧数据适配和单向迁移；旧的固定 mock tags 会被清理为 `pending`，不伪装成真实抽取结果。

为了降低 SwiftData 迁移风险，版本化元数据暂时编码在现有 `TimelineRecord.tagsData` 中，没有增加一批新 SwiftData 列。这是最小纵切的兼容策略，不代表永久模型已定稿。

### 6.2 语音入口

- iPhone 今日语音保留真实录音时间，保存的文本是已确认/已修改，不再写固定假标签。
- StopWatch 目前只有手机收到时间，因为硬件没有提供原始采集时间戳；所以记为未审阅 + 待抽取。
- 音频仍是临时文件，转写后删除。StopWatch 保存失败时会删除已插入的不完整对象。

### 6.3 今日页的用户控制

- 真实用户路径只显示真实事件；演示数据只在显式 demo mode 中显示。
- 可查看全部主观历史。
- 可修改、隐藏、恢复显示、删除。
- 修改时 `revision + 1`，确认状态改为 corrected，旧抽取版本/置信度/标注被清除，回到 pending。

### 6.4 Onboarding 和 Ask 的进入规则

- Onboarding 用户自己的回答会保存为主观历史。
- Ask 中表达自己当前状态、经历或个人假设的内容可保存。
- 普通问题不保存为身体事实。
- 助手回答永远不保存为用户事实。
- 当前使用可测试的本地分类规则，而不是把每条 Ask 输入都当主观数据。接手人要专门审查边界样例和误判率。

### 6.5 Ask 的真实、最小化上下文

iOS 新增 `AskContextBuilder.swift`，只向服务端发送：

- 当前这次问题。
- 最近 90 天中最多 12 条、已确认/已修正、没有被隐藏/删除的主观事件。
- 每条确认文本最长 240 字符。
- 近 28 天 HealthKit 摘要。
- 最多 8 个已由用户确认/修正的标注。

不发送原始音频，不发送 raw transcript，不整包发送多年原文，不发送未审阅的 StopWatch 转写。

服务端新增 `requestAskContext.js`，生产路径不再从 `mockAskContext.js` 取个人规律。请求契约会二次校验白名单、数量、文本长度、确认状态和允许的健康指标。Ask 回答中的来源可追溯到主观事件 ID/版本和健康摘要。

### 6.6 主客观时间对齐和证据下钻

`EvidenceEngine.computeSubjectiveAlignments` 已真正消费主观记录：

- 使用事件自带时区，对齐到同一个本地日历日的客观数据。
- 没有可用客观数据时，输出 `factOnly`。
- 有同日客观数据时，只输出 `cooccurrence`。
- 不升级为规律、置信等级或因果结论。
- 来源 ID 包含事件 ID 和 revision，并保留时间窗口、分析版本和客观事实，用于证据下钻和后续重算。

洞察页已增加“你说过的话”与证据下钻界面。

### 6.7 演示与真实路径隔离

- Today 真实历史不再默认混入 mock events。
- `mockAskContext.js` 可保留用于演示/测试，但生产 Ask service 已不导入它。
- 不要为了方便截图把 mock 数据重新接回真实用户路径。

## 7. 关键代码地图

### 7.1 数据契约和持久化

- `apps/ios/sheRuntime/sheRuntime/SubjectiveEvent.swift`
  - `SubjectiveRecordMetadata`
  - `SubjectiveEvent`
  - `SubjectiveEventAdapter`
  - `SubjectiveInputClassifier`
  - `SubjectiveEventWriter`
  - `SubjectiveLegacyMigrator`
- `apps/ios/sheRuntime/sheRuntime/TimelineRecord.swift`
  - 主 SwiftData 容器中的长期主观原话记录
  - `applyConfirmedTextEdit`负责修改传播和派生结果失效
- `apps/ios/sheRuntime/sheRuntime/SharedContracts.swift`
  - `SubjectiveNote`和 `SubjectiveObjectiveAlignment` 等引擎边界契约
- `apps/ios/sheRuntime/sheRuntime/HealthDataStore.swift`
  - 客观 HealthKit 长期数据容器和主观适配入口

### 7.2 采集入口与编辑

- `apps/ios/sheRuntime/sheRuntime/VoiceCaptureViewModel.swift`
- `apps/ios/sheRuntime/sheRuntime/StopWatchAudioPipelineService.swift`
- `apps/ios/sheRuntime/sheRuntime/TodayView.swift`
- `apps/ios/sheRuntime/sheRuntime/OnboardingGuidanceView.swift`
- `apps/ios/sheRuntime/sheRuntime/AskView.swift`
- `apps/ios/sheRuntime/sheRuntime/MainTabView.swift`

### 7.3 Ask 真实上下文

- `apps/ios/sheRuntime/sheRuntime/AskContextBuilder.swift`
- `apps/ios/sheRuntime/sheRuntime/AskChatClient.swift`
- `apps/ios/sheRuntime/sheRuntime/AskChatViewModel.swift`
- `server/app/src/context/requestAskContext.js`
- `server/app/src/contracts/askContract.js`
- `server/app/src/services/askService.js`
- `server/app/src/prompts/askSystemPrompt.js`
- `server/app/src/context/mockAskContext.js`（仅演示/测试，不得重新接入生产路径）

### 7.4 规律引擎与证据界面

- `apps/ios/sheRuntime/sheRuntime/EvidenceEngine.swift`
- `apps/ios/sheRuntime/sheRuntime/InsightsView.swift`
- `apps/ios/sheRuntime/sheRuntime/EngineInsightsView.swift`

### 7.5 测试

- `apps/ios/sheRuntime/sheRuntimeTests/SubjectiveDataTests.swift`
- `server/app/test/askContract.test.js`
- `server/app/test/askService.test.js`

## 8. 已验证的结果

以下验证已在独立 worktree 中运行：

### iOS 构建

```bash
cd apps/ios/sheRuntime
xcodebuild -project sheRuntime.xcodeproj -scheme sheRuntime \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build CODE_SIGNING_ALLOWED=NO
```

结果：通过。

### 主观链路定向测试

定向运行：

- `SubjectiveDataContractTests`
- `SubjectiveEvidenceAlignmentTests`
- `AskCompactContextTests`

结果：3 个 suite，12 个 test 全部通过。

### Node 服务端

```bash
cd server/app
npm install --no-package-lock --no-audit --no-fund
npm test
```

结果：8/8 通过。

### 静态检查

- `jq empty apps/ios/sheRuntime/sheRuntime/copy_zh.json`：通过
- `jq empty apps/ios/sheRuntime/sheRuntime/copy_en.json`：通过
- `git diff --check`：通过
- Simulator App：已启动验证

### 已知的全量测试问题

全量 iOS test suite 尚未全绿，已观察到：

- 未修改的 `DailyHealthSummaryLogicTests` 存在浮点精确相等失败，并伴随 Simulator host 重启。
- 排除上述 suite 后，`EnergyMapViewModelHealthSummaryTests.rapidDateChanges...` 也有浮点精确相等失败。
- Simulator 使用 `CODE_SIGNING_ALLOWED=NO` 时会记录 HealthKit entitlement 缺失，属此构建方式的预期限制。
- `HealthDataStore` 中既有 Swift 6 actor-isolation warnings 在本专项前已存在。

这些问题不能被说成“主观链路测试失败”，但也不能隐瞒。接手开发需先单独复现并判断是环境、旧测试或新整合问题，不要直接为了全绿而放宽所有断言。

## 9. 尚未实现，不要误报为已完成

1. 真实 AI 语义抽取服务。当前正确状态是 pending，不是“已识别”。
2. AI 抽取标签/实体的用户确认和纠错 UI。
3. 多次主观事件发展为候选规律，以及候选规律的用户确认/纠错。
4. 周回顾。
5. Ask 对话历史长期持久化。
6. 完整的身体说明书和就医锦囊。当前只留了稳定、可追溯的证据输出边界。
7. HealthKit 约 200 种授权类型的全量读取和全量持久化。
8. 数据隐私页与规律页 HealthKit 授权路径的统一。
9. StopWatch 原始采集时间戳；当前只能使用手机收到时间。
10. 生产服务端部署和真机完整 QA。
11. 对其他并行功能分支的最终 rebase/merge 和语义级冲突处理。

## 10. 并行开发的冲突风险

这个功能虽然在独立分支和 worktree，不会直接覆盖用户的其他页面工作，但合并时仍有语义冲突。交接时已知高重叠区域：

- `codex/personal-pattern-skill`：Ask iOS、Ask server、文案 JSON 高重叠。
- `codex/voice-dock-listening-flow`：`MainTabView`、`TodayView`、`VoiceCaptureViewModel`、文案 JSON 重叠。
- `codex/tab-labels`、`codex/fix-keyboard-tabbar`：`MainTabView`、文案以及部分编辑面板重叠。

开发审核时不能只看 Git 是否出现 conflict marker，还要检查：

- Ask 会不会重新遗失真实 context，或重新导入 mock context。
- Voice/今日页新流程会不会绕过 `SubjectiveEventWriter`。
- 编辑、隐藏、删除后是否仍能撤回下游 context 和 evidence。
- JSON 合并后中英键是否仍同步，是否保留产品文案原则。
- `MainTabView` 脚手架被替换后，SwiftData `modelContext`、Ask context provider 和历史编辑入口是否仍注入成功。

## 11. 接手后的建议顺序

### 第一阶段：审核当前最小纵切

1. 确认独立 worktree 没有未提交改动。
2. 阅读 `git show d281511`，逐文件审查，不只看 diff stat。
3. 按第 12 节的手动用例走一遍，尤其是重启持久化、Ask 分类边界和编辑/隐藏/删除传播。
4. 重跑定向 iOS test 和 server test。
5. 根据团队实际目标分支，决定是在当前分支继续还是 cherry-pick 到新基线。

### 第二阶段：先补足“可上线”缺口

1. 真机验证 iPhone 录音、StopWatch 收音、SwiftData 持久化和 HealthKit 读取。
2. 运行 Ask 真实 server 端到端 QA，核对实际发送的 JSON 确实符合最小化边界。
3. 对 Ask 输入分类补充中文口语、否定句、引用他人、假设性问句、医学知识问题的正反例。
4. 审查删除是硬删除还是需要用户可恢复的软删除；这是可能改变产品体感和合规边界的选择，必须与 Ginger/开发负责人确认。
5. 解决目标分支的语义冲突，重新跑全部定向测试和构建。

### 第三阶段：下一个产品纵切

建议下一刀是“真实抽取 + 用户确认标注 + 编辑后重算”，而不是直接做完整身体说明书。最小产品边界是：

1. 抽取器只输出版本化、带置信度、可用 unknown 表示的候选标注。
2. 抽取失败保留原文并继续 pending，不伪造结果。
3. 用户能用一个轻量界面确认/修正/拒绝标注，不填重表单。
4. 只有用户确认或修正过的标注才能进入 Ask 和后续候选规律。
5. 原话修改、隐藏、删除后，必须用事件 ID + revision 使旧标注和证据失效，并可验证重算。

在抽取器之前需产品明确的少数选择：是否调用云端模型、发送哪一层文本、用户在哪里看到并撤回授权、敏感类别是否默认不出本地。这些不能由开发或 Agent 自行扩大权限。

## 12. 最低手动验收场景

新 Agent/开发完成审核时，至少要能现场演示以下场景：

### 场景 A：今日语音闭环

1. 在今日页说“我今天头有点痛，昨晚睡得很晚”。
2. 检查转写并修正文字，然后保存。
3. 完全退出并重启 App，记录仍存在。
4. 在历史中修改文本，确认 revision 增加、旧标注失效。
5. 在洞察中看到原话、时间、同日客观事实或“待观察”。
6. 隐藏该条记录，它不再进入 Ask context/evidence；恢复显示后重新进入。
7. 删除后，它不再出现，下游也不得继续引用。

### 场景 B：Ask 分类边界

1. 输入“我这两天都很困”：可进入主观历史。
2. 输入“HRV 是什么？”：不得进入主观历史。
3. 助手回答“这可能与睡眠有关”：绝不得保存为用户事实。
4. 检查发送给 server 的 payload：只有最近有效的已确认原话和 28 天摘要，没有音频、raw transcript、隐藏/删除记录、未审阅 StopWatch 文本或 mock 规律。
5. 检查 Ask 回答的来源，可追溯到事件 ID/版本或健康摘要。

### 场景 C：StopWatch 边界

1. StopWatch 语音转写保存后重启仍存在。
2. 没有硬件采集时间戳时，UI/契约不得假装知道原始发生时间。
3. 未审阅文本不得进入 Ask/evidence。
4. 转写后临时音频已删除。

### 场景 D：数据不足

1. 只有一条主观记录、没有同日客观数据：只展示事实/待观察。
2. 有同日客观数据：最多只说共现，不说因果。
3. 不得因为有一条主观记录就生成“你的规律”。

## 13. 产品和开发各自负责什么

### Ginger/产品需要决定

- 用户在哪里看到“Robo 记住了什么”，以及如何撤回。
- 主观原话、AI 标注、共现观察三层分别用什么人话展示。
- AI 抽取是否可发送到云端，哪些敏感类别必须留在本地，用户如何知情和撤回。
- “删除”是立即不可恢复，还是需要回收站/犹豫期。
- 候选规律什么时候才值得打扰用户，用户怎么说“对/不对/可能”。

产品不需要自己设计 SwiftData 表、API schema 或合并代码。

### 开发负责人需要完成

- 审核数据模型、迁移策略、并发/事务边界、删除传播和隐私边界。
- 确定最终 Git 基线，处理并行分支的语义冲突，开 PR 并组织 review。
- 完成真机验证、生产 server 验证、全量回归和部署。
- 如继续下一纵切，实现真实抽取服务、用户确认 UI 和可验证的重算机制。

### AI 在本专项已经做到哪里

- 完成产品材料与当前代码的交叉审计。
- 完成一条从真实入口、持久化、用户编辑/撤回、Ask 最小上下文到主客观对齐和证据下钻的最小纵切。
- 完成定向 iOS/server 测试、iOS 构建和独立分支推送。
- 没有替团队做最终架构签字、产品隐私决策、PR 合并、真机全回归或生产部署。

## 14. 可直接复制到新会话的 Prompt

```text
你接手 Robo / sheRuntime 的“主观数据闭环”专项。

请先完整阅读交接文档：
/Users/kongxueli/Desktop/coding/12-女性身体运行时/tmp/she-runtime-subjective-data-loop/docs/subjective-data-loop-handoff.md

独立代码 worktree：
/Users/kongxueli/Desktop/coding/12-女性身体运行时/tmp/she-runtime-subjective-data-loop

分支：codex/subjective-data-loop
已实现功能 commit：d2815114335251cad1041bf28b04e8e5384f2fb9
GitHub：https://github.com/arieslx/she-runtime/tree/codex/subjective-data-loop

你的第一阶段任务不是重写，而是：
1. 读完仓库 CLAUDE.md 和交接文档列出的必读产品材料。
2. 审查 d281511 的 26 个文件，复核数据契约、迁移、编辑/隐藏/删除传播、Ask 最小上下文和主客观对齐。
3. 重跑定向 iOS 测试、server 测试和 iOS 构建。
4. 按交接文档第 12 节走完手动验收场景。
5. 查明团队当前最终目标分支，不要直接将当前分支合并到 main。如目标基线不是 84275e6，优先从正确基线建新分支并 cherry-pick d281511。
6. 不要清理共享工作目录里用户的 project.pbxproj、临时 copy 文件或任何不相关未提交改动。

请先给 Ginger 一份大白话状态汇报：已实现什么、用户会有什么变化、尚未实现什么、当前最大风险是什么。然后继续技术审核和验证。如果发现会显著改变产品方向且无法从材料判断的选择，再向 Ginger 说明选项、用户体感和风险，不要自行扩大权限。
```

## 15. 交接完成标准

新接手人能清楚回答以下问题，才算真正接手：

1. 用户说的一句话现在存在哪里，怎样和 HealthKit 对齐？
2. 为什么 Ask 不能把助手回答或普通问题当成用户事实？
3. 用户修改、隐藏、删除原话后，哪些下游结果必须失效？
4. 当前什么是真数据，什么是 demo/mock，什么还没实现？
5. 为什么单条记录最多只能形成事实或共现，不能形成规律、原因或医学结论？
6. 为什么当前分支不应该未审核就直接对远端产品分支开 PR？
7. 下一个最小纵切的产品选择和技术缺口分别是什么？
