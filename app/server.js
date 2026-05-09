const express = require("express");
const os = require("os");
const Redis = require("ioredis");

const app = express();
app.use(express.json());

const REDIS_HOST = process.env.REDIS_HOST || "localhost";
const APP_ENV = (process.env.APP_ENV || "dev").toLowerCase();

let redisClient;
function getRedis() {
  if (!redisClient) {
    redisClient = new Redis({
      host: REDIS_HOST,
      port: 6379,
      lazyConnect: true,
      maxRetriesPerRequest: 3,
      enableReadyCheck: true,
    });
  }
  return redisClient;
}

app.get("/api/health", async (req, res) => {
  try {
    const redis = getRedis();
    await redis.ping();
    res.json({
      status: "ok",
      hostname: os.hostname(),
      environment: APP_ENV,
      redis: "connected",
    });
  } catch (err) {
    res.status(503).json({
      status: "degraded",
      hostname: os.hostname(),
      environment: APP_ENV,
      redis: "unavailable",
      error: String(err.message || err),
    });
  }
});

app.get("/api/visits", async (req, res) => {
  const redis = getRedis();
  const count = await redis.incr("visits:counter");
  res.json({ visits: count, hostname: os.hostname(), environment: APP_ENV });
});

app.get("/api/messages", async (req, res) => {
  const redis = getRedis();
  const items = await redis.lrange("messages:list", 0, 49);
  res.json({
    messages: items.map((t) => {
      try {
        return JSON.parse(t);
      } catch {
        return { text: String(t), ts: null };
      }
    }),
    hostname: os.hostname(),
    environment: APP_ENV,
  });
});

app.post("/api/messages", async (req, res) => {
  const redis = getRedis();
  const text =
    typeof req.body?.text === "string"
      ? req.body.text.trim()
      : "";
  if (!text) {
    return res.status(400).json({ error: "Missing text", environment: APP_ENV });
  }
  const payload = JSON.stringify({
    text,
    ts: new Date().toISOString(),
  });
  await redis.lpush("messages:list", payload);
  res.status(201).json({ ok: true, hostname: os.hostname(), environment: APP_ENV });
});

const port = Number(process.env.PORT || 3000);

module.exports = { app, getRedis };

if (require.main === module) {
  const server = app.listen(port, "0.0.0.0", () => {
    console.log(`Listening on ${port} (hostname=${os.hostname()}, APP_ENV=${APP_ENV})`);
  });
  const shutdown = () => {
    server.close(() => process.exit(0));
  };
  process.on("SIGTERM", shutdown);
  process.on("SIGINT", shutdown);
}

module.exports = { app, getRedis };
