import test from "node:test";
import assert from "node:assert/strict";
import { createAskService } from "../src/services/askService.js";

test("ask service returns normalized response with model call count", async () => {
  const askService = createAskService({
    deepSeekClient: {
      async createChatCompletion(messages) {
        const userPayload = JSON.parse(messages[1].content);
        assert.equal(userPayload.request.message, "聊聊今天下午");
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
    protocol_version: 2,
    message: "聊聊今天下午",
    locale: "zh-CN",
    timezone: "Asia/Shanghai",
    request_id: "service-test-001",
    compact_context: {
      today: { date: "2026-08-29", record_count: 1 },
      recent_records: [{
        created_at: "2026-08-29T06:30:00Z",
        event_type: "Voice check-in",
        text: "下午感觉有点累",
        tags: []
      }],
      matched_patterns: [],
      local_knowledge: []
    }
  });

  assert.equal(response.request_id, "service-test-001");
  assert.equal(response.answer, "今天下午的状态下降更常和连续沟通同时出现。");
  assert.ok(response.usage.deepseek_call_count >= 1);
  assert.ok(Array.isArray(response.sources));
  assert.ok(response.sources.some((item) => item.source_type === "local_repo"));
  assert.ok(response.sources.some((item) => item.source_type === "llm"));
  assert.deepEqual(response.route, {
    local_db_used: true,
    local_knowledge_used: true,
    online_tool_called: false,
    llm_called: true
  });
});

test("default context contains no fabricated personal data", async () => {
  const askService = createAskService({
    deepSeekClient: {
      async createChatCompletion(messages) {
        const { compact_context: context } = JSON.parse(messages[1].content);
        assert.equal(context.user_window, null);
        assert.deepEqual(context.today, {});
        assert.deepEqual(context.recent_records, []);
        assert.deepEqual(context.patterns, []);
        assert.equal(JSON.stringify(context).includes("152"), false);
        assert.equal(JSON.stringify(context).includes("continuous-communication-drain"), false);
        return JSON.stringify({ answer: "目前没有可用于回答的个人数据。" });
      }
    },
    knowledgeSearch: { async search() { return []; } }
  });

  const response = await askService.answer({
    message: "我今天状态怎么样？",
    locale: "zh-CN",
    timezone: "Asia/Shanghai",
    request_id: "service-test-002",
    compact_context: {
      today: {},
      recent_records: [],
      matched_patterns: [],
      local_knowledge: []
    }
  });
  assert.equal(response.answer, "目前没有可用于回答的个人数据。");
  assert.equal(response.route.online_tool_called, false);
  assert.equal(response.route.llm_called, true);
});
