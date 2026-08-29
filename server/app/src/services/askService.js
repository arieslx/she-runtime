import { getMockAskContext } from "../context/mockAskContext.js";
import { normalizeAskResponse } from "../contracts/askContract.js";
import { askSystemPrompt } from "../prompts/askSystemPrompt.js";
import { incrementDeepSeekCallCount } from "./usageCounter.js";

export function createAskService({
  deepSeekClient,
  contextProvider = getMockAskContext,
  knowledgeSearch,
  onlineKnowledgeSearch = null
}) {
  return {
    async answer(request) {
      const context = await contextProvider({ request, knowledgeSearch });
      const messages = [
        { role: "system", content: askSystemPrompt },
        {
          role: "user",
          content: JSON.stringify({
            request,
            compact_context: context
          })
        }
      ];

      const content = await deepSeekClient.createChatCompletion(messages);
      const deepSeekCallCount = incrementDeepSeekCallCount();
      const parsed = parseModelJson(content);
      const normalized = normalizeAskResponse({
        ...parsed,
        usage: {
          ...parsed?.usage,
          deepseek_call_count: deepSeekCallCount
        },
        sources: buildSources({ context, request, hasModelAnswer: Boolean(parsed?.answer) })
      });

      if (!normalized.answer) {
        throw new Error("DeepSeek JSON response did not include answer");
      }
      return normalized;
    }
  };
}

function parseModelJson(content) {
  try {
    return JSON.parse(content);
  } catch {
    throw new Error("DeepSeek response was not valid JSON");
  }
}

function buildSources({ context, request, hasModelAnswer }) {
  const sources = [];
  const knowledge = Array.isArray(context?.local_knowledge) ? context.local_knowledge : [];

  for (const card of knowledge) {
    sources.push({
      source_id: card.source_id,
      source_type: card.source_type ?? "local_repo",
      label: card.label ?? card.source_id,
      path: card.path ?? "",
      url: card.url ?? ""
    });
  }

  if (hasModelAnswer) {
    sources.push({
      source_id: "LLM",
      source_type: "llm",
      label: "LLM 推理",
      detail: request.locale === "en-US" ? "Generated from compact_context" : "基于 compact_context 生成"
    });
  }

  return dedupeSources(sources);
}

function dedupeSources(sources) {
  const seen = new Set();
  return sources.filter((item) => {
    const key = [item.source_type, item.source_id, item.label, item.path, item.url].join("|");
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}
