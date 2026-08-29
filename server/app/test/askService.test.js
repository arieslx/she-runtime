import test from "node:test";
import assert from "node:assert/strict";
import { createAskService } from "../src/services/askService.js";

test("ask service returns normalized response with model call count", async () => {
  const askService = createAskService({
    deepSeekClient: {
      async createChatCompletion(messages) {
        const userPayload = JSON.parse(messages[1].content);
        assert.equal(userPayload.request.message, "聊聊今天下午");
        assert.equal("context" in userPayload.request, false);
        assert.equal(userPayload.compact_context.subjective_events[0].source_event_id, "event-ask-1");
        assert.equal(userPayload.compact_context.health_summary.metrics[0].metric_key, "hrv");
        assert.equal(userPayload.compact_context.local_knowledge[0].source_id, "METRIC-HRV");
        assert.ok(Array.isArray(userPayload.compact_context.knowledge_sources));

        return JSON.stringify({
          answer: "今天下午的状态下降更常和连续沟通同时出现。",
          basis: [{ label: "你的规律", value: "90 分钟以上沟通" }],
          safety_note: "共同出现不代表因果。",
          follow_up: "要继续看恢复方式吗？"
        });
      }
    },
    knowledgeSearch: {
      async search() {
        return [{ source_id: "METRIC-HRV", avoid_claims: ["HRV 低说明你压力大"] }];
      }
    }
  });

  const response = await askService.answer({
    message: "聊聊今天下午",
    locale: "zh-CN",
    timezone: "Asia/Shanghai",
    context: {
      schema_version: 1,
      generated_at: "2026-08-29T02:00:00Z",
      subjective_events: [{
        source_event_id: "event-ask-1",
        occurred_at: "2026-08-29T01:00:00Z",
        source: "ask",
        confirmed_text: "今天下午很累",
        extraction_status: "pending",
        confirmation_status: "confirmed",
        revision: 1,
        annotations: []
      }],
      health_summary: {
        window_start: "2026-08-02T00:00:00Z",
        window_end: "2026-08-29T00:00:00Z",
        effective_day_count: 18,
        latest_record_at: "2026-08-29T00:00:00Z",
        is_stale: false,
        metrics: [{
          metric_key: "hrv",
          sample_count: 18,
          latest_value: 51,
          median_value: 48,
          unit_key: "milliseconds"
        }]
      }
    }
  });

  assert.equal(response.answer, "今天下午的状态下降更常和连续沟通同时出现。");
  assert.ok(response.usage.deepseek_call_count >= 1);
  assert.ok(Array.isArray(response.sources));
  assert.ok(response.sources.some((item) => item.source_type === "local_repo"));
  assert.ok(response.sources.some((item) => item.source_type === "subjective_event" && item.source_id === "event-ask-1"));
  assert.ok(response.sources.some((item) => item.source_type === "health_summary"));
  assert.ok(response.sources.some((item) => item.source_type === "llm"));
});

test("ask service replaces causal or diagnostic model claims", async () => {
  const askService = createAskService({
    deepSeekClient: {
      async createChatCompletion() {
        return JSON.stringify({
          answer: "你的疲劳一定是连续开会导致的。",
          basis: [{ label: "诊断", value: "已经证明" }]
        });
      }
    },
    knowledgeSearch: { async search() { return []; } }
  });

  const response = await askService.answer({
    message: "为什么累？",
    locale: "zh-CN",
    timezone: "Asia/Shanghai",
    context: null
  });

  assert.equal(response.answer, "现有记录只说明这些情况出现在同一个观察窗口，还不足以判断原因。");
  assert.deepEqual(response.basis, []);
  assert.equal(response.safety_note, "共同出现不代表因果，也不是医学诊断。");
});
