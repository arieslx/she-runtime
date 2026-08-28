import test from "node:test";
import assert from "node:assert/strict";
import { createApp } from "../src/app.js";

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
      timeoutMs: 30000
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
    assert.equal(JSON.stringify(body).includes("secret"), false);
  } finally {
    await new Promise((resolve, reject) => {
      server.close((error) => (error ? reject(error) : resolve()));
    });
  }
});
