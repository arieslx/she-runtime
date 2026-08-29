import { getEmptyAskContext } from "../context/emptyAskContext.js";
import { normalizeAskResponse } from "../contracts/askContract.js";
import { askSystemPrompt } from "../prompts/askSystemPrompt.js";
import { incrementDeepSeekCallCount } from "./usageCounter.js";
import { hasPersonalContext } from "./askRouter.js";

export function createAskService({
  deepSeekClient,
  contextProvider = getEmptyAskContext,
  knowledgeSearch
}) {
  return {
    async answer(request) {
      const localKnowledge = knowledgeSearch?.searchLocal
        ? await knowledgeSearch.searchLocal(request.message, 3)
        : await knowledgeSearch?.search?.(request.message, 3) ?? [];
      const serverContext = await contextProvider({
        request,
        knowledgeSearch,
        knowledge: localKnowledge
      });
      const context = mergeCompactContext(serverContext, request.compact_context);
      const { compact_context: _compactContext, ...requestMetadata } = request;
      const messages = [
        { role: "system", content: askSystemPrompt },
        {
          role: "user",
          content: JSON.stringify({
            request: requestMetadata,
            compact_context: context
          })
        }
      ];

      const content = await deepSeekClient.createChatCompletion(messages);
      const deepSeekCallCount = incrementDeepSeekCallCount();
      const parsed = parseModelJson(content);
      const normalized = normalizeAskResponse({
        ...parsed,
        request_id: request.request_id,
        usage: {
          ...parsed?.usage,
          deepseek_call_count: deepSeekCallCount
        },
        sources: buildSources({ context, request, hasModelAnswer: Boolean(parsed?.answer) }),
        route: {
          local_db_used: hasPersonalContext(request.compact_context),
          local_knowledge_used: localKnowledge.length > 0,
          online_tool_called: false,
          llm_called: true
        }
      });

      if (!normalized.answer) {
        throw new Error("DeepSeek JSON response did not include answer");
      }
      return normalized;
    }
  };
}

function mergeCompactContext(serverContext, clientContext) {
  return {
    ...serverContext,
    today: clientContext?.today ?? {},
    recent_records: clientContext?.recent_records ?? [],
    matched_patterns: clientContext?.matched_patterns ?? [],
    local_knowledge: [
      ...(clientContext?.local_knowledge ?? []),
      ...(serverContext?.local_knowledge ?? [])
    ]
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
