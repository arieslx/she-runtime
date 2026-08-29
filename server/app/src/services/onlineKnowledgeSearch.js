export function createOnlineKnowledgeSearch(config, fetchImpl = fetch) {
  if (!config?.endpoint) return null;

  return {
    async search(query, limit = 3) {
      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), config.timeoutMs ?? 5000);

      try {
        const response = await fetchImpl(config.endpoint, {
          method: "POST",
          signal: controller.signal,
          headers: {
            "Content-Type": "application/json"
          },
          body: JSON.stringify({ query, limit })
        });

        const payload = await response.json().catch(() => []);
        if (!response.ok) {
          const message = payload?.error?.message ?? response.statusText;
          throw new Error(`online knowledge search failed: ${message}`);
        }

        return Array.isArray(payload) ? payload : (payload?.items ?? []);
      } finally {
        clearTimeout(timeout);
      }
    }
  };
}
