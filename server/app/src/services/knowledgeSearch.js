import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const DEFAULT_KNOWLEDGE_DIR = path.resolve(__dirname, "../../../../knowledge");
const DEFAULT_SKILLS_DIR = path.resolve(__dirname, "../../../../.claude/skills");

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

export function createKnowledgeSearch({
  knowledgeDir = DEFAULT_KNOWLEDGE_DIR,
  skillsDir = DEFAULT_SKILLS_DIR,
  onlineSearch = null
} = {}) {
  let cachedLocalCards;

  return {
    async searchLocal(query, limit = 3) {
      cachedLocalCards ??= await loadLocalCards({ knowledgeDir, skillsDir });
      const tokens = tokenize(query);
      return rankCards(cachedLocalCards, tokens, limit, query);
    },
    async searchOnline(query, limit = 3) {
      return onlineSearch ? safeOnlineSearch({ onlineSearch, query, limit }) : [];
    },
    async search(query, limit = 3) {
      cachedLocalCards ??= await loadLocalCards({ knowledgeDir, skillsDir });
      return rankCards(cachedLocalCards, tokenize(query), limit, query);
    }
  };
}

async function loadLocalCards({ knowledgeDir, skillsDir }) {
  const [knowledgeCards, skillCards] = await Promise.all([
    loadKnowledgeCards(knowledgeDir),
    loadSkillCards(skillsDir)
  ]);
  return [...knowledgeCards, ...skillCards];
}

async function loadKnowledgeCards(knowledgeDir) {
  const files = await listMarkdownFiles(knowledgeDir);
  return Promise.all(files.map((filePath) => loadKnowledgeCard(filePath, knowledgeDir)));
}

async function loadSkillCards(skillsDir) {
  const files = await listMarkdownFiles(skillsDir);
  const skillFiles = files.filter((filePath) => path.basename(filePath) === "SKILL.md");
  return Promise.all(skillFiles.map((filePath) => loadSkillCard(filePath, skillsDir)));
}

async function listMarkdownFiles(rootDir) {
  const files = [];

  async function walk(dir) {
    let entries;
    try {
      entries = await fs.readdir(dir, { withFileTypes: true });
    } catch (error) {
      if (error?.code === "ENOENT") return;
      throw error;
    }

    for (const entry of entries) {
      const filePath = path.join(dir, entry.name);
      if (entry.isDirectory()) {
        await walk(filePath);
      } else if (entry.isFile() && entry.name.endsWith(".md")) {
        files.push(filePath);
      }
    }
  }

  await walk(rootDir);
  return files;
}

async function loadKnowledgeCard(filePath, knowledgeDir) {
  const content = await fs.readFile(filePath, "utf8");
  const frontmatter = parseFrontmatter(content);
  const cardId = frontmatter.card_id ?? path.basename(filePath, ".md");
  const metric = inferMetric(cardId);
  const metricLabel = frontmatter.metric_zh ?? cardId;
  const relativePath = path.relative(knowledgeDir, filePath);

  return {
    source_id: cardId,
    source_type: "local_repo",
    label: `本地知识库 · ${metricLabel}`,
    path: `knowledge/${relativePath}`,
    metric,
    metric_zh: metricLabel,
    safe_claim: frontmatter.safe_claim_style ?? "",
    action_type: frontmatter.action_type ?? "",
    avoid_claims: parseYamlList(frontmatter.avoid_claims).slice(0, 5),
    hypotheses: extractHypotheses(content).slice(0, 4),
    confounds: extractBulletsAfterHeading(content, "confounds").slice(0, 4),
    aliases: METRIC_ALIASES[metric] ?? [],
    content
  };
}

async function loadSkillCard(filePath, skillsDir) {
  const content = await fs.readFile(filePath, "utf8");
  const frontmatter = parseFrontmatter(content);
  const name = frontmatter.name ?? path.basename(path.dirname(filePath));
  const relativePath = path.relative(skillsDir, filePath);

  return {
    source_id: `SKILL-${name}`,
    source_type: "local_skill",
    label: `本地 Skill ${name}`,
    path: `.claude/skills/${relativePath}`,
    metric: "skill",
    metric_zh: name,
    safe_claim: frontmatter.description ?? firstParagraph(content),
    action_type: "skill_instruction",
    avoid_claims: extractNumberedItemsAfterHeading(content, "红线").slice(0, 5),
    hypotheses: extractNumberedItemsAfterHeading(content, "检索规则").slice(0, 4),
    confounds: extractNumberedItemsAfterHeading(content, "出稿前五关").slice(0, 4),
    aliases: [name, frontmatter.description ?? ""].filter(Boolean),
    content
  };
}

function rankCards(cards, tokens, limit, query) {
  return cards
    .map((card) => ({
      ...card,
      score: scoreCard(card, tokens, query)
    }))
    .filter((card) => card.score > 0)
    .sort((a, b) => b.score - a.score)
    .slice(0, limit)
    .map(stripPrivateFields);
}

async function safeOnlineSearch({ onlineSearch, query, limit }) {
  try {
    return (await onlineSearch.search(query, limit)).map((item) => ({
      source_id: item.source_id ?? item.url ?? item.title ?? "ONLINE",
      source_type: "online",
      label: item.label ?? `在线来源 ${item.title ?? item.url ?? "未命名"}`,
      url: item.url ?? "",
      title: item.title ?? "",
      snippet: item.snippet ?? "",
      safe_claim: item.snippet ?? "",
      avoid_claims: [],
      hypotheses: [],
      confounds: []
    }));
  } catch (error) {
    return [{
      source_id: "ONLINE-SEARCH-FAILED",
      source_type: "online",
      label: "在线检索失败",
      status: "failed",
      detail: error instanceof Error ? error.message : "Unknown online search error",
      safe_claim: "",
      avoid_claims: [],
      hypotheses: [],
      confounds: []
    }];
  }
}

function stripPrivateFields({ score, content, aliases, ...card }) {
  return card;
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

function extractNumberedItemsAfterHeading(content, headingKeyword) {
  const lines = content.split("\n");
  const start = lines.findIndex((line) => {
    const normalized = line.toLowerCase();
    return normalized.startsWith("##") && normalized.includes(headingKeyword.toLowerCase());
  });
  if (start === -1) return [];

  const items = [];
  for (const line of lines.slice(start + 1)) {
    if (line.startsWith("##")) break;
    const item = line.match(/^\d+\.\s+(.+)$/) ?? line.match(/^-\s+(.+)$/);
    if (item) items.push(item[1].trim());
  }
  return items;
}

function firstParagraph(content) {
  return content
    .replace(/^---\n[\s\S]*?\n---/, "")
    .split(/\n\s*\n/)
    .map((item) => item.replace(/^#+\s+/gm, "").trim())
    .find(Boolean) ?? "";
}

function tokenize(query) {
  const lower = query.toLowerCase();
  const chars = [...new Set(lower.match(/[\p{Script=Han}A-Za-z0-9]+/gu) ?? [])];
  return chars.filter((token) => token.length >= 2);
}

function scoreCard(card, tokens, query) {
  let score = 0;
  const normalizedQuery = query.toLowerCase();
  const haystack = [
    card.source_id,
    card.source_type,
    card.label,
    card.path,
    card.metric_zh,
    card.safe_claim,
    card.action_type,
    ...card.aliases,
    ...card.hypotheses,
    ...card.confounds
  ].join("\n").toLowerCase();

  for (const token of tokens) {
    if (haystack.includes(token)) score += 1;
  }
  for (const alias of card.aliases) {
    const normalizedAlias = alias.toLowerCase().trim();
    if (normalizedAlias && normalizedQuery.includes(normalizedAlias)) score += 3;
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
