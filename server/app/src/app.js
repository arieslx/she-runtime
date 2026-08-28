import express from "express";
import { createAskRouter } from "./routes/askRoute.js";

export function createApp({ askService }) {
  const app = express();

  app.use((req, _res, next) => {
    console.log(`${new Date().toISOString()} ${req.method} ${req.originalUrl}`);
    next();
  });

  app.use(express.json({ limit: "32kb" }));

  app.get("/api/health", (_req, res) => {
    res.json({ ok: true });
  });

  app.use("/api", createAskRouter(askService));

  return app;
}
