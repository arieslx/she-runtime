import test from "node:test";
import assert from "node:assert/strict";
import { createKnowledgeSearch } from "../src/services/knowledgeSearch.js";

test("knowledge search finds sleep card for sleep-related question", async () => {
  const knowledgeSearch = createKnowledgeSearch();
  const results = await knowledgeSearch.search("最近短睡以后 HRV 为什么低", 3);

  assert.ok(results.length > 0);
  assert.ok(results.some((item) => item.metric === "sleep" || item.metric === "hrv"));
  assert.ok(results.every((item) => !("content" in item)));
});
