import { createApp } from "./app.js";
import { loadConfig } from "./config/env.js";
import { createAskService } from "./services/askService.js";
import { createDeepSeekClient } from "./services/deepseekClient.js";
import { createKnowledgeSearch } from "./services/knowledgeSearch.js";

const config = loadConfig();
const deepSeekClient = createDeepSeekClient(config.deepSeek);
const knowledgeSearch = createKnowledgeSearch();
const askService = createAskService({ deepSeekClient, knowledgeSearch });
const app = createApp({ askService });

app.listen(config.port, () => {
  console.log(`Ask server listening on http://localhost:${config.port}`);
});
