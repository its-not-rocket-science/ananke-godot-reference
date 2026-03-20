/**
 * ananke-godot-sidecar/server.js
 *
 * Node.js sidecar that exposes health/state HTTP endpoints plus a WebSocket
 * snapshot stream for Godot.
 *
 * Endpoints:
 *   GET /health  →  { "ok": true }
 *   GET /state   →  Latest streamed snapshot frame
 *   WS  /        →  Snapshot frame pushed at 20 Hz
 */

import crypto from "node:crypto";
import http from "node:http";
import {
  createWorld,
  extractRigSnapshots,
  SCALE,
} from "@its-not-rocket-science/ananke";

const PORT = 7373;
const TICK_HZ = 20;
const TICK_MS = 1000 / TICK_HZ;
const WORLD_SEED = 42;
const WS_MAGIC = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";

const world = createWorld(WORLD_SEED, [
  {
    id: 1,
    teamId: 1,
    seed: 1001,
    archetype: "KNIGHT_INFANTRY",
    weaponId: "wpn_longsword",
    armourId: "arm_plate",
    x_m: 0.0,
    y_m: 0.0,
  },
  {
    id: 2,
    teamId: 2,
    seed: 2001,
    archetype: "KNIGHT_INFANTRY",
    weaponId: "wpn_longsword",
    armourId: "arm_plate",
    x_m: 0.6,
    y_m: 0.0,
  },
]);

let latestFrame = buildFrame(0, []);
let tickCounter = 0;
const wsClients = new Set();

function toRealMetres(pos_m) {
  return {
    x: pos_m.x / SCALE.m,
    y: pos_m.y / SCALE.m,
    z: pos_m.z / SCALE.m,
  };
}

function currentWorldPosition(entity) {
  const base = toRealMetres(entity.position_m);
  const phase = tickCounter / TICK_HZ + entity.id * 0.6;
  return {
    x: base.x + Math.sin(phase) * 0.08,
    y: base.y + Math.cos(phase * 0.5) * 0.03,
    z: base.z,
  };
}

function serialiseSnapshot(snap, entity) {
  return {
    entityId: snap.entityId,
    teamId: snap.teamId,
    tick: tickCounter,
    position: currentWorldPosition(entity),
    animation: {
      ...snap.animation,
      primaryState: tickCounter % (TICK_HZ * 4) < TICK_HZ * 2 ? "idle" : "guard",
    },
    pose: snap.pose,
    grapple: snap.grapple,
    dead: snap.animation.dead,
    unconscious: snap.animation.unconscious,
  };
}

function buildFrame(tick, snapshots) {
  return {
    type: "snapshot",
    tick,
    entityCount: snapshots.length,
    sentAtMs: Date.now(),
    snapshots,
  };
}

function encodeWebSocketFrame(payload) {
  const body = Buffer.from(payload, "utf8");
  const length = body.length;

  if (length < 126) {
    return Buffer.concat([Buffer.from([0x81, length]), body]);
  }

  if (length < 65536) {
    const header = Buffer.alloc(4);
    header[0] = 0x81;
    header[1] = 126;
    header.writeUInt16BE(length, 2);
    return Buffer.concat([header, body]);
  }

  const header = Buffer.alloc(10);
  header[0] = 0x81;
  header[1] = 127;
  header.writeBigUInt64BE(BigInt(length), 2);
  return Buffer.concat([header, body]);
}

function sendWebSocketJson(socket, frame) {
  if (socket.destroyed || !socket.writable) {
    wsClients.delete(socket);
    return;
  }
  socket.write(encodeWebSocketFrame(JSON.stringify(frame)));
}

function broadcastFrame(frame) {
  for (const socket of wsClients) {
    sendWebSocketJson(socket, frame);
  }
}

function tick() {
  tickCounter += 1;
  const rigs = extractRigSnapshots(world);
  const snapshots = rigs.map((snap) => {
    const entity = world.entities.find((candidate) => candidate.id === snap.entityId);
    return serialiseSnapshot(snap, entity);
  });
  latestFrame = buildFrame(tickCounter, snapshots);
  broadcastFrame(latestFrame);
}

const intervalId = setInterval(tick, TICK_MS);
tick();

const server = http.createServer((req, res) => {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Content-Type", "application/json");

  if (req.method === "GET" && req.url === "/health") {
    res.writeHead(200);
    res.end(JSON.stringify({ ok: true, tick: tickCounter, clients: wsClients.size }));
    return;
  }

  if (req.method === "GET" && req.url === "/state") {
    res.writeHead(200);
    res.end(JSON.stringify(latestFrame));
    return;
  }

  res.writeHead(404);
  res.end(JSON.stringify({ error: "Not found" }));
});

server.on("upgrade", (req, socket) => {
  if (req.url !== "/") {
    socket.destroy();
    return;
  }

  const key = req.headers["sec-websocket-key"];
  if (!key) {
    socket.destroy();
    return;
  }

  const accept = crypto.createHash("sha1").update(`${key}${WS_MAGIC}`).digest("base64");
  socket.write(
    [
      "HTTP/1.1 101 Switching Protocols",
      "Upgrade: websocket",
      "Connection: Upgrade",
      `Sec-WebSocket-Accept: ${accept}`,
      "",
      "",
    ].join("\r\n")
  );

  wsClients.add(socket);
  socket.on("close", () => wsClients.delete(socket));
  socket.on("end", () => wsClients.delete(socket));
  socket.on("error", () => wsClients.delete(socket));
  socket.on("data", () => {});
  sendWebSocketJson(socket, latestFrame);
});

server.listen(PORT, "127.0.0.1", () => {
  console.log(`Ananke Godot sidecar running on http://127.0.0.1:${PORT}`);
  console.log(`  WebSocket stream: ws://127.0.0.1:${PORT}`);
  console.log(`  Simulation: ${TICK_HZ} Hz  seed=${WORLD_SEED}`);
  console.log(`  Entities:   ${world.entities.map((entity) => `#${entity.id} team${entity.teamId}`).join(", ")}`);
  console.log(`  GET /health   →  { ok: true }`);
  console.log(`  GET /state    →  latest snapshot frame`);
});

function shutdown(signal) {
  console.log(`${signal} received — shutting down sidecar.`);
  clearInterval(intervalId);
  for (const socket of wsClients) {
    if (!socket.destroyed) {
      socket.end();
    }
  }
  server.close(() => process.exit(0));
}

process.on("SIGTERM", () => shutdown("SIGTERM"));
process.on("SIGINT", () => shutdown("SIGINT"));
