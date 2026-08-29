export const AskRouteKind = Object.freeze({
  PERSONAL_INTERPRETATION: "personal_interpretation",
  EXTERNAL_KNOWLEDGE: "external_knowledge"
});

export function classifyAskRequest(request) {
  if (hasPersonalContext(request.compact_context) || hasPersonalLanguage(request.message)) {
    return AskRouteKind.PERSONAL_INTERPRETATION;
  }
  return AskRouteKind.EXTERNAL_KNOWLEDGE;
}

export function hasPersonalContext(context) {
  return Boolean(
    Object.keys(context?.today ?? {}).length ||
    context?.recent_records?.length ||
    context?.matched_patterns?.length
  );
}

function hasPersonalLanguage(message = "") {
  const normalized = message.toLowerCase();
  return ["我", "我的", "今天", "昨晚", "昨天", "最近", "刚才", "today", "my ", "recent", "last night"]
    .some((token) => normalized.includes(token));
}
