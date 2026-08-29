import test from "node:test";
import assert from "node:assert/strict";
import { createApp } from "../src/app.js";
import { ServiceError } from "../src/errors/serviceError.js";

test("health endpoint exposes network and upstream configuration without api key", async () => {
  const config = {
    port: 3001,
    host: "0.0.0.0",
    endpoints: {
      ask: "http://192.168.1.10:3001/api/ask",
      health: "http://192.168.1.10:3001/api/health"
    },
    deepSeek: {
      apiKey: "secret",
      baseUrl: "https://api.deepseek.com",
      model: "deepseek-v4-flash",
      timeoutMs: 30000,
      maxTokens: 800,
      thinkingMode: "disabled"
    }
  };

  const app = createApp({
    config,
    askService: {
      async answer() {
        throw new Error("not used");
      }
    }
  });

  const server = app.listen(0);
  try {
    const { port } = server.address();
    const response = await fetch(`http://127.0.0.1:${port}/api/health`);
    const body = await response.json();

    assert.equal(response.status, 200);
    assert.equal(body.ok, true);
    assert.equal(body.endpoint, config.endpoints.ask);
    assert.equal(body.health_endpoint, config.endpoints.health);
    assert.equal(body.listen.host, config.host);
    assert.equal(body.listen.port, config.port);
    assert.equal(body.deepseek.configured, true);
    assert.equal(body.deepseek.model, config.deepSeek.model);
    assert.equal(body.deepseek.max_tokens, 800);
    assert.equal(body.deepseek.thinking_mode, "disabled");
    assert.equal(JSON.stringify(body).includes("secret"), false);
  } finally {
    await new Promise((resolve, reject) => {
      server.close((error) => (error ? reject(error) : resolve()));
    });
  }
});

test("ask endpoint returns stable error codes without upstream details", async () => {
  const app = createApp({
    config: {},
    askService: {
      async answer() {
        throw new ServiceError("llm_auth_failed", { cause: new Error("secret upstream response") });
      }
    }
  });
  const server = app.listen(0);
  try {
    const { port } = server.address();
    const response = await fetch(`http://127.0.0.1:${port}/api/ask`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ message: "test", request_id: "error-route-test" })
    });
    const body = await response.json();

    assert.equal(response.status, 502);
    assert.equal(body.request_id, "error-route-test");
    assert.equal(body.error, "llm_auth_failed");
    assert.equal(JSON.stringify(body).includes("secret upstream response"), false);
  } finally {
    await new Promise((resolve, reject) => {
      server.close((error) => (error ? reject(error) : resolve()));
    });
  }
});

test("ask endpoint requires the configured API key", async () => {
  const app = createApp({
    config: { askApiKey: "test-api-key" },
    askService: {
      async answer(request) {
        return { request_id: request.request_id, answer: "ok" };
      }
    }
  });
  const server = app.listen(0);
  try {
    const { port } = server.address();
    const url = `http://127.0.0.1:${port}/api/ask`;
    const request = {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ message: "test", request_id: "auth-route-test" })
    };

    const missingKeyResponse = await fetch(url, request);
    assert.equal(missingKeyResponse.status, 401);

    const wrongKeyResponse = await fetch(url, {
      ...request,
      headers: { ...request.headers, "X-Ask-API-Key": "wrong-key" }
    });
    assert.equal(wrongKeyResponse.status, 401);

    const validResponse = await fetch(url, {
      ...request,
      headers: { ...request.headers, "X-Ask-API-Key": "test-api-key" }
    });
    assert.equal(validResponse.status, 200);
  } finally {
    await new Promise((resolve, reject) => {
      server.close((error) => (error ? reject(error) : resolve()));
    });
  }
});
