const MAX_MESSAGE_LENGTH = 1_000;
const MAX_SUBJECTIVE_EVENTS = 12;
const MAX_CONTEXT_TEXT_LENGTH = 240;
const ALLOWED_CONFIRMATION_STATUSES = new Set(["confirmed", "corrected"]);
const ALLOWED_ANNOTATION_CONFIRMATION_STATUSES = new Set(["userConfirmed", "userCorrected"]);
const ALLOWED_METRICS = new Set([
  "sleep_hours",
  "sleep_onset_minutes",
  "hrv",
  "resting_heart_rate",
  "wrist_temperature",
  "respiratory_rate",
  "steps",
  "headphone_hours",
  "daylight_minutes",
  "mindful_minutes",
  "menses_days"
]);

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
      locale: normalizeLimitedString(body?.locale, 32) || "zh-CN",
      timezone: normalizeLimitedString(body?.timezone, 80) || "Asia/Shanghai",
      context: normalizeCompactContext(body?.context)
    }
  };
}

function normalizeCompactContext(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;

  const subjectiveEvents = Array.isArray(value.subjective_events)
    ? value.subjective_events
        .map(normalizeSubjectiveEvent)
        .filter((item) =>
          item.source_event_id &&
          item.confirmed_text &&
          ALLOWED_CONFIRMATION_STATUSES.has(item.confirmation_status)
        )
        .slice(0, MAX_SUBJECTIVE_EVENTS)
    : [];

  return {
    schema_version: normalizeInteger(value.schema_version, 1, 1, 10),
    generated_at: normalizeLimitedString(value.generated_at, 64),
    subjective_events: subjectiveEvents,
    health_summary: normalizeHealthSummary(value.health_summary)
  };
}

function normalizeSubjectiveEvent(item) {
  const annotations = Array.isArray(item?.annotations)
    ? item.annotations
        .map((annotation) => ({
          annotation_id: normalizeLimitedString(annotation?.annotation_id, 80),
          dimension: normalizeLimitedString(annotation?.dimension, 40),
          value: normalizeLimitedString(annotation?.value, 80),
          confidence: normalizeOptionalNumber(annotation?.confidence, 0, 1),
          extractor_version: normalizeLimitedString(annotation?.extractor_version, 80),
          confirmation_status: normalizeLimitedString(annotation?.confirmation_status, 40)
        }))
        .filter((annotation) =>
          annotation.annotation_id &&
          annotation.value &&
          ALLOWED_ANNOTATION_CONFIRMATION_STATUSES.has(annotation.confirmation_status)
        )
        .slice(0, 8)
    : [];

  return {
    source_event_id: normalizeLimitedString(item?.source_event_id, 80),
    occurred_at: normalizeLimitedString(item?.occurred_at, 64),
    timezone: normalizeLimitedString(item?.timezone, 80),
    source: normalizeLimitedString(item?.source, 40),
    topic_key: normalizeLimitedString(item?.topic_key, 100),
    confirmed_text: normalizeLimitedString(item?.confirmed_text, MAX_CONTEXT_TEXT_LENGTH),
    extraction_status: normalizeLimitedString(item?.extraction_status, 40),
    extraction_version: normalizeLimitedString(item?.extraction_version, 80),
    extraction_confidence: normalizeOptionalNumber(item?.extraction_confidence, 0, 1),
    confirmation_status: normalizeLimitedString(item?.confirmation_status, 40),
    revision: normalizeInteger(item?.revision, 1, 1, 1_000_000),
    annotations
  };
}

function normalizeHealthSummary(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return {
      window_start: "",
      window_end: "",
      effective_day_count: 0,
      latest_record_at: "",
      is_stale: true,
      metrics: []
    };
  }

  const metrics = Array.isArray(value.metrics)
    ? value.metrics
        .map((metric) => ({
          metric_key: normalizeLimitedString(metric?.metric_key, 60),
          sample_count: normalizeInteger(metric?.sample_count, 0, 0, 365),
          latest_value: normalizeOptionalNumber(metric?.latest_value),
          median_value: normalizeOptionalNumber(metric?.median_value),
          unit_key: normalizeLimitedString(metric?.unit_key, 60)
        }))
        .filter((metric) =>
          ALLOWED_METRICS.has(metric.metric_key) &&
          metric.latest_value !== null &&
          metric.median_value !== null
        )
        .slice(0, ALLOWED_METRICS.size)
    : [];

  return {
    window_start: normalizeLimitedString(value.window_start, 64),
    window_end: normalizeLimitedString(value.window_end, 64),
    effective_day_count: normalizeInteger(value.effective_day_count, 0, 0, 28),
    latest_record_at: normalizeLimitedString(value.latest_record_at, 64),
    is_stale: typeof value.is_stale === "boolean" ? value.is_stale : true,
    metrics
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
    usage: normalizeUsage(raw?.usage),
    sources: normalizeSources(raw?.sources)
  };
}

function normalizeString(value, fallback = "") {
  return typeof value === "string" ? value.trim() : fallback;
}

function normalizeLimitedString(value, limit) {
  return normalizeString(value).slice(0, limit);
}

function normalizeInteger(value, fallback, min, max) {
  const number = Number(value);
  if (!Number.isFinite(number)) return fallback;
  return Math.min(max, Math.max(min, Math.trunc(number)));
}

function normalizeOptionalNumber(value, min = -Number.MAX_VALUE, max = Number.MAX_VALUE) {
  if (value === null || value === undefined || value === "") return null;
  const number = Number(value);
  if (!Number.isFinite(number)) return null;
  return Math.min(max, Math.max(min, number));
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
