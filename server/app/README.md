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
