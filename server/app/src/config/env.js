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

export function loadConfig() {
  return {
    port: readInteger("PORT", 3000),
    deepSeek: {
      apiKey: readString("DEEPSEEK_API_KEY"),
      baseUrl: readString("DEEPSEEK_BASE_URL", "https://api.deepseek.com"),
      model: readString("DEEPSEEK_MODEL", "deepseek-v4-flash"),
      timeoutMs: readInteger("DEEPSEEK_TIMEOUT_MS", 30_000)
    }
  };
}
