"use strict";

const assert = require("assert");
const request = require("supertest");

function stubRedis() {
  const store = { visits: 0, messages: [] };
  return {
    ping: async () => "PONG",
    incr: async (_k) => {
      store.visits += 1;
      return store.visits;
    },
    lrange: async (_k, _start, _stop) =>
      store.messages.slice(0, 50).map((m) => JSON.stringify(m)),
    lpush: async (_k, raw) => {
      store.messages.unshift(JSON.parse(raw));
      return store.messages.length;
    },
    on() {},
    quit: async () => {},
  };
}

describe("backend unit", () => {
  let app;

  before(() => {
    delete require.cache[require.resolve("./server.js")];
    delete require.cache[require.resolve("ioredis")];
    require.cache[require.resolve("ioredis")] = {
      id: require.resolve("ioredis"),
      filename: require.resolve("ioredis"),
      loaded: true,
      exports: function () {
        return stubRedis();
      },
    };
    process.env.APP_ENV = "test";
    process.env.REDIS_HOST = "localhost";
    // eslint-disable-next-line global-require
    ({ app } = require("./server.js"));
  });

  it("GET /api/health returns ok", async () => {
    const res = await request(app).get("/api/health");
    assert.strictEqual(res.status, 200);
    assert.strictEqual(res.body.status, "ok");
    assert.strictEqual(res.body.redis, "connected");
    assert.strictEqual(typeof res.body.hostname, "string");
    assert.strictEqual(res.body.environment, "test");
  });

  after(() => {
    delete require.cache[require.resolve("ioredis")];
    delete require.cache[require.resolve("./server.js")];
  });
});
