export function createDeepSeekClient(config, fetchImpl = fetch) {
  return {
    async createChatCompletion(messages) {
      if (!config.apiKey) {
        throw new Error("DEEPSEEK_API_KEY is not configured");
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
              thinking: { type: "disabled" },
              response_format: { type: "json_object" },
              temperature: 0.3,
              max_tokens: 800
            })
          }
        );

        const payload = await response.json().catch(() => ({}));

        if (!response.ok) {
          const detail =
            payload?.error?.message ??
            response.statusText;

          throw new Error(
            `DeepSeek request failed: ${detail}`
          );
        }

        const content =
          payload?.choices?.[0]?.message?.content;

        if (
          typeof content !== "string" ||
          !content.trim()
        ) {
          throw new Error(
            "DeepSeek response did not include message content"
          );
        }

        return content;
      } catch (error) {
        if (
          error instanceof Error &&
          error.name === "AbortError"
        ) {
          throw new Error(
            `DeepSeek request timed out after ${config.timeoutMs}ms`
          );
        }

        throw error;
      } finally {
        clearTimeout(timeout);
      }
    }
  };
}