import test from "node:test";
import assert from "node:assert/strict";
import { AskRouteKind, classifyAskRequest } from "../src/services/askRouter.js";

test("classifier routes personal context to interpretation", () => {
  assert.equal(classifyAskRequest({
    message: "为什么状态下降？",
    compact_context: { today: {}, recent_records: [{ text: "累" }], matched_patterns: [] }
  }), AskRouteKind.PERSONAL_INTERPRETATION);
});

test("classifier routes general metric question to external knowledge", () => {
  assert.equal(classifyAskRequest({
    message: "HRV 一般代表什么？",
    compact_context: { today: {}, recent_records: [], matched_patterns: [] }
  }), AskRouteKind.EXTERNAL_KNOWLEDGE);
});

test("personal interpretation reports no online tool usage", async () => {
  const { createAskService } = await import("../src/services/askService.js");
  const service = createAskService({
    deepSeekClient: { async createChatCompletion() { return JSON.stringify({ answer: "ok" }); } },
    knowledgeSearch: { async searchLocal() { return []; } }
  });
  const response = await service.answer({
    message: "为什么我今天状态下降？",
    locale: "zh-CN",
    request_id: "route-test-001",
    compact_context: { today: {}, recent_records: [{ text: "累" }], matched_patterns: [], local_knowledge: [] }
  });
  assert.equal(response.route.online_tool_called, false);
});

test("general question uses local knowledge and reports no online tool usage", async () => {
  const { createAskService } = await import("../src/services/askService.js");
  const service = createAskService({
    deepSeekClient: { async createChatCompletion() { return JSON.stringify({ answer: "ok" }); } },
    knowledgeSearch: {
      async searchLocal() { return [{ source_id: "METRIC-HRV", source_type: "local_repo" }]; }
    }
  });
  const response = await service.answer({
    message: "HRV 一般代表什么？",
    locale: "zh-CN",
    request_id: "route-test-002",
    compact_context: { today: {}, recent_records: [], matched_patterns: [], local_knowledge: [] }
  });
  assert.equal(response.route.local_knowledge_used, true);
  assert.equal(response.route.online_tool_called, false);
  assert.equal(response.route.llm_called, true);
});

test("research question passes matched local knowledge to the LLM", async () => {
  let receivedKnowledge = [];
  const { createAskService } = await import("../src/services/askService.js");
  const service = createAskService({
    deepSeekClient: {
      async createChatCompletion(messages) {
        receivedKnowledge = JSON.parse(messages[1].content).compact_context.local_knowledge;
        return JSON.stringify({ answer: "本地知识回答" });
      }
    },
    knowledgeSearch: {
      async searchLocal() {
        return [{ source_id: "METRIC-SLEEP", source_type: "local_repo", label: "本地睡眠知识" }];
      }
    }
  });
  const response = await service.answer({
    message: "有哪些研究讨论睡眠和恢复？",
    locale: "zh-CN",
    request_id: "route-test-003",
    compact_context: { today: {}, recent_records: [], matched_patterns: [], local_knowledge: [] }
  });
  assert.equal(receivedKnowledge[0].source_id, "METRIC-SLEEP");
  assert.equal(response.route.local_knowledge_used, true);
  assert.equal(response.route.online_tool_called, false);
  assert.equal(response.route.llm_called, true);
});

test("question without a local knowledge match still reports no online tool usage", async () => {
  const { createAskService } = await import("../src/services/askService.js");
  const service = createAskService({
    deepSeekClient: { async createChatCompletion() { return JSON.stringify({ answer: "无在线资料回答" }); } },
    knowledgeSearch: { async searchLocal() { return []; } }
  });

  const response = await service.answer({
    message: "查找一个本地知识库没有覆盖的最新研究",
    locale: "zh-CN",
    request_id: "route-test-004",
    compact_context: { today: {}, recent_records: [], matched_patterns: [], local_knowledge: [] }
  });

  assert.equal(response.route.online_tool_called, false);
});
