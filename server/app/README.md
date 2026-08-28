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
