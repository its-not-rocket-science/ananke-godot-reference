/**
 * ananke-godot-sidecar/server.js
 *
 * Node.js HTTP sidecar that drives the Ananke simulation at 20 Hz and exposes
 * a snapshot endpoint for Godot to poll.
 *
 * Endpoints:
 *   GET /health  →  { "ok": true }
 *   GET /state   →  AnankeSnapshot[] (see type below)
 *
 * TODO (CE-6): Upgrade to WebSocket push so Godot receives frames without
 * polling. Use the `ws` package and push a snapshot after each stepWorld call.
 *
 * Usage:
 *   npm install
 *   node server.js          # production
 *   node --watch server.js  # auto-restart on file change (dev)
 */

import http from "node:http";
import {
  createWorld,
  stepWorld,
  extractRigSnapshots,
  buildAICommands,
  buildWorldIndex,
  buildSpatialIndex,
  AI_PRESETS,
  SCALE,
} from "@its-not-rocket-science/ananke";

// ── Configuration ─────────────────────────────────────────────────────────────

const PORT       = 3000;
const TICK_HZ    = 20;          // Must match TICK_HZ in Ananke kernel (src/sim/tick.ts)
const TICK_MS    = 1000 / TICK_HZ;
const WORLD_SEED = 42;

// ── World setup ───────────────────────────────────────────────────────────────

/**
 * Build the initial WorldState with two KNIGHT_INFANTRY entities on opposing
 * teams, positioned 0.6 m apart (the default close-combat spacing).
 *
 * createWorld() is deterministic: same seed + same specs → identical entity
 * attributes every time.
 *
 * @type {import("@its-not-rocket-science/ananke").WorldState}
 */
const world = createWorld(WORLD_SEED, [
  {
    id:        1,
    teamId:    1,
    seed:      1001,
    archetype: "KNIGHT_INFANTRY",
    weaponId:  "wpn_longsword",
    armourId:  "arm_plate",
    x_m:       0.0,
    y_m:       0.0,
  },
  {
    id:        2,
    teamId:    2,
    seed:      2001,
    archetype: "KNIGHT_INFANTRY",
    weaponId:  "wpn_longsword",
    armourId:  "arm_plate",
    x_m:       0.6,
    y_m:       0.0,
  },
]);

// KernelContext: passed to stepWorld each tick.
// trace: null disables per-tick tracing (use metrics.CollectingTrace in dev if needed).
/** @type {import("@its-not-rocket-science/ananke").KernelContext} */
const ctx = { trace: null };

// AI policy map: both entities use the default aggressive melee AI.
// AI_PRESETS.aggressiveMelee makes entities attack the nearest opponent.
/** @type {Map<number, import("@its-not-rocket-science/ananke").AIPolicy>} */
const policyMap = new Map([
  [1, AI_PRESETS.aggressiveMelee],
  [2, AI_PRESETS.aggressiveMelee],
]);

// ── Snapshot state ────────────────────────────────────────────────────────────

/**
 * The latest rig snapshots, refreshed every tick.
 * Godot reads this on each poll.
 *
 * @type {import("@its-not-rocket-science/ananke").RigSnapshot[]}
 */
let latestSnapshots = [];

// Convert fixed-point position to real metres for renderer consumption.
// Ananke stores positions as integers: SCALE.m = 1000, so 600 = 0.6 m.
/**
 * @param {import("@its-not-rocket-science/ananke").Vec3} pos_m Fixed-point Vec3
 * @returns {{ x: number, y: number, z: number }}
 */
function toRealMetres(pos_m) {
  return {
    x: pos_m.x / SCALE.m,
    y: pos_m.y / SCALE.m,
    z: pos_m.z / SCALE.m,
  };
}

/**
 * Serialise a RigSnapshot into the wire format Godot expects.
 * All Q values are left as integers (0–18000); GDScript divides by SCALE_Q = 18000.
 *
 * @param {import("@its-not-rocket-science/ananke").RigSnapshot} snap
 * @param {import("@its-not-rocket-science/ananke").Entity}      entity
 * @returns {object}
 */
function serialiseSnapshot(snap, entity) {
  return {
    entityId:    snap.entityId,
    teamId:      snap.teamId,
    tick:        snap.tick,
    position:    toRealMetres(entity.position_m),
    animation:   snap.animation,
    pose:        snap.pose,
    grapple:     snap.grapple,
    // Convenience fields so GDScript does not need to dig into animation object.
    dead:        snap.animation.dead,
    unconscious: snap.animation.unconscious,
  };
}

// ── Simulation loop ───────────────────────────────────────────────────────────

/**
 * Step the world one tick.
 * Called by setInterval at TICK_HZ.
 */
function tick() {
  // Stop advancing once all entities are dead.
  const anyAlive = world.entities.some(e => !e.injury.dead);
  if (!anyAlive) return;

  // Build spatial and world indices required by the AI and kernel.
  const index   = buildWorldIndex(world);
  const spatial = buildSpatialIndex(world);

  // Generate AI commands for all entities with a policy.
  const cmds = buildAICommands(world, index, spatial, id => policyMap.get(id));

  // Advance the simulation by one tick (1/20 s).
  stepWorld(world, cmds, ctx);

  // Extract rig snapshots for all entities.
  const rigs = extractRigSnapshots(world);

  // Build serialised snapshot list.
  latestSnapshots = rigs.map(snap => {
    const entity = world.entities.find(e => e.id === snap.entityId);
    return serialiseSnapshot(snap, entity);
  });
}

// Start the simulation loop.
const intervalId = setInterval(tick, TICK_MS);

// ── HTTP server ───────────────────────────────────────────────────────────────

const server = http.createServer((req, res) => {
  // CORS headers — allow Godot's HTTP client on any origin.
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Content-Type", "application/json");

  if (req.method === "GET" && req.url === "/health") {
    res.writeHead(200);
    res.end(JSON.stringify({ ok: true, tick: world.tick }));
    return;
  }

  if (req.method === "GET" && req.url === "/state") {
    res.writeHead(200);
    res.end(JSON.stringify(latestSnapshots));
    return;
  }

  // TODO (CE-6): Handle WebSocket upgrade here.
  // if (req.headers.upgrade?.toLowerCase() === "websocket") { ... }

  res.writeHead(404);
  res.end(JSON.stringify({ error: "Not found" }));
});

server.listen(PORT, "127.0.0.1", () => {
  console.log(`Ananke Godot sidecar running on http://127.0.0.1:${PORT}`);
  console.log(`  Simulation: ${TICK_HZ} Hz  seed=${WORLD_SEED}`);
  console.log(`  Entities:   ${world.entities.map(e => `#${e.id} team${e.teamId}`).join(", ")}`);
  console.log(`  GET /health   →  { ok: true }`);
  console.log(`  GET /state    →  entity snapshot array`);
});

// ── Graceful shutdown ─────────────────────────────────────────────────────────

process.on("SIGTERM", () => {
  console.log("SIGTERM received — shutting down sidecar.");
  clearInterval(intervalId);
  server.close(() => process.exit(0));
});

process.on("SIGINT", () => {
  console.log("SIGINT received — shutting down sidecar.");
  clearInterval(intervalId);
  server.close(() => process.exit(0));
});
