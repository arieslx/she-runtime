export async function getEmptyAskContext({ request, knowledgeSearch }) {
  const knowledge = knowledgeSearch
    ? await knowledgeSearch.search(request.message, 3)
    : [];

  return {
    user_window: null,
    today: {},
    recent_records: [],
    patterns: [],
    product_rules: [
      "只和用户自己的个人基线比较，不做人群平均比较",
      "说共现和值得观察，不说因果",
      "不给医学诊断或治疗建议",
      "没有个人数据时必须明确说明，不得推测或补造"
    ],
    local_knowledge: knowledge,
    knowledge_sources: summarizeSources(knowledge)
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
