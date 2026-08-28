import express from "express";
import { createAskRouter } from "./routes/askRoute.js";

export function createApp({ askService, config }) {
  const app = express();

  app.use((req, _res, next) => {
    console.log(`${new Date().toISOString()} ${req.method} ${req.originalUrl}`);
    next();
  });

  app.use(express.json({ limit: "32kb" }));

  app.get("/api/health", (_req, res) => {
    res.json({
      ok: true,
      service: "she-runtime-ask-server",
      endpoint: config?.endpoints?.ask ?? "/api/ask",
      health_endpoint: config?.endpoints?.health ?? "/api/health",
      listen: {
        host: config?.host ?? null,
        port: config?.port ?? null
      },
      deepseek: {
        configured: Boolean(config?.deepSeek?.apiKey),
        base_url: config?.deepSeek?.baseUrl ?? null,
        model: config?.deepSeek?.model ?? null,
        timeout_ms: config?.deepSeek?.timeoutMs ?? null
      }
    });
  });

  app.use("/api", createAskRouter(askService));

  return app;
}
