export async function getMockAskContext({ request, knowledgeSearch }) {
  const knowledge = knowledgeSearch
    ? await knowledgeSearch.search(request.message, 3)
    : [];

  return {
    user_window: "last_28_days",
    today: {
      recovery_status: "close_to_personal_baseline",
      meetings: {
        count: 3,
        total_minutes: 152,
        window: "13:40-17:10"
      }
    },
    patterns: [
      {
        id: "continuous-communication-drain",
        statement: "90 分钟以上连续沟通后，主观精力下降更常出现",
        sample_size: 8,
        confidence: "medium"
      },
      {
        id: "walk-recovery",
        statement: "15-30 分钟独处步行后，状态改善更常出现",
        sample_size: 8,
        confidence: "medium"
      }
    ],
    product_rules: [
      "只和用户自己的个人基线比较，不做人群平均比较",
      "说共现和值得观察，不说因果",
      "不给医学诊断或治疗建议"
    ],
    local_knowledge: knowledge
  };
}
