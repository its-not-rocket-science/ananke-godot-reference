# ananke-godot-reference — Roadmap

## M1 — Entity positions over WebSocket (current)

**Status:** In progress

- Sidecar runs `stepWorld` at 20 Hz and serves entity positions over HTTP (`GET /state`).
- `AnankeController.gd` polls `/state` every 50 ms and moves two `Node3D` placeholders.
- No bone mapping, no animation, no IK.

Acceptance criteria:
- Two cubes move in the Godot viewport driven by Ananke simulation positions.
- `GET /health` returns `{ "ok": true }`.
- Sidecar exits cleanly on SIGTERM.

Stretch goal: Upgrade HTTP polling to WebSocket push (CE-6) for lower latency.

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
- Blend weights (guardingQ, attackingQ, shockQ) map to `AnimationNodeBlend2` weights after dividing by `SCALE.Q` (18000).
- Stagger / flinch overlay driven by `shockQ`.

---

## M4 — GrapplePoseConstraint → FABRIK IK constraints

- When `grapple.isHeld = true`, apply a `SkeletonIK3D` or `XRBodyModifier3D` constraint locking the held entity's root to an attachment point on the holder.
- `position` field (`"standing"`, `"prone"`, `"pinned"`) selects the IK target anchor.
- `gripQ` (0–18000) drives a hand-close blend shape on the holder mesh.
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
