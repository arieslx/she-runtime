# sheRuntime Ask Server

Node.js proxy for the Ask page. The iOS app calls this server, and the
server owns the DeepSeek API key.

## Setup

```bash
cd server/app
pnpm install
cp .env.example .env
pnpm dev
```

Set `DEEPSEEK_API_KEY` in `.env` before using the real DeepSeek API.

For an iOS device on the same Wi-Fi network, expose the server on all local
interfaces and advertise the Mac LAN address:

```env
HOST=0.0.0.0
ASK_SERVER_BASE_URL=http://<mac-lan-ip>:3000
```

Then set the iOS runtime endpoint to:

```text
ASK_CHAT_ENDPOINT=http://<mac-lan-ip>:3000/api/ask
```

For Debug builds, set `ASK_CHAT_ENDPOINT` explicitly in the Xcode Scheme or
provide the `ASK_CHAT_ENDPOINT` build setting used by the generated Info.plist.
Plain HTTP is accepted only for RFC 1918 LAN addresses or `.local` hosts.
Loopback addresses are intentionally rejected because `127.0.0.1` on a real
iPhone points to the phone, not the development Mac.

Release builds require an HTTPS endpoint. Inject the production value through
the `ASK_CHAT_ENDPOINT` build setting; do not hard-code a private domain in
application logic. When no valid endpoint is configured, the app reports the
current value and configuration guidance instead of falling back to localhost.

The app also reads `AskChatEndpoint` from `UserDefaults` or Info.plist when the
environment variable is not set. Local HTTP access is allowed through the app's
ATS local-network exception, and iOS will prompt for local network access on
device.

## Endpoint

```http
POST /api/ask
Content-Type: application/json
```

```json
{
  "protocol_version": 2,
  "message": "为什么我今天下午状态掉得这么快？",
  "locale": "zh-CN",
  "timezone": "Asia/Shanghai",
  "request_id": "<uuid>",
  "compact_context": {
    "today": { "date": "2026-08-29", "record_count": 1 },
    "recent_records": [
      {
        "created_at": "2026-08-29T06:30:00Z",
        "event_type": "Voice check-in",
        "text": "下午感觉有点累",
        "tags": []
      }
    ],
    "matched_patterns": [],
    "local_knowledge": []
  }
}
```

Protocol version 2 sends only a bounded, question-relevant snapshot from the
existing iOS SwiftData store. The client sends at most 8 visible records from
the current day or previous 7 days, truncates record text and tags, and never
sends raw transcripts, audio, unrelated HealthKit samples, or the full local
database. Version 1 requests without `request_id` or `compact_context` remain
accepted temporarily and receive a server-generated request ID with an empty
personal context.

The response echoes `request_id`. Server logs record only this ID, HTTP status,
and duration; compact health context and message text are not logged.

Responses also include the executed path:

```json
{
  "route": {
    "local_db_used": true,
    "local_knowledge_used": true,
    "online_tool_called": false,
    "llm_called": true
  }
}
```

Deterministic questions supported by the iOS local router (today's steps, last
night's sleep, today's record count, and latest record) do not call this
endpoint. Basic metric-definition questions can also be answered from the
read-only knowledge index bundled with the app. Personal interpretation
requests may use server-local knowledge but
never trigger online search. General knowledge requests use the repository's
reviewed local knowledge cards and DeepSeek only for synthesis when needed.

## Online knowledge provider

Online Function Tool/API integration is intentionally out of scope for the
current MVP. The server contains no online provider adapter and never makes an
external knowledge request. The response retains `online_tool_called: false`
for protocol compatibility. Real-time external research search must be treated
as a separate product and security project if it is introduced later.

## Health Check

```http
GET /api/health
```

The response includes the public Ask endpoint, listening host/port, and whether
DeepSeek is configured. It does not include the API key.

The production Ask service currently supplies an empty personal context until
real local context is added by the protocol work. `mockAskContext.js` is a demo
fixture only and is not used by the default service path.
