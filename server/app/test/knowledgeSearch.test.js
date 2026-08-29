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

test("knowledge search matches aliases inside a full Chinese sentence", async () => {
  const knowledgeSearch = createKnowledgeSearch();
  const results = await knowledgeSearch.searchLocal("有哪些研究讨论睡眠和恢复？", 3);

  assert.ok(results.some((item) => item.source_id === "METRIC-SLEEP"));
  assert.ok(results.some((item) => item.source_id === "METRIC-HRV"));
});

test("metric knowledge cards expose Chinese display labels", async () => {
  const knowledgeSearch = createKnowledgeSearch();
  const queries = [
    "活动量", "月经周期", "日内心率", "HRV", "睡眠呼吸频率", "静息心率", "睡眠", "夜间腕温"
  ];

  const results = (await Promise.all(queries.map((query) => knowledgeSearch.searchLocal(query, 3))))
    .flat()
    .filter((item) => item.source_id.startsWith("METRIC-"));

  assert.ok(results.length > 0);
  assert.ok(results.every((item) => item.label.startsWith("本地知识库 · ")));
  assert.ok(results.every((item) => !item.label.includes(item.source_id)));
});
