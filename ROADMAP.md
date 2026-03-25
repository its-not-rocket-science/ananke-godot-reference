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

## M2 — Skeleton rig: segment IDs → Skeleton3D bones ✅ COMPLETE

**Status:** Complete

- `SkeletonMapper.gd` maps all nine canonical Ananke segment IDs to `Skeleton3D` bone names via `DEFAULT_MAP`; override per-rig by calling `load_mapping_from_json("res://mappings/humanoid.json")`.
- `apply_snapshot` drives `set_bone_pose_position` and `set_bone_pose_rotation` per bone; `reset_pose` clears all bones each frame before re-applying.
- `mappings/humanoid.json` documents the default segment → Godot bone name mapping with coordinate convention (`ananke_y → godot_z`).
- Bone offset and rotation are derived procedurally from `impairmentQ` via `_derive_offset` / `_derive_rotation`.

---

## M3 — AnimationPlayer state machine from AnimationHints ✅ COMPLETE

**Status:** Complete

- `AnimationDriver.gd` resolves `primaryState` string to a state name via `STATE_MAP` (Idle / Walk / Run / Sprint / Crawl / Guard / Attack / Prone / KO / Dead).
- Calls `rig.set_animation_state(state, blend, animation)` — implement this method on your character rig scene to wire an `AnimationTree` or `AnimationPlayer`.
- `blend` = `max(injuryWeightQ, shockQ) / SCALE.Q` — use as the weight for a stagger additive track.
- `AnankeCharacter.gd` provides a reference `set_animation_state` implementation using colour tinting as a placeholder until real clips are assigned.

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
