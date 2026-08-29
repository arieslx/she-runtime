import { Router } from "express";
import { timingSafeEqual } from "node:crypto";
import { parseAskRequest } from "../contracts/askContract.js";
import { toServiceError } from "../errors/serviceError.js";

export function createAskRouter(askService, { apiKey = "" } = {}) {
  const router = Router();

  router.post("/ask", async (req, res) => {
    const startedAt = Date.now();
    if (apiKey && !keysMatch(req.get("X-Ask-API-Key") ?? "", apiKey)) {
      console.warn(`ask rejected auth status=401 duration_ms=${Date.now() - startedAt}`);
      res.status(401).json({ error: "unauthorized" });
      return;
    }
    const parsed = parseAskRequest(req.body);
    if (!parsed.ok) {
      console.warn(`ask rejected request_id=invalid status=${parsed.status} duration_ms=${Date.now() - startedAt}`);
      res.status(parsed.status).json({ error: parsed.error });
      return;
    }

    try {
      const answer = await askService.answer(parsed.value);
      console.info(`ask completed request_id=${parsed.value.request_id} status=200 duration_ms=${Date.now() - startedAt}`);
      res.json(answer);
    } catch (error) {
      const serviceError = toServiceError(error);
      console.error(`ask failed request_id=${parsed.value.request_id} error=${serviceError.code} status=${serviceError.status} duration_ms=${Date.now() - startedAt}`);
      res.status(serviceError.status).json({
        request_id: parsed.value.request_id,
        error: serviceError.code,
        detail: serviceError.publicMessage
      });
    }
  });

  return router;
}

function keysMatch(candidate, expected) {
  const candidateBuffer = Buffer.from(candidate, "utf8");
  const expectedBuffer = Buffer.from(expected, "utf8");
  return candidateBuffer.length === expectedBuffer.length &&
    timingSafeEqual(candidateBuffer, expectedBuffer);
}
