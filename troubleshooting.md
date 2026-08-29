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

## 阶段 3：本地优先路由

### 已完成问题与任务

- 新增 iOS 确定性本地路由，不依赖 LLM 判断是否调用 LLM。
- “今天走了多少步”直接读取已验证的 HealthKit 今日步数查询。
- “昨晚睡了多久”直接读取已验证的最近一次主要睡眠查询。
- “今天记录过几次”直接通过现有 SwiftData 统计未隐藏的今日记录。
- “最近一条记录是什么”直接通过现有 SwiftData 读取最近一条未隐藏记录。
- 上述本地答案不请求 Node，`deepseek_call_count` 为 0，调用路径标记 `llm_called=false`。
- 新增随 App 打包的只读基础知识索引，内容由仓库已有指标知识卡提炼，不包含个人数据。
- “HRV 一般代表什么”等明确指标定义问题可由 App 内置知识直接回答，不请求 Node、不调用 LLM。
- 个人数据解释问题不由本地确定性路由抢答，继续发送最小 `compact_context` 给 Node，并调用 DeepSeek 组织解释。
- Node 新增确定性分类器，将请求分为 `personal_interpretation` 和 `external_knowledge`。
- 拆分本地知识搜索与在线搜索，取消二者无条件并行执行。
- 个人解释请求不调用在线搜索。
- 外部知识请求先查仓库本地知识卡；存在匹配卡时不调用在线搜索。
- 仅当外部知识请求没有本地命中且在线 provider 已配置时，才尝试在线搜索。
- 响应与页面增加 `route`：`local_db_used`、`local_knowledge_used`、`online_tool_called`、`llm_called`。
- 本地知识与在线知识分别限额为最多 3 条，不再出现在线调用已执行但结果被统一 `slice` 丢弃的路径。

### 当前边界

- App 内置索引当前覆盖 HRV、睡眠、静息心率和活动量的基础定义；更复杂的资料与研究问题会进入 Node。
- `ASK_ONLINE_KNOWLEDGE_ENDPOINT` 尚未确认是真实、可信的 Function Tool/API；provider 的正式接入、白名单、响应校验与 prompt injection 防护属于阶段 4。
- 本阶段不会为缺失的在线 API 伪造结果。
- 当前 DeepSeek 的严格响应 schema、错误分类和正式用量统计属于阶段 5。

### 自动测试与构建

- Node：`pnpm test`，13/13 通过。
- Node 路由测试覆盖：个人解释不调用在线搜索；一般知识归类；本地知识命中时不调用在线搜索；调用路径字段。
- iOS：Ask 配置、最小上下文、本地路由和 App 内置知识测试全部通过。
- iOS 本地路由测试确认今日记录次数在本地回答，LLM 与在线工具调用均为 false；解释问题不会被本地确定性路由误接管。
- Debug `generic/platform=iOS` 构建通过。
- 仅有既有 AppIcon/AppLogo asset warning。

### 阶段 3 真机验收步骤

1. 启动 Node，并记录当前控制台最后一条日志。
2. 在 Ask 页面提问“今天记录过几次？”。
3. 确认答案与今日时间线未隐藏记录数量一致。
4. 确认页面显示大模型调用次数为 0，路径显示本地数据“是”、在线工具“否”、LLM“否”。
5. 确认 Node 控制台没有新增 `/api/ask` 请求日志。
6. 提问“最近一条记录是什么？”，确认回答来自真实最近记录，且仍无 Node 请求和 LLM 调用。
7. 在已允许 HealthKit 读取的真机上提问“今天走了多少步？”和“昨晚睡了多久？”，确认与 HealthKit Probe 数据一致且不请求 Node。
8. 提问“为什么我今天下午状态下降？”，确认 Node 收到请求，页面路径显示本地数据按实际上下文标记、在线工具“否”、LLM“是”。
9. 提问“HRV 一般代表什么？”，确认来源为 App 内置 `METRIC-HRV`，路径显示本地知识“是”、在线工具“否”、LLM“否”，Node 没有新增请求。
10. 再提问“有哪些研究讨论睡眠和恢复？”，确认内置基础定义不足时请求 Node；Node 先查仓库本地知识卡，存在命中时在线工具仍为“否”，LLM 为“是”。

### 阶段 3 当前状态

- [x] 代码实现完成。
- [x] Node 路由测试通过。
- [x] iOS 本地路由测试通过。
- [x] iOS 真机目标构建通过。
- [x] iPhone 真机确认其余阶段 3 路由与回答通过。
- [ ] 等待 iPhone 真机确认知识来源小卡片已全部显示中文标题。
- [ ] 等待确认“通过，进入下一阶段”。

### 阶段 3 真机问题：中文研究问题未命中本地知识（2026-08-29）

真机提问“有哪些研究讨论睡眠和恢复？”时，请求进入了 Node 和大模型，但回答称没有最近的睡眠与恢复记录，未引用仓库本地知识卡。该结果不通过阶段 3 验收。

根因不是该问题调用了 LLM。研究归纳类问题按当前设计应由 Node 先检索本地知识，再由 LLM 组织回答。真正的问题是本地知识检索将完整中文句子视为单个 token，而别名匹配只判断 token 是否与“睡眠”“恢复”等词完全相等，导致 `METRIC-SLEEP` 和 `METRIC-HRV` 均未命中。LLM 最终收到空知识和空个人数据，因此生成了要求用户补充个人记录的无效回答。

本阶段内已完成修复：

- 本地知识卡别名改为在规范化后的完整中文问题中做包含匹配，不再依赖中文空格分词。
- 保留确定性路由：该问题仍属于外部知识/研究归纳，不误判为个人数据解释。
- 增加原句回归测试，确认“有哪些研究讨论睡眠和恢复？”能命中 `METRIC-SLEEP` 和 `METRIC-HRV`。
- 增加 Ask 路由回归测试，确认命中的本地知识会进入 LLM prompt，且响应路径为本地知识“是”、在线工具“否”、LLM“是”。
- Node 测试更新为 15/15 通过。

复验前需要完整重启 Node 服务，使修改后的 `knowledgeSearch.js` 生效。再次使用完全相同的问题时，预期行为是：

1. iPhone 请求 Node，并调用一次 LLM；研究归纳调用 LLM 是预期行为。
2. 页面路径显示本地数据“否”、本地知识“是”、在线工具“否”、LLM“是”。
3. 来源至少包含 `METRIC-SLEEP`，并应同时命中与恢复相关的 `METRIC-HRV`。
4. 回答应基于本地知识讨论睡眠阶段、睡眠时长/规律或 HRV 恢复信号，不再以“没有你的最近记录”为主要回答。
5. 阶段 3 在上述真机复验通过前继续保持未完成，不进入阶段 4。

### 阶段 3 真机反馈：知识来源卡片中文化（2026-08-29）

其余阶段 3 验收项已由用户确认通过。来源小卡片仍显示 `METRIC-SLEEP` 一类内部英文编号，不符合中文界面要求。

已完成：

- 保留 `METRIC-*` 作为稳定的内部 `source_id`，不改变检索、协议和测试引用。
- Node 对外返回的 8 张指标知识卡标题统一读取知识卡已有的 `metric_zh`：活动量、月经周期、日内心率模式、心率变异性、睡眠呼吸频率、静息心率、睡眠、夜间腕温。
- 展示格式统一为“本地知识库 · 中文指标名称”，不再把 `METRIC-*` 作为小卡片标题。
- 增加自动测试，防止指标卡展示标题再次泄漏内部英文编号。
- Node 全量测试 16/16 通过。
- 阶段 3 只等待中文来源卡片的真机确认。

### 阶段 3 最终验收（2026-08-29）

结论：阶段 3 通过。用户已确认本地优先路由、知识检索和中文来源卡片均符合真机验收要求，可以进入阶段 4。

## 阶段 4：在线 Function Tool/API

### 配置检查结论

- 当前 `server/app/.env` 未配置 `ASK_ONLINE_KNOWLEDGE_ENDPOINT`。
- `.env.example` 也没有在线知识 endpoint 或供应商 API Key 配置。
- 仓库中没有供应商名称、认证方式、接口文档、请求/响应样例或可验证的真实 Function Tool/API。
- 原有 `onlineKnowledgeSearch.js` 只是对任意配置 URL 发起 POST 的通用 fetch 包装，不能证明 endpoint 可信，也没有供应商白名单、严格字段校验或 prompt injection 边界。
- 因此当前不能确认存在真实在线知识服务，不能启用在线调用，也不能擅自绑定收费供应商。

### 已完成问题与任务

- 新增明确的 `OnlineKnowledgeProvider` 结构契约：稳定 provider ID、启用状态和 `search(query, limit)`。
- 新增 disabled provider；未选定真实供应商时固定返回空结果，不伪造资料、不执行外部请求。
- 即使遗留的 `ASK_ONLINE_KNOWLEDGE_ENDPOINT` 被设置，当前运行时也不会把任意 URL 静默视为可信 provider。
- Ask 路由仅在 provider 明确 `enabled=true` 时将 `online_tool_called` 标记为 true。
- 删除未绑定真实供应商、缺少可信契约的通用在线 fetch 实现。
- 增加 disabled provider 与 provider 接口形状的 mock 测试。
- 增加 Ask 路由回归测试，确认 disabled provider 不执行且 `online_tool_called=false`。
- README 记录启用真实 provider 前必须提供的配置和安全信息。

### 当前阻塞与下一步所需信息

按照阶段 4 约束，代码在 provider disabled 状态暂停。继续接入前需要用户选择在线知识供应商或提供已有接口的以下信息：

1. 供应商/服务名称，以及允许调用的固定 API host。
2. API 文档或准确的请求、成功响应、失败响应样例。
3. 认证 header 形式和 Node 端环境变量名称（不要提供真实密钥到 Git）。
4. timeout、限流和计费规则。
5. 是否稳定返回标题、原始来源 URL、摘要、发布日期和 provider 名称。

收到上述信息后，才能实现供应商专用 allowlist adapter、超时、数量与长度限制、URL/Content-Type/字段校验、失败状态区分及不可信内容隔离。阶段 4 在此之前不判定通过，也不进入阶段 5。

### 阶段 4 产品决策（2026-08-29）

经产品评估，阶段 4 的在线 Function Tool/API 暂不实施。当前 App 内置知识和 Node 仓库本地知识卡已经满足 MVP；需要实时外部研究检索时再作为独立需求重新立项。

处理结论：

- 阶段 4 标记为“按产品决策暂不实施”，不是“在线知识功能验收通过”。
- 保留 disabled `OnlineKnowledgeProvider` 边界，确保当前版本不会误发在线知识请求，也不会伪造外部检索结果。
- `online_tool_called` 在当前 MVP 中保持 false。
- 不选择在线供应商，不增加工具 API Key，不引入新的网络依赖或费用。
- 本决策解除阶段 5 的前置阻塞；是否开始阶段 5 仍需用户明确确认。

### 阶段 4 代码清理（2026-08-29）

根据“当前 MVP 不实施在线知识库”的产品决策，已从运行时移除阶段 4 的临时 provider 结构，而不是恢复原先可请求任意 URL 的通用 fetch：

- 删除 disabled provider 文件及其专用测试。
- `server.js` 不再创建或注入在线 provider。
- `askService.js` 删除在线搜索分支，响应继续固定保留 `online_tool_called=false`。
- `knowledgeSearch.js` 只保留 App/仓库本地知识检索，不再暴露 `searchOnline()`。
- 删除在线 endpoint 和 timeout 环境配置读取。
- README 明确当前 MVP 只使用本地知识卡；在线研究检索以后必须独立立项。
- 保留回归测试：个人解释、一般知识、本地知识无命中三类 Node 请求均报告 `online_tool_called=false`。
- 不恢复已删除的旧 `onlineKnowledgeSearch.js`，避免任意 endpoint 被误当成可信知识服务。
