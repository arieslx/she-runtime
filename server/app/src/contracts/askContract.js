import { randomUUID } from "node:crypto";

const MAX_MESSAGE_LENGTH = 1_000;
const MAX_REQUEST_ID_LENGTH = 128;
const MAX_RECORDS = 8;
const MAX_RECORD_TEXT_LENGTH = 240;
const MAX_TAGS = 6;
const MAX_TAG_LENGTH = 32;
const MAX_PATTERNS = 4;
const MAX_KNOWLEDGE_ITEMS = 4;
const MODEL_RESPONSE_KEYS = new Set(["answer", "basis", "safety_note", "follow_up"]);

export function parseAskRequest(body) {
  if (!isPlainObject(body)) return invalid("request body must be an object");
  const message = strictString(body.message, MAX_MESSAGE_LENGTH);
  if (!message) return invalid("message is required or too long");

  const protocolVersion = body.protocol_version ?? 1;
  if (protocolVersion !== 1 && protocolVersion !== 2) return invalid("unsupported protocol_version");

  const requestID = body.request_id === undefined
    ? randomUUID()
    : strictString(body.request_id, MAX_REQUEST_ID_LENGTH);
  if (!requestID) return invalid("request_id is invalid");

  const locale = strictString(body.locale ?? "zh-CN", 16);
  const timezone = strictString(body.timezone ?? "Asia/Shanghai", 64);
  if (!locale || !timezone) return invalid("locale or timezone is invalid");

  const contextResult = parseCompactContext(body.compact_context, protocolVersion);
  if (!contextResult.ok) return contextResult;
  return {
    ok: true,
    value: {
      protocol_version: protocolVersion,
      message,
      locale,
      timezone,
      request_id: requestID,
      compact_context: contextResult.value
    }
  };
}

function parseCompactContext(raw, protocolVersion) {
  if (raw === undefined && protocolVersion === 1) return { ok: true, value: emptyCompactContext() };
  if (!isPlainObject(raw)) return invalid("compact_context must be an object");

  const today = parseToday(raw.today);
  if (!today.ok) return today;
  const recentRecords = parseArray(raw.recent_records, MAX_RECORDS, parseRecentRecord, "recent_records");
  if (!recentRecords.ok) return recentRecords;
  const matchedPatterns = parseArray(raw.matched_patterns, MAX_PATTERNS, parsePattern, "matched_patterns");
  if (!matchedPatterns.ok) return matchedPatterns;
  const localKnowledge = parseArray(raw.local_knowledge, MAX_KNOWLEDGE_ITEMS, parseKnowledge, "local_knowledge");
  if (!localKnowledge.ok) return localKnowledge;
  return {
    ok: true,
    value: {
      today: today.value,
      recent_records: recentRecords.value,
      matched_patterns: matchedPatterns.value,
      local_knowledge: localKnowledge.value
    }
  };
}

function parseToday(raw) {
  if (raw === undefined || raw === null) return { ok: true, value: {} };
  if (!isPlainObject(raw)) return invalid("compact_context.today must be an object");
  const date = strictString(raw.date, 10);
  const recordCount = raw.record_count;
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date) || !isBoundedInteger(recordCount, 0, MAX_RECORDS)) {
    return invalid("compact_context.today is invalid");
  }
  return { ok: true, value: { date, record_count: recordCount } };
}

function parseRecentRecord(raw) {
  if (!isPlainObject(raw)) return null;
  const createdAt = strictString(raw.created_at, 40);
  const eventType = strictString(raw.event_type, 64);
  const text = strictString(raw.text, MAX_RECORD_TEXT_LENGTH, true);
  if (!createdAt || Number.isNaN(Date.parse(createdAt)) || !eventType || text === null) return null;
  if (!Array.isArray(raw.tags) || raw.tags.length > MAX_TAGS) return null;
  const tags = raw.tags.map((tag) => strictString(tag, MAX_TAG_LENGTH)).filter(Boolean);
  if (tags.length !== raw.tags.length) return null;
  return { created_at: createdAt, event_type: eventType, text, tags };
}

function parsePattern(raw) {
  if (!isPlainObject(raw)) return null;
  const patternID = strictString(raw.pattern_id, 64);
  const summary = strictString(raw.summary, 240);
  return patternID && summary ? { pattern_id: patternID, summary } : null;
}

function parseKnowledge(raw) {
  if (!isPlainObject(raw)) return null;
  const sourceID = strictString(raw.source_id, 64);
  const title = strictString(raw.title, 120);
  const snippet = strictString(raw.snippet, 500);
  return sourceID && title && snippet ? { source_id: sourceID, title, snippet } : null;
}

function parseArray(raw, limit, parser, fieldName) {
  if (raw === undefined) return { ok: true, value: [] };
  if (!Array.isArray(raw) || raw.length > limit) return invalid(`compact_context.${fieldName} is invalid`);
  const value = raw.map(parser);
  return value.some((item) => item === null)
    ? invalid(`compact_context.${fieldName} contains an invalid item`)
    : { ok: true, value };
}

function emptyCompactContext() {
  return { today: {}, recent_records: [], matched_patterns: [], local_knowledge: [] };
}

function strictString(value, maximumLength, allowEmpty = false) {
  if (typeof value !== "string") return null;
  const normalized = value.trim();
  if ((!allowEmpty && !normalized) || normalized.length > maximumLength) return null;
  return normalized;
}

function optionalStrictString(value, maximumLength) {
  if (value === undefined) return "";
  return strictString(value, maximumLength, true);
}

function isBoundedInteger(value, minimum, maximum) {
  return Number.isInteger(value) && value >= minimum && value <= maximum;
}

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function invalid(error) {
  return { ok: false, status: 400, error };
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
    request_id: normalizeString(raw?.request_id),
    answer: normalizeString(raw?.answer),
    basis,
    safety_note: normalizeString(raw?.safety_note),
    follow_up: normalizeString(raw?.follow_up),
    usage: normalizeUsage(raw?.usage),
    sources: normalizeSources(raw?.sources),
    route: normalizeRoute(raw?.route)
  };
}

export function parseAskModelResponse(content) {
  let raw;
  try {
    raw = JSON.parse(content);
  } catch {
    return { ok: false, error: "model response is not valid JSON" };
  }

  if (!isPlainObject(raw) || Object.keys(raw).some((key) => !MODEL_RESPONSE_KEYS.has(key))) {
    return { ok: false, error: "model response has an invalid object shape" };
  }

  const answer = strictString(raw.answer, 4_000);
  if (!answer) return { ok: false, error: "model response answer is missing or invalid" };

  const safetyNote = optionalStrictString(raw.safety_note, 500);
  const followUp = optionalStrictString(raw.follow_up, 500);
  if (safetyNote === null || followUp === null) {
    return { ok: false, error: "model response text field is invalid" };
  }

  const basis = raw.basis ?? [];
  if (!Array.isArray(basis) || basis.length > 3) {
    return { ok: false, error: "model response basis is invalid" };
  }
  const parsedBasis = basis.map((item) => {
    if (!isPlainObject(item) || Object.keys(item).some((key) => key !== "label" && key !== "value")) return null;
    const label = strictString(item.label, 80);
    const value = strictString(item.value, 500);
    return label && value ? { label, value } : null;
  });
  if (parsedBasis.some((item) => item === null)) {
    return { ok: false, error: "model response basis contains an invalid item" };
  }

  return {
    ok: true,
    value: {
      answer,
      basis: parsedBasis,
      safety_note: safetyNote,
      follow_up: followUp
    }
  };
}

function normalizeRoute(value) {
  return {
    local_db_used: value?.local_db_used === true,
    local_knowledge_used: value?.local_knowledge_used === true,
    online_tool_called: value?.online_tool_called === true,
    llm_called: value?.llm_called === true
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

function normalizeSources(value) {
  if (!Array.isArray(value)) return [];
  return value
    .map((item) => ({
      source_id: normalizeString(item?.source_id),
      source_type: normalizeString(item?.source_type),
      label: normalizeString(item?.label),
      path: normalizeString(item?.path),
      url: normalizeString(item?.url),
      status: normalizeString(item?.status),
      detail: normalizeString(item?.detail)
    }))
    .filter((item) => item.source_id || item.label);
}
