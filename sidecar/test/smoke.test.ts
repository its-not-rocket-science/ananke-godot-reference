import test from "node:test";
import assert from "node:assert/strict";
import { once } from "node:events";
import { setTimeout as delay } from "node:timers/promises";
import { spawn } from "node:child_process";

const HOST = "127.0.0.1";
const PORT = 7474;
const BASE_URL = `http://${HOST}:${PORT}`;

async function waitForHealth(timeoutMs = 10000): Promise<void> {
  const started = Date.now();

  while (Date.now() - started < timeoutMs) {
    try {
      const response = await fetch(`${BASE_URL}/health`);
      if (response.ok) {
        return;
      }
    } catch {
      // keep polling until the child process is ready
    }

    await delay(100);
  }

  throw new Error("Timed out waiting for sidecar health endpoint.");
}

test("sidecar serves HTTP and websocket frames", async () => {
  const child = spawn("node", ["dist/src/main.js"], {
    cwd: process.cwd(),
    env: {
      ...process.env,
      ANANKE_HOST: HOST,
      ANANKE_PORT: `${PORT}`,
      ANANKE_MAX_TICKS: "30",
    },
    stdio: ["ignore", "pipe", "pipe"],
  });

  let stdout = "";
  let stderr = "";
  child.stdout.on("data", (chunk) => {
    stdout += chunk.toString();
  });
  child.stderr.on("data", (chunk) => {
    stderr += chunk.toString();
  });

  try {
    await waitForHealth();

    const healthResponse = await fetch(`${BASE_URL}/health`);
    assert.equal(healthResponse.status, 200);
    const health = await healthResponse.json() as { ok: boolean; scenarioId: string };
    assert.equal(health.ok, true);
    assert.equal(health.scenarioId, "knight-vs-brawler");

    await delay(250);

    const frameResponse = await fetch(`${BASE_URL}/frame`);
    assert.equal(frameResponse.status, 200);
    const frame = await frameResponse.json() as {
      schema: string;
      entities: Array<{
        position_m: { x: number };
        animation: { primaryState: string };
        poseModifiers: Array<{ localOffset_m: { x: number; y: number; z: number } }>;
      }>;
    };
    assert.equal(frame.schema, "ananke.bridge.frame.v1");
    assert.equal(frame.entities.length, 2);
    assert.equal(typeof frame.entities[0]?.animation.primaryState, "string");
    assert.ok(Array.isArray(frame.entities[0]?.poseModifiers));

    const socket = new WebSocket(`ws://${HOST}:${PORT}/ws`);
    await once(socket, "open");
    const message = await new Promise<MessageEvent<string>>((resolve, reject) => {
      socket.addEventListener("message", resolve, { once: true });
      socket.addEventListener("error", () => reject(new Error("websocket error")), { once: true });
    });
    const parsed = JSON.parse(message.data) as { entities: Array<{ entityId: number }> };
    assert.equal(parsed.entities.length, 2);
    socket.close();

    const stateResponse = await fetch(`${BASE_URL}/state`);
    assert.equal(stateResponse.status, 200);
    const state = await stateResponse.json() as Array<{ entityId: number; tick: number }>;
    assert.equal(state.length, 2);
    assert.ok(state.every((entity) => entity.tick >= 0));
  } finally {
    child.kill("SIGTERM");
    await once(child, "exit");
    if (stderr.trim().length > 0) {
      assert.fail(`sidecar wrote to stderr:\n${stderr}`);
    }
    assert.match(stdout, /Ananke sidecar listening/);
  }
});
