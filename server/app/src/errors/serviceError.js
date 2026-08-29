const HTTP_STATUS_BY_CODE = Object.freeze({
  configuration_error: 503,
  llm_timeout: 504,
  llm_auth_failed: 502,
  llm_rate_limited: 503,
  llm_upstream_failed: 502,
  invalid_llm_response: 502,
  knowledge_search_failed: 502
});

const PUBLIC_MESSAGE_BY_CODE = Object.freeze({
  configuration_error: "Ask 服务尚未完成模型配置。",
  llm_timeout: "大模型响应超时，请稍后重试。",
  llm_auth_failed: "Ask 服务暂时无法访问大模型。",
  llm_rate_limited: "大模型服务当前繁忙，请稍后重试。",
  llm_upstream_failed: "大模型服务暂时不可用。",
  invalid_llm_response: "大模型返回了无法使用的结果。",
  knowledge_search_failed: "本地知识检索暂时不可用。"
});

export class ServiceError extends Error {
  constructor(code, options = {}) {
    super(code, options);
    this.name = "ServiceError";
    this.code = code;
    this.status = HTTP_STATUS_BY_CODE[code] ?? 500;
    this.publicMessage = PUBLIC_MESSAGE_BY_CODE[code] ?? "Ask 服务暂时不可用。";
  }
}

export function toServiceError(error) {
  return error instanceof ServiceError
    ? error
    : new ServiceError("llm_upstream_failed", { cause: error });
}
