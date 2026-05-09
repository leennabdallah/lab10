"use strict";

const assert = require("assert");
const Redis = require("ioredis");

describe("Redis integration", function () {
  this.timeout(15_000);

  let redis;

  before(function () {
    redis = new Redis({
      host: process.env.REDIS_HOST || "localhost",
      port: 6379,
      maxRetriesPerRequest: 3,
      connectTimeout: 5_000,
    });
  });

  after(async function () {
    if (!redis) {
      return;
    }
    try {
      if (redis.status === "ready") {
        await redis.quit();
      } else {
        redis.disconnect();
      }
    } catch {
      redis.disconnect();
    }
  });

  it("supports set/get", async () => {
    await redis.set("lab010:int:test", "value-1");
    const v = await redis.get("lab010:int:test");
    assert.strictEqual(v, "value-1");
  });

  it("supports counter increment", async () => {
    const key = "lab010:int:counter";
    await redis.del(key);
    assert.strictEqual(await redis.incr(key), 1);
    assert.strictEqual(await redis.incr(key), 2);
  });

  it("supports list push and read", async () => {
    const key = "lab010:int:list";
    await redis.del(key);
    await redis.lpush(key, "a", "b", "c");
    const vals = await redis.lrange(key, 0, -1);
    assert.deepStrictEqual(vals, ["c", "b", "a"]);
  });
});
