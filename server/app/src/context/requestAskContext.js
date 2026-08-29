export async function getRequestAskContext({ request, knowledgeSearch }) {
  const knowledge = knowledgeSearch
    ? await knowledgeSearch.search(request.message, 3)
    : [];
  const supplied = request.context ?? emptyContext();

  return {
    schema_version: supplied.schema_version ?? 1,
    generated_at: supplied.generated_at ?? "",
    subjective_events: supplied.subjective_events ?? [],
    health_summary: supplied.health_summary ?? emptyContext().health_summary,
    product_rules: [
      "只使用请求中提供的用户记录和健康摘要，不补写不存在的个人事实",
      "单条陈述只能作为事实或同日共现，不能当作规律或因果",
      "只和用户自己的窗口内数据比较，不做人群平均比较",
      "不给医学诊断或治疗建议"
    ],
    local_knowledge: knowledge,
    knowledge_sources: summarizeSources(knowledge)
  };
}

function emptyContext() {
  return {
    schema_version: 1,
    generated_at: "",
    subjective_events: [],
    health_summary: {
      window_start: "",
      window_end: "",
      effective_day_count: 0,
      latest_record_at: "",
      is_stale: true,
      metrics: []
    }
  };
}

function summarizeSources(cards) {
  return cards.map((card) => ({
    source_id: card.source_id,
    source_type: card.source_type,
    label: card.label,
    path: card.path ?? "",
    url: card.url ?? ""
  }));
}
