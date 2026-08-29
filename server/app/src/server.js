import { createApp } from "./app.js";
import { loadConfig } from "./config/env.js";
import { createAskService } from "./services/askService.js";
import { createDeepSeekClient } from "./services/deepseekClient.js";
import { createKnowledgeSearch } from "./services/knowledgeSearch.js";

const config = loadConfig();
const deepSeekClient = createDeepSeekClient(config.deepSeek);
const knowledgeSearch = createKnowledgeSearch();
const askService = createAskService({
  deepSeekClient,
  knowledgeSearch
});
const app = createApp({ askService, config });

app.listen(config.port, config.host, () => {
  console.log(`Ask server listening on ${config.publicBaseUrl}`);
  console.log(`Ask endpoint: ${config.endpoints.ask}`);
  console.log(`Health endpoint: ${config.endpoints.health}`);
});
