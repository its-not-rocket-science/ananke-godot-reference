# ananke-godot-reference — Roadmap

## M1 — Entity positions over HTTP polling ✅ COMPLETE

**Status:** Complete

- Sidecar (`sidecar/server.js`) runs `stepWorld` at 20 Hz and serves entity state over HTTP.
- `AnankeController.gd` polls `GET /state` every 50 ms and drives `AnankeCharacter.gd` nodes.
- `AnankeCharacter.gd` renders a procedural capsule rig with per-segment damage colouring,
  arm/tilt animation, and flash effects for attack and shock events.
- `mappings/humanoid.json` documents the Ananke segment ID → Godot node mapping.
- `SCALE.Q = 10000` (fixed — was erroneously 18000 in earlier revisions).

Acceptance criteria — all met:
- Two procedural humanoid rigs move in the Godot viewport driven by Ananke positions.
- `GET /health` returns `{ "ok": true }`.
- Sidecar exits cleanly on SIGTERM.
- Per-region damage tinting (surface/structural) visible on body parts.

Stretch goal: Upgrade HTTP polling to WebSocket push (CE-6) for lower latency.
Alternative: use the `renderer-bridge.ts` WebSocket server in the ananke repo
(`npm run run:renderer-bridge` → `ws://localhost:3001/bridge`).

---

## M2 — Skeleton rig: segment IDs → Skeleton3D bones

- Map `RigSnapshot.pose[].segmentId` values from `extractRigSnapshots` to `Skeleton3D` bone names using a JSON mapping file (`mappings/humanoid.json`).
- Drive bone transforms from `MassDistribution.cogOffset_m` and canonical segment offsets.
- Expose `BodyPlanMapping` loader in GDScript.

Reference: `SegmentMapping` and `BodyPlanMapping` interfaces in `@its-not-rocket-science/ananke` bridge API.

---

## M3 — AnimationPlayer state machine from AnimationHints

- Create an `AnimationTree` with a `AnimationNodeStateMachine` covering states: `Idle`, `Walk`, `Run`, `Sprint`, `Crawl`, `Guard`, `Attack`, `Prone`, `KO`, `Dead`.
- Drive transitions from `AnimationHints` fields in the sidecar snapshot.
- Blend weights (guardingQ, attackingQ, shockQ) map to `AnimationNodeBlend2` weights after dividing by `SCALE.Q` (10000).
- Stagger / flinch overlay driven by `shockQ`.

---

## M4 — GrapplePoseConstraint → FABRIK IK constraints

- When `grapple.isHeld = true`, apply a `SkeletonIK3D` or `XRBodyModifier3D` constraint locking the held entity's root to an attachment point on the holder.
- `position` field (`"standing"`, `"prone"`, `"pinned"`) selects the IK target anchor.
- `gripQ` (0–10000) drives a hand-close blend shape on the holder mesh.
- Release IK constraint when `grapple.isHeld` becomes false.

---

## M5 — Full Knight vs Brawler demo scene with UI

- Replace placeholder MeshInstance3D nodes with fully rigged GLTF humanoid meshes.
- HUD overlay showing:
  - Per-entity shock bar (shockQ / SCALE.Q).
  - Fluid loss / fatigue bar.
  - Dead / KO state indicator.
- Demo scene uses the same `KNIGHT_INFANTRY` vs `HUMAN_BASE` setup from the vertical slice.
- Replay export: press R to dump the sidecar's tick log to a JSON file for replay in `replayTo()`.
