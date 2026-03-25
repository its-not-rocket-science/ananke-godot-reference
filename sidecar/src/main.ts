import crypto from "node:crypto";
import http from "node:http";
import type { Duplex } from "node:stream";
import { performance } from "node:perf_hooks";
import { extractRigSnapshots, q, stepWorld, type CommandMap } from "@its-not-rocket-science/ananke";
import { loadWasmKernel, type WasmKernel } from "@its-not-rocket-science/ananke/wasm-kernel";
import { createScenario, DEFAULT_HOST, DEFAULT_PORT, TICK_MS } from "./scenario.js";
import { serialiseFrame, type WireFrame } from "./serialiser.js";

const host = process.env.ANANKE_HOST ?? DEFAULT_HOST;
const port = Number.parseInt(process.env.ANANKE_PORT ?? `${DEFAULT_PORT}`, 10);
const requestedTicks = Number.parseInt(process.env.ANANKE_MAX_TICKS ?? "0", 10);
const maxTicks = Number.isFinite(requestedTicks) ? requestedTicks : 0;

const scenario = createScenario();
let latestFrame: WireFrame = bootFrame();
let frameCount = 0;
let intervalId: NodeJS.Timeout | null = null;
const wsClients = new Set<Duplex>();
let wasmKernel: WasmKernel | null = null;

// Load WASM kernel in background — shadow-mode diagnostics only.
const WASM_LOG_EVERY = 100; // log summary every N ticks
loadWasmKernel().then(k => { wasmKernel = k; }).catch(err => {
  process.stderr.write(`[wasm] kernel unavailable: ${err.message}\n`);
});

const server = http.createServer((req, res) => {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Content-Type", "application/json");

  if (req.method === "GET" && req.url === "/health") {
    res.writeHead(200);
    res.end(JSON.stringify({ ok: true, scenarioId: scenario.id, tick: scenario.world.tick, frameCount }));
    return;
  }

  if (req.method === "GET" && req.url === "/frame") {
    res.writeHead(200);
    res.end(JSON.stringify(latestFrame));
    return;
  }

  if (req.method === "GET" && req.url === "/state") {
    res.writeHead(200);
    res.end(JSON.stringify(latestFrame.entities));
    return;
  }

  res.writeHead(404);
  res.end(JSON.stringify({ error: "Not found" }));
});

server.on("upgrade", (req, socket) => {
  if (req.url !== "/ws") {
    socket.destroy();
    return;
  }

  const key = req.headers["sec-websocket-key"];
  if (typeof key !== "string") {
    socket.destroy();
    return;
  }

  const accept = crypto
    .createHash("sha1")
    .update(`${key}258EAFA5-E914-47DA-95CA-C5AB0DC85B11`, "binary")
    .digest("base64");

  socket.write([
    "HTTP/1.1 101 Switching Protocols",
    "Upgrade: websocket",
    "Connection: Upgrade",
    `Sec-WebSocket-Accept: ${accept}`,
    "",
    "",
  ].join("\r\n"));

  wsClients.add(socket);
  socket.on("close", () => wsClients.delete(socket));
  socket.on("end", () => wsClients.delete(socket));
  socket.on("error", () => wsClients.delete(socket));
  socket.on("data", (chunk) => {
    if (chunk.length > 0 && (chunk[0] & 0x0f) === 0x8) {
      socket.end();
      wsClients.delete(socket);
    }
  });

  sendWebSocketFrame(socket, JSON.stringify(latestFrame));
});

server.listen(port, host, () => {
  console.log(`Ananke sidecar listening on ws://${host}:${port}/ws`);
  console.log(`HTTP health endpoint available at http://${host}:${port}/health`);
  startLoop();
});

function startLoop(): void {
  if (intervalId) {
    return;
  }

  intervalId = setInterval(() => {
    if (maxTicks > 0 && frameCount >= maxTicks) {
      stopLoop();
      return;
    }

    tick();
  }, TICK_MS);
}

function stopLoop(): void {
  if (!intervalId) {
    return;
  }

  clearInterval(intervalId);
  intervalId = null;
}

function tick(): void {
  const commands: CommandMap = scenario.buildCommands(scenario.world);
  stepWorld(scenario.world, commands, { tractionCoeff: q(1.0) });

  if (wasmKernel && frameCount % WASM_LOG_EVERY === 0) {
    const report = wasmKernel.shadowStep(scenario.world, scenario.world.tick);
    process.stderr.write(report.summary + "\n");
  }

  latestFrame = serialiseFrame({
    scenarioId: scenario.id,
    tick: scenario.world.tick,
    timestampMs: performance.now(),
    snapshots: extractRigSnapshots(scenario.world),
    entities: scenario.world.entities,
  });

  frameCount += 1;
  const payload = JSON.stringify(latestFrame);
  for (const client of wsClients) {
    if (!client.destroyed) {
      sendWebSocketFrame(client, payload);
    }
  }
}

function bootFrame(): WireFrame {
  return serialiseFrame({
    scenarioId: scenario.id,
    tick: scenario.world.tick,
    timestampMs: performance.now(),
    snapshots: extractRigSnapshots(scenario.world),
    entities: scenario.world.entities,
  });
}

function sendWebSocketFrame(socket: Duplex, payload: string): void {
  const body = Buffer.from(payload);
  const length = body.length;

  if (length >= 65536) {
    throw new Error("Frame too large for the minimal websocket implementation.");
  }

  let header: Buffer;
  if (length < 126) {
    header = Buffer.from([0x81, length]);
  } else {
    header = Buffer.alloc(4);
    header[0] = 0x81;
    header[1] = 126;
    header.writeUInt16BE(length, 2);
  }

  socket.write(Buffer.concat([header, body]));
}

function shutdown(signal: NodeJS.Signals): void {
  console.log(`${signal} received — shutting down sidecar.`);
  stopLoop();
  for (const client of wsClients) {
    client.end();
  }
  server.close(() => {
    process.exit(0);
  });
}

process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);
