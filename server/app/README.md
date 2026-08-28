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
  "message": "为什么我今天下午状态掉得这么快？",
  "locale": "zh-CN",
  "timezone": "Asia/Shanghai"
}
```

## Health Check

```http
GET /api/health
```

The response includes the public Ask endpoint, listening host/port, and whether
DeepSeek is configured. It does not include the API key.

The production Ask service currently supplies an empty personal context until
real local context is added by the protocol work. `mockAskContext.js` is a demo
fixture only and is not used by the default service path.
