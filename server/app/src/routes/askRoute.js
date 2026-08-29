import { Router } from "express";
import { parseAskRequest } from "../contracts/askContract.js";

export function createAskRouter(askService) {
  const router = Router();

  router.post("/ask", async (req, res) => {
    const startedAt = Date.now();
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
      console.error(`ask failed request_id=${parsed.value.request_id} status=502 duration_ms=${Date.now() - startedAt}`);
      res.status(502).json({
        request_id: parsed.value.request_id,
        error: "ask_upstream_failed",
        detail: error instanceof Error ? error.message : "Unknown error"
      });
    }
  });

  return router;
}
