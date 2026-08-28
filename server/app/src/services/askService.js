import { getMockAskContext } from "../context/mockAskContext.js";
import { normalizeAskResponse } from "../contracts/askContract.js";
import { askSystemPrompt } from "../prompts/askSystemPrompt.js";
import { incrementDeepSeekCallCount } from "./usageCounter.js";

export function createAskService({
  deepSeekClient,
  contextProvider = getMockAskContext,
  knowledgeSearch
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
        }
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
