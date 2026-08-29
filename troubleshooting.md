# SheRuntime Troubleshooting

本文档按阶段记录 Ask Service 连接与 Chatbot 分层架构的排查、修复任务、测试结果和验收步骤。每个阶段完成后暂停，获得确认后才进入下一阶段。

## 阶段 0：现状检查（2026-08-29）

状态：检查完成，等待确认；未修改应用、服务端或部署代码。

### 仓库与工作区

- 当前分支：`chore/stopwatch`
- 当前提交：`b951cae update chatbot`
- 工作区检查前为干净状态。
- 当前 HEAD 比本地 `main` 多 3 个提交；本地 `main` 位于 `f9bb2ce`。本阶段没有 fetch、切分支或改写 Git 状态，因此未从本地信息验证远端 `main` 是否已经包含 PR #10。

### 当前真实调用链

```text
AskView
→ AskChatViewModel.send
→ RemoteAskChatClient.ask
→ POST configured Ask endpoint
→ Node /api/ask
→ parseAskRequest
→ getMockAskContext
→ knowledgeSearch.search
   → 本地知识检索
   → 若配置在线 endpoint，则继续在线检索
→ DeepSeek（每次请求无条件调用）
→ JSON.parse + normalizeAskResponse
→ iOS AskChatResponse
```

当前架构不是“本地优先”：iOS 不查询个人本地数据库或 App 内置知识后直接作答；请求先进入 Node，Node 使用模拟个人上下文，随后无条件调用 DeepSeek。

### 1. iOS Ask endpoint 来源和优先级

入口位于 `apps/ios/sheRuntime/sheRuntime/AskChatClient.swift` 的 `AskChatConfig.configuredEndpointString()`。

读取优先级从高到低为：

1. `ProcessInfo.processInfo.environment["ASK_CHAT_ENDPOINT"]`（运行进程/Xcode Scheme 环境变量）
2. `UserDefaults.standard["AskChatEndpoint"]`
3. App `Info.plist` 的 `AskChatEndpoint`
4. 硬编码 fallback：`http://127.0.0.1:3000/api/ask`

`Info.plist` 值由 Xcode build setting `INFOPLIST_KEY_AskChatEndpoint = "$(ASK_CHAT_ENDPOINT)"` 生成。仓库没有 `.xcconfig`，共享 Scheme 中也没有可见的 endpoint 环境变量配置；未展开的 `$(...)` 和空值会被过滤，最终进入 loopback fallback。

真机上的 `127.0.0.1` 指向 iPhone 本身，不是开发 Mac，因此 Mac 上的 Node Service 无法通过该默认地址访问。这是当前连接失败的最可能原因。

### 2. Node Service 网络配置

- 默认监听 host：`0.0.0.0`
- 默认 port：`3000`
- Ask：`POST /api/ask`
- Health：`GET /api/health`
- 默认公开地址字符串：`http://localhost:3000`
- 可通过 `HOST`、`PORT`、`ASK_SERVER_BASE_URL` 修改。

`/api/health` 当前返回：服务状态、公开 Ask/Health endpoint、监听 host/port、DeepSeek 是否配置、base URL、model 和 timeout；不返回 API Key。

### 3. 当前 `/api/ask` 协议

请求：

```json
{
  "message": "用户问题，trim 后最多 1000 字符",
  "locale": "zh-CN",
  "timezone": "Asia/Shanghai"
}
```

响应：

```json
{
  "answer": "...",
  "basis": [{ "label": "...", "value": "..." }],
  "safety_note": "...",
  "follow_up": "...",
  "usage": { "deepseek_call_count": 1 },
  "sources": [
    {
      "source_id": "...",
      "source_type": "...",
      "label": "...",
      "path": "...",
      "url": "...",
      "status": "...",
      "detail": "..."
    }
  ]
}
```

当前没有 `request_id`、`compact_context` 客户端输入、route/call-path 字段或严格响应 schema 校验。

### 4. 虚构个人数据

`server/app/src/context/mockAskContext.js` 会把以下内容作为 `compact_context` 交给模型：

- `user_window: last_28_days`
- “今天恢复状态接近个人基线”
- 3 场会议、共 152 分钟、时间段 13:40–17:10
- “连续沟通超过 90 分钟后精力下降更常出现”，样本量 8
- “独处步行 15–30 分钟后状态改善更常出现”，样本量 8

这些是虚构个人事实，不只是 UI 演示数据；当前服务默认使用该 provider，存在被模型当成真实用户数据回答的高风险。

### 5. 本地知识、在线知识和 DeepSeek 行为

- 本地与在线检索是串行执行：先加载/排序本地结果，再等待在线检索。
- 只要配置了 `ASK_ONLINE_KNOWLEDGE_ENDPOINT`，每次知识搜索都会调用在线 endpoint，不判断本地结果是否足够。
- 合并逻辑是 `[...localHits, ...onlineHits].slice(0, limit)`。当本地结果已占满 limit 时，在线调用已经发生，但在线结果会被尾部 `slice` 丢弃。
- 每次合法 `/api/ask` 请求都会调用 DeepSeek，没有确定性本地回答路径。
- `ASK_ONLINE_KNOWLEDGE_ENDPOINT` 只是一个通用 HTTP POST adapter。仓库没有具体供应商、真实 Function Tool、鉴权、白名单或 provider 部署配置；未设置环境变量时在线搜索为 disabled/null。

### 6. 部署现状

仓库中未发现 Dockerfile、Docker Compose、Caddyfile、Vercel/Fly/Render 或其他服务部署配置。当前 README 只描述本机 Node 启动和局域网连接。

### 按严重程度排序的问题

#### P0

1. iOS fallback 使用 `127.0.0.1`，真机必然连接到自身，而不是 Mac。
2. Node 默认把 `mockAskContext.js` 中的会议、恢复状态和个人规律作为真实上下文交给模型，可能生成虚假的个体结论。

#### P1

3. 所有 Ask 请求无条件调用 DeepSeek，不存在本地确定性回答。
4. 配置在线搜索后每次无条件调用；本地结果占满 limit 时，在线结果可能在已付出调用成本后被丢弃。
5. 在线知识只是未绑定真实供应商的通用 endpoint adapter，不是已验证的 Function Tool/API。
6. `/api/ask` 上游异常统一映射为 502，并把原始 error message 放进 `detail`，错误分类和敏感信息控制不足。
7. 模型响应只做 `JSON.parse` 和宽松 normalization，缺少严格 schema 验证。

#### P2

8. 没有 Ask endpoint 配置优先级、endpoint 合法性或真机配置测试。
9. 没有“空真实上下文不得生成模拟数据”的测试。
10. `deepseek_call_count` 是进程内全局计数，重启即丢失，不适合作为正式用量统计。
11. 尚无公网部署、鉴权、限流和安全配置。

### 测试结果

#### Node

命令：

```bash
cd server/app
pnpm test
```

结果：6/6 通过。

- Health endpoint：通过
- 请求 contract：3 项通过
- Ask service：通过
- 本地知识检索：通过

首次在受限沙箱内运行时，Health 测试因无法监听 `0.0.0.0` 报 `EPERM`；允许本机临时端口监听后全部通过，属于运行环境限制，不是代码失败。

#### iOS

完整 Scheme 测试构建成功，基础 UI 启动测试曾通过，但 UI 测试执行器随后长时间等待并被终止。单独运行 `sheRuntimeTests` 的结果：9 通过、14 失败。

失败集中在既有 Energy Map 和 Daily Health Summary 测试，多项以 0 秒立即失败；当前测试文件没有 Ask endpoint 或 AskChatClient 测试。本阶段未修改或修复这些非 Ask 测试。

### 当前真机检查步骤（只验证现状）

1. Mac 在 `server/app` 启动 Node，并确认 `.env` 使用 `HOST=0.0.0.0`。
2. 在 Mac 执行 `curl http://<Mac局域网IP>:3000/api/health`。
3. 在 Xcode Scheme 设置 `ASK_CHAT_ENDPOINT=http://<Mac局域网IP>:3000/api/ask`。
4. 确保 iPhone 和 Mac 在同一局域网，并允许 App 的本地网络权限。
5. App Ask 页面执行健康检查，核对页面展示的实际 endpoint。
6. 删除 Scheme endpoint 后重启 App，可复现 fallback 为 `127.0.0.1` 导致的真机连接失败。

### 后续阶段预计修改文件

阶段 1 预计：

- `apps/ios/sheRuntime/sheRuntime/AskChatClient.swift`
- `apps/ios/sheRuntime/sheRuntimeTests/sheRuntimeTests.swift`，或新增 Ask 专用测试文件
- Debug/Release `.xcconfig`（新增，具体生产 endpoint 由配置注入）
- `server/app/src/context/mockAskContext.js`（隔离或移除默认真实路径）
- `server/app/src/services/askService.js`
- `server/app/test/askService.test.js`
- `server/app/test/app.test.js`
- `server/app/README.md`

阶段 2 预计：

- iOS 现有本地存储/模型与上下文提取器（需先确认实际存储方式）
- `AskChatClient.swift`、Ask request/response models
- `server/app/src/contracts/askContract.js`
- Ask contract/service tests

阶段 3 预计：

- 新增 iOS 本地请求分类器与确定性回答器
- `AskChatViewModel.swift`
- Node `askService.js`、knowledge search 和 route contract
- iOS/Node 路由测试

阶段 4 预计：

- `server/app/src/services/onlineKnowledgeSearch.js`，或拆分 Provider 接口和 disabled provider
- `server/app/src/config/env.js`
- provider mock tests 和 README

阶段 5 预计：

- `server/app/src/services/deepseekClient.js`
- Ask response schema、错误映射和相关 tests
- `usageCounter.js` 的正式替代方案需另行确定

阶段 6 预计：

- Express 鉴权、限流、日志和安全中间件
- 对应配置、测试及部署说明

### 阶段 0 完成任务

- [x] 阅读 `AGENTS.md`、`CLAUDE.md` 和 Ask Server README。
- [x] 检查分支、工作区和现有实现。
- [x] 解析 iOS endpoint 来源与优先级。
- [x] 解析 Node host、port、health、Ask contract。
- [x] 确认模拟个人数据、知识检索和 DeepSeek 调用行为。
- [x] 检查在线 provider 与部署文件现状。
- [x] 运行 Node 测试和可运行的 iOS 测试。
- [x] 输出当前调用链、连接失败原因、问题等级和后续文件范围。
- [x] 已确认“通过，进入下一阶段”。

## 阶段 1：连接配置与假数据修复（2026-08-29）

状态：代码与自动测试完成，等待真机验收和进入阶段 2 的确认。

### 已完成问题

1. 删除 iOS 的 `127.0.0.1` 默认 fallback。环境变量、UserDefaults 和 Info.plist 都没有有效配置时，现在保持“未配置”并给出明确排查提示。
2. 保留配置优先级：Xcode Scheme 环境变量 → UserDefaults → Info.plist build setting。
3. Debug 只允许：
   - HTTPS；或
   - 显式配置的 RFC 1918 局域网 HTTP 地址（`10/8`、`172.16/12`、`192.168/16`）及 `.local` host。
4. Debug 拒绝 `127.0.0.1` 和公网明文 HTTP，避免真机再次误连自身或明文访问公网。
5. Release 只接受 HTTPS，生产域名通过 `ASK_CHAT_ENDPOINT` build setting 注入，没有硬编码私人域名。
6. endpoint 无效时，错误包含当前 endpoint 和 Debug/Release 对应的配置建议；新增界面文案已同步进入中英文 JSON。
7. Node 默认 context provider 从 `mockAskContext` 切换为 `emptyAskContext`。
8. 没有真实个人数据时，默认上下文为：
   - `user_window: null`
   - `today: {}`
   - `recent_records: []`
   - `patterns: []`
9. `mockAskContext.js` 被明确标记为 demo fixture，生产 AskService 不再引用；本地知识检索仍保留，不被误删为个人数据。
10. `/api/health` 保持可用，继续返回服务 endpoint、监听地址和 DeepSeek 配置状态，不泄露 API Key。
11. 没有扩大 ATS：仍只使用现有 `NSAllowsLocalNetworking`，没有启用全局任意加载。

### 修改文件

- `apps/ios/sheRuntime/sheRuntime/AskChatClient.swift`
- `apps/ios/sheRuntime/sheRuntime/copy_zh.json`
- `apps/ios/sheRuntime/sheRuntime/copy_en.json`
- `apps/ios/sheRuntime/sheRuntimeTests/sheRuntimeTests.swift`
- `server/app/src/context/emptyAskContext.js`（新增）
- `server/app/src/context/mockAskContext.js`
- `server/app/src/services/askService.js`
- `server/app/test/askService.test.js`
- `server/app/README.md`
- `troubleshooting.md`

没有修改 `project.pbxproj`，符合工程文件夹自动同步约定。

### 核心逻辑

#### iOS endpoint

```text
ASK_CHAT_ENDPOINT 环境变量
→ AskChatEndpoint UserDefaults
→ AskChatEndpoint Info.plist / build setting
→ 未配置（不再 fallback）
```

配置解析和 URL 安全验证已拆成可测试的纯逻辑。Health endpoint 继续从合法 Ask endpoint 的同级路径推导为 `/api/health`。

#### Node 空个人上下文

```text
/api/ask
→ emptyAskContext
→ 空 personal fields + 可匹配的本地知识
→ DeepSeek（阶段 1 暂不改变调用策略）
```

阶段 1 只消除虚构数据；“本地优先、按需调用 DeepSeek”留到阶段 3，不提前实现。

### 自动测试结果

#### Node

```bash
cd server/app
pnpm test
```

结果：7/7 通过。

新增覆盖：默认上下文不包含 152 分钟会议、`continuous-communication-drain` 或任何模拟个人记录。

#### iOS Ask 配置测试

```bash
xcodebuild -project apps/ios/sheRuntime/sheRuntime.xcodeproj \
  -scheme sheRuntime \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  test -only-testing:sheRuntimeTests/AskChatConfigTests \
  CODE_SIGNING_ALLOWED=NO
```

结果：4/4 通过。

覆盖：

- 环境变量、UserDefaults、Info.plist 优先级。
- 空值和未展开 build setting 不回退 loopback。
- Debug 允许局域网 HTTP/HTTPS，拒绝公网 HTTP 和 `127.0.0.1`。
- Release 拒绝 HTTP，只接受 HTTPS。

#### iOS 构建

- Debug 真机目标：通过。
- Release 真机目标：通过。
- 存在既有 AppIcon/AppLogo asset warning，本阶段未修改这些资源。

### 真机验收步骤

1. Mac 与 iPhone 连接同一局域网。
2. 在 `server/app/.env` 配置：

   ```env
   HOST=0.0.0.0
   ASK_SERVER_BASE_URL=http://<Mac局域网IP>:3000
   ```

3. 启动服务：

   ```bash
   cd server/app
   pnpm start
   ```

4. Mac 验证：

   ```bash
   curl http://<Mac局域网IP>:3000/api/health
   ```

5. Xcode Debug Scheme 设置：

   ```text
   ASK_CHAT_ENDPOINT=http://<Mac局域网IP>:3000/api/ask
   ```

6. 安装到 iPhone，允许本地网络权限，在 Ask 页面运行健康检查。
7. 确认页面显示的 endpoint 是 Mac 局域网地址，健康状态正常。
8. 删除 Scheme endpoint、清除可能存在的 `AskChatEndpoint` UserDefaults 后重启 App；确认页面显示 endpoint 未配置及明确排查建议，不再出现 `127.0.0.1`。
9. 尝试配置 `http://公网域名/api/ask`，确认 Debug 拒绝；Release 包使用 HTTP 时也应拒绝。
10. 调用 Ask 后检查 Node 输入上下文，确认个人字段为空，不出现会议次数、152 分钟或两条模拟规律。

### 已知边界

- 当前没有实际生产域名，因此 Release 只实现安全配置入口和 HTTPS 校验，不内置默认生产 URL。
- 真机局域网健康检查需要用户现场网络和 Xcode Scheme 配置，本机自动测试无法替代。
- 阶段 1 尚未传输真实 iOS 本地个人数据；这是阶段 2 的任务。
- 当前仍会调用 DeepSeek，这是阶段 3/5 的后续工作，不在本阶段提前改变。

### 阶段 1 完成任务

- [x] 移除真机错误 loopback fallback。
- [x] 区分 Debug 局域网 HTTP 与 Release HTTPS 安全规则。
- [x] 增加 endpoint 优先级和合法性测试。
- [x] 生产路径移除模拟个人上下文。
- [x] 增加空上下文无假数据测试。
- [x] 保留并验证健康检查。
- [x] 更新 Ask Server README。
- [x] 运行 Node、iOS Ask 测试和 Debug/Release 构建。
- [x] 完成 iPhone 真机健康检查。
- [x] 用户确认阶段 1 通过。

### 真机验收记录（2026-08-29 07:33）

结论：阶段 1 暂不通过，不进入阶段 2。

截图证据：

- 健康检查卡显示 `she-runtime-ask-server`、`DeepSeek 已配置` 和 `deepseek-v4-flash`，说明 iPhone 已能通过局域网访问 Node 的 `/api/health`。
- Ask 错误明确显示实际客户端 endpoint 为 `http://192.168.6.229:3000/api/ask`，说明 Debug Scheme/LAN endpoint 配置已生效，App 没有回退到 `127.0.0.1`。
- Ask 请求返回 `The request timed out`，说明 12 秒 iOS 请求时限内没有收到 `/api/ask` 响应。健康检查成功只能证明 Node 可达，不能证明 DeepSeek 完整 Ask 链路能在客户端时限内完成。
- 健康卡显示的服务公开 endpoint 仍是 `http://localhost:3000/api/ask`。这是 Node 的 `ASK_SERVER_BASE_URL` 配置值，不是 iPhone 实际使用的 endpoint；说明服务端 `.env` 仍可能使用 localhost，健康信息具有误导性。

通过阶段 1 前需要再次确认：

1. `server/app/.env` 使用 `ASK_SERVER_BASE_URL=http://192.168.6.229:3000` 后重启 Node。
2. 健康卡公开 endpoint 显示 `http://192.168.6.229:3000/api/ask`。
3. 记录 Node 收到 `POST /api/ask` 的时间、返回状态和总耗时。
4. 从 Mac 对同一个 LAN endpoint 执行 `/api/ask`，记录完整耗时，而不只是确认 DeepSeek API 单独可访问。
5. iPhone Ask 请求在当前客户端 12 秒 timeout 内成功，或基于实测耗时再决定是否调整 timeout。未经测量不直接增大 timeout。

### 真机复验结果（2026-08-29）

结论：阶段 1 通过。

- 服务端已配置 `ASK_SERVER_BASE_URL=http://192.168.6.229:3000`。
- iPhone Ask 请求已成功返回，不再出现超时。
- 返回过程显示 LLM 推理，并确认本次请求仅调用大模型一次。
- 已验证完整链路：iPhone → 局域网 Ask Server → DeepSeek → Ask Server → iPhone。
- 本记录仅确认阶段 1 验收结果；尚未开始阶段 2。

## 阶段 2：请求协议与 iOS 最小本地上下文

### 存储检查

- App 已使用 SwiftData，持久化容器在 `sheRuntimeApp.swift` 中创建。
- 当前唯一适合 Ask 使用的真实个人记录模型是 `TimelineRecord`。
- HealthKit 当前通过查询服务读取，没有写入本地数据库；本阶段不从 Probe 临时状态拼接 HealthKit 数据。
- 当前没有已落库的个人规律模型，也没有 App 内置知识索引模型，因此 `matched_patterns` 和 iOS `local_knowledge` 保持空数组，不伪造内容，也不新建第二套数据库。

### 已完成问题与任务

- 请求协议升级为 `protocol_version: 2`，加入由 iOS 生成的 `request_id` 和 `compact_context`。
- 响应回传同一个 `request_id`，Node 日志仅记录 request ID、状态码和耗时。
- Ask 发送前通过现有 SwiftData `ModelContext` 限量查询 `TimelineRecord`。
- 只有问题包含个人时间范围或个人指向时才提取记录；一般知识问题发送空个人上下文。
- “今天”类问题只查询今天；其他个人问题最多查询最近 7 天。
- 最多发送 8 条未隐藏记录；确认文本最多 240 字；标签最多 6 个，每个最多 32 字。
- 只发送 `created_at`、`event_type`、`text` 和 `tags`。
- 不发送 `rawTranscript`、录音文件、录音时长、记录来源、完整数据库或 HealthKit 样本。
- Node 将请求重新构造成受信任对象，校验协议版本、message、locale、timezone、request ID、对象类型、数组上限、日期、字段类型和文本长度。
- v1 请求仍临时兼容：缺少 `request_id` 时由服务器生成，缺少上下文时使用空个人上下文。
- 本阶段保留现有 DeepSeek 与服务器本地知识行为，没有实现阶段 3 的本地优先路由，也没有增加在线工具。

### 自动测试与构建

- Node：`pnpm test`，9/9 通过。
- iOS：`AskChatConfigTests` 与 `AskLocalContextProviderTests` 通过。
- iOS 上下文测试覆盖：空上下文、最多 8 条、文本与标签上限、排除原始转写/来源/录音字段、v2 编码和 request ID。
- Debug `generic/platform=iOS` 构建通过。
- 构建仍存在既有 AppIcon/AppLogo asset warning，本阶段没有修改资源。

### 阶段 2 真机验收步骤

1. 保持阶段 1 已验证的 LAN endpoint 和 Node 配置，重新启动 Node 服务。
2. 在 App 中通过语音记录保存一条带有独特内容的今日时间线记录，例如“下午三点喝咖啡后仍然很困”。
3. 确认该记录已出现在今日时间线，并且不是隐藏状态。
4. 在 Ask 页面提问“我今天记录了什么？”或“为什么我今天下午状态下降？”。
5. 确认请求成功，回答可以引用刚保存的真实确认文本，不出现旧的演示会议数据。
6. 查看 Node 控制台，确认出现 `ask completed request_id=<id> status=200 duration_ms=<n>`，且日志没有打印 message、完整 `compact_context` 或健康数据。
7. 再问一般知识问题“HRV 一般代表什么？”，确认请求仍成功；该问题的 iOS 个人上下文应为空，不应把刚才的时间线记录带入回答。
8. 可选兼容验证：用旧版 curl 请求（只有 message/locale/timezone），确认仍返回 200，并带有服务器生成的 `request_id`。

### 阶段 2 当前状态

- [x] 代码实现完成。
- [x] Node 单元测试通过。
- [x] iOS 相关测试通过。
- [x] iOS 真机目标构建通过。
- [x] iPhone 真机确认真实 SwiftData 记录可完成 Ask 请求。
- [x] 一般知识问题可完成 Ask 请求。
- [x] 用户确认阶段 2 通过。

### 阶段 2 真机验收结果（2026-08-29）

结论：阶段 2 通过。

- 个人数据问题和一般知识问题均成功完成请求与返回。
- 两个问题均调用了大模型，符合阶段 2 的预期：本阶段仅完成 v2 协议、最小本地上下文传输和服务端校验，尚未实现本地确定性回答或按需 LLM 路由。
- “本地可直接回答时不调用 LLM”属于阶段 3，不能用本阶段两次 LLM 调用判定失败。
- 尚未开始阶段 3。
