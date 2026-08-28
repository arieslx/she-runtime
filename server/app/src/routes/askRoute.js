import { Router } from "express";
import { parseAskRequest } from "../contracts/askContract.js";

export function createAskRouter(askService) {
  const router = Router();

  router.post("/ask", async (req, res) => {
    const parsed = parseAskRequest(req.body);
    if (!parsed.ok) {
      res.status(parsed.status).json({ error: parsed.error });
      return;
    }

    try {
      const answer = await askService.answer(parsed.value);
      res.json(answer);
    } catch (error) {
      res.status(502).json({
        error: "ask_upstream_failed",
        detail: error instanceof Error ? error.message : "Unknown error"
      });
    }
  });

  return router;
}
