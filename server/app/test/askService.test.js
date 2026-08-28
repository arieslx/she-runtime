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
    message: "聊聊今天下午",
    locale: "zh-CN",
    timezone: "Asia/Shanghai"
  });

  assert.equal(response.answer, "今天下午的状态下降更常和连续沟通同时出现。");
  assert.ok(response.usage.deepseek_call_count >= 1);
  assert.ok(Array.isArray(response.sources));
  assert.ok(response.sources.some((item) => item.source_type === "local_repo"));
  assert.ok(response.sources.some((item) => item.source_type === "llm"));
});
