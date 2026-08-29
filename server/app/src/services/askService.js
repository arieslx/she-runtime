import { getRequestAskContext } from "../context/requestAskContext.js";
import { normalizeAskResponse } from "../contracts/askContract.js";
import { askSystemPrompt } from "../prompts/askSystemPrompt.js";
import { incrementDeepSeekCallCount } from "./usageCounter.js";

export function createAskService({
  deepSeekClient,
  contextProvider = getRequestAskContext,
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
            request: {
              message: request.message,
              locale: request.locale,
              timezone: request.timezone
            },
            compact_context: context
          })
        }
      ];

      const content = await deepSeekClient.createChatCompletion(messages);
      const deepSeekCallCount = incrementDeepSeekCallCount();
      const parsed = enforceProductBoundary(parseModelJson(content), request.locale);
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

function enforceProductBoundary(parsed, locale) {
  const visibleText = [
    parsed?.answer,
    parsed?.follow_up,
    ...(Array.isArray(parsed?.basis)
      ? parsed.basis.flatMap((item) => [item?.label, item?.value])
      : [])
  ].filter((value) => typeof value === "string").join(" ");
  const disallowed = [
    /导致/u,
    /引起/u,
    /造成/u,
    /证明(?:了)?/u,
    /诊断为/u,
    /确诊/u,
    /你患有/u,
    /一定是/u,
    /肯定是/u,
    /\bcaus(?:e|es|ed|ing)\b/iu,
    /\bdue\s+to\b/iu,
    /\bbecause\s+of\b/iu,
    /\bproves?\b/iu,
    /\bdiagnos(?:e|ed|is)\b/iu,
    /\bdefinitely\b/iu
  ];
  if (!disallowed.some((pattern) => pattern.test(visibleText))) return parsed;

  const english = locale === "en-US";
  return {
    ...parsed,
    answer: english
      ? "The records only show what appeared in the same observation window. They are not enough to determine a cause."
      : "现有记录只说明这些情况出现在同一个观察窗口，还不足以判断原因。",
    basis: [],
    safety_note: english
      ? "Co-occurrence is not causation or a medical diagnosis."
      : "共同出现不代表因果，也不是医学诊断。",
    follow_up: english
      ? "Would you like to keep observing this window?"
      : "要继续观察这个时间窗口吗？"
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

  const subjectiveEvents = Array.isArray(context?.subjective_events)
    ? context.subjective_events
    : [];
  for (const event of subjectiveEvents) {
    sources.push({
      source_id: event.source_event_id,
      source_type: "subjective_event",
      label: request.locale === "en-US" ? "Confirmed user statement" : "用户确认的陈述",
      detail: [event.occurred_at, event.source].filter(Boolean).join(" · ")
    });
  }

  const healthSummary = context?.health_summary;
  if (healthSummary?.window_start || healthSummary?.metrics?.length) {
    sources.push({
      source_id: `health-summary:${healthSummary.window_start}:${healthSummary.window_end}`,
      source_type: "health_summary",
      label: request.locale === "en-US" ? "Local health summary" : "本地健康摘要",
      detail: request.locale === "en-US"
        ? `${healthSummary.effective_day_count} effective days`
        : `${healthSummary.effective_day_count} 个有效日`
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
