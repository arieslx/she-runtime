import { ServiceError } from "../errors/serviceError.js";

export function createDeepSeekClient(config, fetchImpl = fetch) {
  return {
    async createChatCompletion(messages) {
      if (!config.apiKey) {
        throw new ServiceError("configuration_error");
      }

      const controller = new AbortController();
      const timeout = setTimeout(
        () => controller.abort(),
        config.timeoutMs
      );

      try {
        const response = await fetchImpl(
          `${config.baseUrl}/chat/completions`,
          {
            method: "POST",
            signal: controller.signal,
            headers: {
              "Content-Type": "application/json",
              Authorization: `Bearer ${config.apiKey}`
            },
            body: JSON.stringify({
              model: config.model,
              messages,
              thinking: { type: config.thinkingMode },
              response_format: { type: "json_object" },
              temperature: 0.3,
              max_tokens: config.maxTokens
            })
          }
        );

        const payload = await response.json().catch(() => ({}));

        if (!response.ok) {
          if (response.status === 401 || response.status === 403) {
            throw new ServiceError("llm_auth_failed");
          }
          if (response.status === 429) {
            throw new ServiceError("llm_rate_limited");
          }
          throw new ServiceError("llm_upstream_failed");
        }

        if (payload?.choices?.[0]?.finish_reason === "length") {
          throw new ServiceError("invalid_llm_response");
        }

        const content =
          payload?.choices?.[0]?.message?.content;

        if (
          typeof content !== "string" ||
          !content.trim()
        ) {
          throw new ServiceError("invalid_llm_response");
        }

        return content;
      } catch (error) {
        if (
          error instanceof Error &&
          error.name === "AbortError"
        ) {
          throw new ServiceError("llm_timeout", { cause: error });
        }
        if (error instanceof ServiceError) throw error;
        throw new ServiceError("llm_upstream_failed", { cause: error });
      } finally {
        clearTimeout(timeout);
      }
    }
  };
}
