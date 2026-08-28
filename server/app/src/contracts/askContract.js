const MAX_MESSAGE_LENGTH = 1_000;

export function parseAskRequest(body) {
  const message = typeof body?.message === "string" ? body.message.trim() : "";
  if (!message) {
    return { ok: false, status: 400, error: "message is required" };
  }
  if (message.length > MAX_MESSAGE_LENGTH) {
    return { ok: false, status: 400, error: "message is too long" };
  }

  return {
    ok: true,
    value: {
      message,
      locale: normalizeString(body?.locale, "zh-CN"),
      timezone: normalizeString(body?.timezone, "Asia/Shanghai")
    }
  };
}

export function normalizeAskResponse(raw) {
  const basis = Array.isArray(raw?.basis)
    ? raw.basis
        .map((item) => ({
          label: normalizeString(item?.label),
          value: normalizeString(item?.value)
        }))
        .filter((item) => item.label && item.value)
        .slice(0, 3)
    : [];

  return {
    answer: normalizeString(raw?.answer),
    basis,
    safety_note: normalizeString(raw?.safety_note),
    follow_up: normalizeString(raw?.follow_up),
    usage: normalizeUsage(raw?.usage)
  };
}

function normalizeString(value, fallback = "") {
  return typeof value === "string" ? value.trim() : fallback;
}

function normalizeUsage(value) {
  const deepSeekCallCount = Number(value?.deepseek_call_count ?? 0);
  return {
    deepseek_call_count: Number.isFinite(deepSeekCallCount) ? deepSeekCallCount : 0
  };
}
