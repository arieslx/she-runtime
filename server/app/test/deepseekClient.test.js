import test from "node:test";
import assert from "node:assert/strict";
import { createDeepSeekClient } from "../src/services/deepseekClient.js";

const config = {
  apiKey: "test-key",
  baseUrl: "https://api.deepseek.com",
  model: "deepseek-v4-flash",
  timeoutMs: 20,
  maxTokens: 800,
  thinkingMode: "disabled"
};

function jsonResponse(status, body) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" }
  });
}

test("DeepSeek client sends bounded JSON output with thinking disabled", async () => {
  let requestBody;
  const client = createDeepSeekClient(config, async (_url, options) => {
    requestBody = JSON.parse(options.body);
    return jsonResponse(200, {
      choices: [{ finish_reason: "stop", message: { content: JSON.stringify({ answer: "ok" }) } }]
    });
  });

  assert.equal(await client.createChatCompletion([{ role: "user", content: "json" }]), '{"answer":"ok"}');
  assert.deepEqual(requestBody.thinking, { type: "disabled" });
  assert.deepEqual(requestBody.response_format, { type: "json_object" });
  assert.equal(requestBody.max_tokens, 800);
});

test("DeepSeek client classifies missing configuration", async () => {
  const client = createDeepSeekClient({ ...config, apiKey: "" });
  await assert.rejects(() => client.createChatCompletion([]), { code: "configuration_error" });
});

for (const [status, code] of [[401, "llm_auth_failed"], [429, "llm_rate_limited"], [500, "llm_upstream_failed"]]) {
  test(`DeepSeek client maps HTTP ${status} to ${code}`, async () => {
    const client = createDeepSeekClient(config, async () => jsonResponse(status, {
      error: { message: "sensitive upstream detail" }
    }));
    await assert.rejects(() => client.createChatCompletion([]), { code });
  });
}

test("DeepSeek client classifies timeout", async () => {
  const client = createDeepSeekClient(config, async (_url, options) => new Promise((_resolve, reject) => {
    options.signal.addEventListener("abort", () => reject(new DOMException("aborted", "AbortError")));
  }));
  await assert.rejects(() => client.createChatCompletion([]), { code: "llm_timeout" });
});

test("DeepSeek client rejects empty and truncated output", async () => {
  const emptyClient = createDeepSeekClient(config, async () => jsonResponse(200, {
    choices: [{ finish_reason: "stop", message: { content: "" } }]
  }));
  const truncatedClient = createDeepSeekClient(config, async () => jsonResponse(200, {
    choices: [{ finish_reason: "length", message: { content: '{"answer":' } }]
  }));

  await assert.rejects(() => emptyClient.createChatCompletion([]), { code: "invalid_llm_response" });
  await assert.rejects(() => truncatedClient.createChatCompletion([]), { code: "invalid_llm_response" });
});
