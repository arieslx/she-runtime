import test from "node:test";
import assert from "node:assert/strict";
import { normalizeAskResponse, parseAskModelResponse, parseAskRequest } from "../src/contracts/askContract.js";

test("parseAskRequest trims valid input", () => {
  const result = parseAskRequest({
    message: "  聊聊今天下午  ",
    locale: "zh-CN",
    timezone: "Asia/Shanghai"
  });

  assert.equal(result.ok, true);
  assert.equal(result.value.message, "聊聊今天下午");
  assert.equal(result.value.protocol_version, 1);
  assert.ok(result.value.request_id);
  assert.deepEqual(result.value.compact_context.recent_records, []);
});

test("parseAskRequest rejects empty message", () => {
  const result = parseAskRequest({ message: "   " });

  assert.equal(result.ok, false);
  assert.equal(result.status, 400);
});

test("parseAskRequest accepts bounded protocol v2 context", () => {
  const result = parseAskRequest({
    protocol_version: 2,
    message: "为什么我今天状态下降？",
    locale: "zh-CN",
    timezone: "Asia/Shanghai",
    request_id: "request-002",
    compact_context: {
      today: { date: "2026-08-29", record_count: 1 },
      recent_records: [{
        created_at: "2026-08-29T06:30:00Z",
        event_type: "Voice check-in",
        text: "下午感觉有点累",
        tags: ["疲惫"]
      }],
      matched_patterns: [],
      local_knowledge: []
    }
  });

  assert.equal(result.ok, true);
  assert.equal(result.value.request_id, "request-002");
  assert.equal(result.value.compact_context.recent_records.length, 1);
});

test("parseAskRequest rejects oversized and malformed compact context", () => {
  const base = {
    protocol_version: 2,
    message: "test",
    request_id: "request-003"
  };
  const tooMany = parseAskRequest({
    ...base,
    compact_context: {
      recent_records: Array.from({ length: 9 }, (_, index) => ({
        created_at: "2026-08-29T06:30:00Z",
        event_type: "Voice check-in",
        text: String(index),
        tags: []
      }))
    }
  });
  const malformed = parseAskRequest({ ...base, compact_context: [] });
  const longText = parseAskRequest({
    ...base,
    compact_context: {
      recent_records: [{
        created_at: "2026-08-29T06:30:00Z",
        event_type: "Voice check-in",
        text: "x".repeat(241),
        tags: []
      }]
    }
  });

  assert.equal(tooMany.ok, false);
  assert.equal(malformed.ok, false);
  assert.equal(longText.ok, false);
});

test("normalizeAskResponse limits malformed basis items", () => {
  const result = normalizeAskResponse({
    answer: "  ok  ",
    basis: [
      { label: "今天", value: "3 场会议" },
      { label: "", value: "skip" },
      { label: "规律", value: "90 分钟以上" },
      { label: "多余", value: "会被保留到上限内" },
      { label: "第四个", value: "被截断" }
    ],
    safety_note: "  共现不代表因果  "
  });

  assert.equal(result.answer, "ok");
  assert.equal(result.basis.length, 3);
  assert.equal(result.safety_note, "共现不代表因果");
});

test("parseAskModelResponse accepts only the documented model schema", () => {
  const result = parseAskModelResponse(JSON.stringify({
    answer: "值得继续观察自己的睡眠与恢复变化。",
    basis: [{ label: "本地知识", value: "睡眠与 HRV 可能同时变化" }],
    safety_note: "相关不等于因果。",
    follow_up: "要继续看最近记录吗？"
  }));

  assert.equal(result.ok, true);
  assert.equal(result.value.basis.length, 1);
});

test("parseAskModelResponse rejects invalid JSON, empty answers, extra fields and malformed basis", () => {
  const cases = [
    "not-json",
    JSON.stringify({ answer: "" }),
    JSON.stringify({ answer: "ok", unexpected: true }),
    JSON.stringify({ answer: "ok", basis: [{ label: "only-label" }] }),
    JSON.stringify({ answer: "ok", basis: Array.from({ length: 4 }, () => ({ label: "a", value: "b" })) })
  ];

  assert.ok(cases.every((content) => parseAskModelResponse(content).ok === false));
});
