import dotenv from "dotenv";

dotenv.config();

function readInteger(name, fallback) {
  const raw = process.env[name];
  if (!raw) return fallback;

  const value = Number.parseInt(raw, 10);
  if (!Number.isFinite(value) || value <= 0) {
    throw new Error(`${name} must be a positive integer`);
  }
  return value;
}

function readString(name, fallback = "") {
  const value = process.env[name] ?? fallback;
  return value.trim();
}

function readEnum(name, allowedValues, fallback) {
  const value = readString(name, fallback);
  if (!allowedValues.includes(value)) {
    throw new Error(`${name} must be one of: ${allowedValues.join(", ")}`);
  }
  return value;
}

export function loadConfig() {
  const port = readInteger("PORT", 3000);
  const host = readString("HOST", "0.0.0.0");
  const publicBaseUrl = readString("ASK_SERVER_BASE_URL", `http://localhost:${port}`).replace(/\/+$/, "");

  return {
    port,
    host,
    publicBaseUrl,
    endpoints: {
      ask: `${publicBaseUrl}/api/ask`,
      health: `${publicBaseUrl}/api/health`
    },
    deepSeek: {
      apiKey: readString("DEEPSEEK_API_KEY"),
      baseUrl: readString("DEEPSEEK_BASE_URL", "https://api.deepseek.com"),
      model: readString("DEEPSEEK_MODEL", "deepseek-v4-flash"),
      timeoutMs: readInteger("DEEPSEEK_TIMEOUT_MS", 30_000),
      maxTokens: readInteger("DEEPSEEK_MAX_TOKENS", 800),
      thinkingMode: readEnum("DEEPSEEK_THINKING_MODE", ["enabled", "disabled"], "disabled")
    }
  };
}
