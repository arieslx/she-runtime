import test from "node:test";
import assert from "node:assert/strict";
import { normalizeAskResponse, parseAskRequest } from "../src/contracts/askContract.js";

test("parseAskRequest trims valid input", () => {
  const result = parseAskRequest({
    message: "  聊聊今天下午  ",
    locale: "zh-CN",
    timezone: "Asia/Shanghai"
  });

  assert.equal(result.ok, true);
  assert.equal(result.value.message, "聊聊今天下午");
});

test("parseAskRequest rejects empty message", () => {
  const result = parseAskRequest({ message: "   " });

  assert.equal(result.ok, false);
  assert.equal(result.status, 400);
});

test("parseAskRequest bounds and whitelists compact user context", () => {
  const result = parseAskRequest({
    message: "看看我的记录",
    locale: "x".repeat(100),
    timezone: "y".repeat(120),
    context: {
      schema_version: 1,
      generated_at: "2026-08-29T02:00:00Z",
      subjective_events: [
        {
          source_event_id: "unreviewed-event",
          confirmed_text: "尚未确认",
          confirmation_status: "unreviewed"
        },
        ...Array.from({ length: 15 }, (_, index) => ({
          source_event_id: `event-${index}`,
          occurred_at: "2026-08-29T01:00:00Z",
          source: "ask",
          confirmed_text: "困".repeat(300),
          raw_transcript: "must-not-cross-boundary",
          extraction_confidence: 4,
          confirmation_status: "confirmed",
          revision: 2,
          annotations: [
            {
              annotation_id: `confirmed-${index}`,
              dimension: "body_sensation",
              value: "疲劳",
              confirmation_status: "userConfirmed"
            },
            {
              annotation_id: `pending-${index}`,
              dimension: "body_sensation",
              value: "伪标签",
              confirmation_status: "pending"
            }
          ]
        }))
      ],
      health_summary: {
        window_start: "2026-08-02T00:00:00Z",
        window_end: "2026-08-29T00:00:00Z",
        effective_day_count: 99,
        is_stale: false,
        metrics: [
          { metric_key: "hrv", sample_count: 20, latest_value: 51, median_value: 48, unit_key: "milliseconds" },
          { metric_key: "invented_diagnosis", sample_count: 20, latest_value: 1, median_value: 1, unit_key: "claim" }
        ]
      },
      arbitrary_private_blob: "ignored"
    }
  });

  assert.equal(result.ok, true);
  assert.equal(result.value.locale.length, 32);
  assert.equal(result.value.timezone.length, 80);
  assert.equal(result.value.context.subjective_events.length, 12);
  assert.equal(result.value.context.subjective_events.some((item) => item.source_event_id === "unreviewed-event"), false);
  assert.equal(result.value.context.subjective_events[0].confirmed_text.length, 240);
  assert.equal(result.value.context.subjective_events[0].extraction_confidence, 1);
  assert.deepEqual(result.value.context.subjective_events[0].annotations.map((item) => item.value), ["疲劳"]);
  assert.equal("raw_transcript" in result.value.context.subjective_events[0], false);
  assert.equal(result.value.context.health_summary.effective_day_count, 28);
  assert.deepEqual(result.value.context.health_summary.metrics.map((item) => item.metric_key), ["hrv"]);
  assert.equal("arbitrary_private_blob" in result.value.context, false);
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
