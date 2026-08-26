const express = require("express");
const { Pool } = require("pg");
const Redis = require("ioredis");

const app = express();

const pool = new Pool({
  host: process.env.DB_HOST,
  user: process.env.DB_USER || "postgres",
  password: process.env.DB_PASSWORD || "postgres",
  database: process.env.DB_NAME || "postgres",
  port: 5432,
  // Fail fast + bounded pool: a slow/paused DB must not hang requests forever
  max: 10, // keep below postgres max_connections=20
  connectionTimeoutMillis: 2000,
  idleTimeoutMillis: 30000,
  statement_timeout: 5000, // server-side cap
  query_timeout: 5000, // client-side cap — covers a frozen/unreachable server too
});

const redis = new Redis({
  host: process.env.REDIS_HOST,
  port: 6379,
  // Bounded retries: a dead redis must not add ~20 retries of latency per request
  maxRetriesPerRequest: 1,
  enableOfflineQueue: false,
});
// Without an error listener ioredis floods logs on every reconnect attempt
redis.on("error", (err) => console.error("redis:", err.message));

app.get("/api/users", async (req, res) => {
  try {
    // pool.query acquires AND releases the connection even when the query
    // throws — the original connect/query/release pattern leaked a pool slot
    // on every failed query
    const result = await pool.query("SELECT NOW()");

    // Redis write is best-effort telemetry: its failure must not fail the request
    try {
      await redis.set("last_call", Date.now());
    } catch (err) {
      console.error("redis set failed:", err.message);
    }

    res.json({ ok: true, time: result.rows[0] });
  } catch (err) {
    console.error(err);
    res.status(500).json({ ok: false, error: err.message });
  }
});

app.get("/status", (req, res) => {
  res.json({ status: "ok" });
});

// Readiness: verifies the dependency chain, used for monitoring (not liveness)
app.get("/ready", async (req, res) => {
  try {
    await pool.query("SELECT 1");
    res.json({ ready: true });
  } catch (err) {
    res.status(503).json({ ready: false, error: err.message });
  }
});

const server = app.listen(3000, () => console.log("API running on 3000"));

// Graceful shutdown so rolling restarts do not drop in-flight requests
process.on("SIGTERM", () => {
  server.close(() => {
    pool.end().then(() => process.exit(0));
  });
});
