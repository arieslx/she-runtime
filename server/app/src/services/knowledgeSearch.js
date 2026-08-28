import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const DEFAULT_KNOWLEDGE_DIR = path.resolve(__dirname, "../../../../knowledge/metrics");

const METRIC_ALIASES = {
  sleep: ["睡眠", "入睡", "深睡", "熬夜", "短睡", "sleep"],
  hrv: ["hrv", "HRV", "心率变异", "恢复", "压力"],
  rhr: ["静息心率", "resting", "心率", "rhr"],
  activity: ["活动", "步数", "运动", "训练", "散步", "activity"],
  cycle: ["周期", "月经", "经期", "黄体", "卵泡", "cycle"],
  wrist_temp: ["腕温", "体温", "温度", "wrist"],
  resp: ["呼吸", "呼吸频率", "resp"],
  hr_intraday: ["日内心率", "心率", "会议", "沟通", "疲劳"]
};

export function createKnowledgeSearch({ knowledgeDir = DEFAULT_KNOWLEDGE_DIR } = {}) {
  let cachedCards;

  return {
    async search(query, limit = 3) {
      cachedCards ??= await loadMetricCards(knowledgeDir);
      const tokens = tokenize(query);

      return cachedCards
        .map((card) => ({
          ...card,
          score: scoreCard(card, tokens)
        }))
        .filter((card) => card.score > 0)
        .sort((a, b) => b.score - a.score)
        .slice(0, limit)
        .map(({ score, content, ...card }) => card);
    }
  };
}

async function loadMetricCards(knowledgeDir) {
  const entries = await fs.readdir(knowledgeDir, { withFileTypes: true });
  const files = entries
    .filter((entry) => entry.isFile() && entry.name.startsWith("METRIC-") && entry.name.endsWith(".md"))
    .map((entry) => path.join(knowledgeDir, entry.name));

  return Promise.all(files.map(loadMetricCard));
}

async function loadMetricCard(filePath) {
  const content = await fs.readFile(filePath, "utf8");
  const frontmatter = parseFrontmatter(content);
  const cardId = frontmatter.card_id ?? path.basename(filePath, ".md");
  const metric = inferMetric(cardId);

  return {
    source_id: cardId,
    metric,
    metric_zh: frontmatter.metric_zh ?? cardId,
    safe_claim: frontmatter.safe_claim_style ?? "",
    avoid_claims: parseYamlList(frontmatter.avoid_claims).slice(0, 5),
    hypotheses: extractHypotheses(content).slice(0, 4),
    confounds: extractBulletsAfterHeading(content, "confounds").slice(0, 4),
    aliases: METRIC_ALIASES[metric] ?? [],
    content
  };
}

function parseFrontmatter(content) {
  const match = content.match(/^---\n([\s\S]*?)\n---/);
  if (!match) return {};

  const lines = match[1].split("\n");
  const result = {};
  let activeKey = null;

  for (const line of lines) {
    const keyValue = line.match(/^([A-Za-z0-9_-]+):\s*(.*)$/);
    if (keyValue) {
      activeKey = keyValue[1];
      result[activeKey] = keyValue[2];
      continue;
    }

    if (activeKey && /^\s+-\s+/.test(line)) {
      result[activeKey] += `\n${line}`;
    }
  }

  return result;
}

function parseYamlList(value = "") {
  if (!value.includes("\n")) return [];
  return value
    .split("\n")
    .map((line) => line.trim().replace(/^-\s*/, "").trim())
    .filter(Boolean);
}

function extractHypotheses(content) {
  const headingMatches = [...content.matchAll(/^###\s+(.+)$/gm)];
  if (headingMatches.length > 0) {
    return headingMatches
      .map((match) => match[1].trim())
      .filter((title) => /^H\d+/i.test(title));
  }

  const tableRows = content
    .split("\n")
    .filter((line) => /^\|\s*H?\d+\s*\|/.test(line));
  return tableRows.map((line) => {
    const columns = line.split("|").map((item) => item.trim()).filter(Boolean);
    return columns.slice(0, 3).join(" · ");
  });
}

function extractBulletsAfterHeading(content, headingKeyword) {
  const lines = content.split("\n");
  const start = lines.findIndex((line) => {
    const normalized = line.toLowerCase();
    return normalized.startsWith("##") && normalized.includes(headingKeyword);
  });
  if (start === -1) return [];

  const bullets = [];
  for (const line of lines.slice(start + 1)) {
    if (line.startsWith("##")) break;
    const bullet = line.match(/^-\s+\*\*(.+?)\*\*[：:]\s*(.+)$/) ?? line.match(/^-\s+(.+)$/);
    if (bullet) {
      bullets.push(bullet.slice(1).join("：").trim());
    }
  }
  return bullets;
}

function tokenize(query) {
  const lower = query.toLowerCase();
  const chars = [...new Set(lower.match(/[\p{Script=Han}A-Za-z0-9]+/gu) ?? [])];
  return chars.filter((token) => token.length >= 2);
}

function scoreCard(card, tokens) {
  let score = 0;
  const haystack = [
    card.source_id,
    card.metric_zh,
    card.safe_claim,
    ...card.aliases,
    ...card.hypotheses
  ].join("\n").toLowerCase();

  for (const token of tokens) {
    if (haystack.includes(token)) score += 1;
  }
  for (const alias of card.aliases) {
    if (tokens.includes(alias.toLowerCase())) score += 3;
  }
  return score;
}

function inferMetric(cardId) {
  const id = cardId.toLowerCase();
  if (id.includes("sleep")) return "sleep";
  if (id.includes("hrv")) return "hrv";
  if (id.includes("rhr")) return "rhr";
  if (id.includes("activity")) return "activity";
  if (id.includes("cycle")) return "cycle";
  if (id.includes("wrist-temp")) return "wrist_temp";
  if (id.includes("resp")) return "resp";
  if (id.includes("hr-intraday")) return "hr_intraday";
  return "unknown";
}
