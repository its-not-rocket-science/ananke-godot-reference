# ananke-godot-reference

Godot 4 humanoid rig plugin driven by the [Ananke](https://github.com/its-not-rocket-science/ananke) physics simulation engine.

## What it is

This project demonstrates how to drive a Godot 4 scene with deterministic, physics-grounded character simulation from Ananke. Ananke runs in a Node.js sidecar process and exposes simulation state over HTTP (and eventually WebSocket). Godot polls the sidecar at 20 Hz, reads entity positions and animation state, and renders the result at 60 Hz using its own interpolation.

Simulation physics — impact energy, injury regions, stamina, grapple constraints, shock — are computed entirely by Ananke. Godot is a pure renderer.

## Architecture

```
┌─────────────────────────────────┐       HTTP / WebSocket (localhost:3000)
│  Node.js sidecar  (20 Hz)       │ ─────────────────────────────────────►
│  @its-not-rocket-science/ananke │                                        │
│  stepWorld → extractRigSnapshots│ ◄─────────────────────────────────────
│  GET /state  GET /health        │       JSON snapshot (positions, anim)
└─────────────────────────────────┘

                                        ┌──────────────────────────────────┐
                                        │  Godot 4 scene  (60 Hz)          │
                                        │  AnankeController.gd             │
                                        │  polls /state every 50 ms        │
                                        │  moves Node3D / Skeleton3D       │
                                        │  drives AnimationPlayer          │
                                        └──────────────────────────────────┘
```

The tick rate for Ananke is 20 Hz (matching `TICK_HZ` in the engine). Godot renders at 60 Hz; interpolation between simulation ticks is handled in GDScript using the `interpolation_factor` field in the snapshot.

## Prerequisites

- [Godot 4.x](https://godotengine.org/download) (4.2 or later recommended)
- Node.js 18 or later
- npm 9 or later

## Quick start

**1. Start the sidecar**

```bash
cd sidecar
npm install
node server.js
# Sidecar listens on http://localhost:3000
# GET /health  →  { "ok": true }
# GET /state   →  JSON snapshot of entity positions and animation hints
```

**2. Open the Godot project**

Open Godot 4, click "Import", and select the `project.godot` file at the root of this repository.

**3. Run the demo scene**

Open `scenes/demo.tscn` and press F5 (or the Play button). You should see two placeholder meshes moving according to the Ananke simulation.

## Snapshot JSON shape

`GET /state` returns an array of entity snapshots:

```jsonc
[
  {
    "entityId": 1,
    "teamId": 1,
    "tick": 42,
    // World-space position in real metres (converted from Ananke fixed-point).
    // SCALE.m = 1000, so position_m fields are integer/1000.
    "position": { "x": 0.0, "y": 0.0, "z": 0.0 },
    "animation": {
      "idle": 0,      // Q value; SCALE.Q = 18000 → 1.0
      "walk": 0,
      "run": 18000,   // entity is running
      "sprint": 0,
      "crawl": 0,
      "guardingQ": 0,
      "attackingQ": 0,
      "shockQ": 1200,
      "fearQ": 0,
      "prone": false,
      "unconscious": false,
      "dead": false
    },
    // Per-region injury blend weights for driven rigs.
    "pose": [
      { "segmentId": "thorax", "impairmentQ": 4500, "structuralQ": 0, "surfaceQ": 4500 }
    ],
    // Grapple relationship — used for IK constraint locking.
    "grapple": {
      "isHolder": false,
      "isHeld": false,
      "heldByIds": [],
      "position": "standing",
      "gripQ": 0
    }
  }
]
```

All `Q` values use Ananke's fixed-point scale (`SCALE.Q = 18000`). Divide by 18000 to get a normalised float for Godot blend weights.

## AnimationHints → AnimationPlayer

Map the `animation` fields to Godot `AnimationPlayer` or `AnimationTree` blend parameters:

| Ananke field   | Godot blend parameter         | Notes                                  |
|----------------|-------------------------------|----------------------------------------|
| `idle`         | `locomotion/idle`             | Mutually exclusive with walk/run/sprint|
| `walk`         | `locomotion/walk`             | —                                      |
| `run`          | `locomotion/run`              | —                                      |
| `sprint`       | `locomotion/sprint`           | —                                      |
| `crawl`        | `locomotion/crawl`            | Also set `prone = true`                |
| `guardingQ`    | `combat/guard_weight`         | Divide by SCALE.Q                      |
| `attackingQ`   | `combat/attack_weight`        | Nonzero during attack cooldown         |
| `shockQ`       | `condition/shock`             | Drives stagger/flinch blend            |
| `prone`        | AnimationPlayer state `Prone` | Boolean flag                           |
| `unconscious`  | AnimationPlayer state `KO`    | Boolean flag                           |
| `dead`         | AnimationPlayer state `Dead`  | Boolean flag                           |

## GrapplePoseConstraint → IK

When `grapple.isHeld` is true, the held entity's root bone should be constrained relative to the holder's root. The `position` field (`"standing"`, `"prone"`, `"pinned"`) selects the IK target pose. See `scripts/AnankeController.gd` for the TODO stubs.

## Fixed-point coordinate conversion

Ananke stores positions as integers in units of `1/SCALE.m = 1/1000` metres. The sidecar converts to real metres before sending. In GDScript:

```gdscript
# position already in metres from sidecar
node.position = Vector3(snap.position.x, snap.position.z, -snap.position.y)
# Note: Ananke uses Y-up with Z as depth; Godot uses Y-up.
# Adjust axis mapping to match your scene orientation.
```

## Further reading

- [docs/bridge-contract.md](https://github.com/its-not-rocket-science/ananke/blob/main/docs/bridge-contract.md) — full bridge API contract
- [Ananke on GitHub](https://github.com/its-not-rocket-science/ananke)
- [ROADMAP.md](./ROADMAP.md) — implementation milestones
