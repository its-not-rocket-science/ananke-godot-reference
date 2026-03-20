import { createWorld, q, type WorldState, type CommandMap } from "@its-not-rocket-science/ananke";

export const SCENARIO_ID = "knight-vs-brawler";
export const TICK_HZ = 20;
export const TICK_MS = Math.trunc(1000 / TICK_HZ);
export const DEFAULT_PORT = 7373;
export const DEFAULT_HOST = "127.0.0.1";
export const WORLD_SEED = 42;

export interface ScenarioRuntime {
  id: string;
  world: WorldState;
  buildCommands: (world: WorldState) => CommandMap;
}

export function createScenario(): ScenarioRuntime {
  const world = createWorld(WORLD_SEED, [
    {
      id: 1,
      teamId: 1,
      seed: 1001,
      archetype: "KNIGHT_INFANTRY",
      weaponId: "wpn_longsword",
      armourId: "arm_plate",
      x_m: -0.45,
      y_m: 0.0,
    },
    {
      id: 2,
      teamId: 2,
      seed: 2001,
      archetype: "PRO_BOXER",
      weaponId: "wpn_bone_dagger",
      x_m: 0.45,
      y_m: 0.0,
    },
  ]);

  return {
    id: SCENARIO_ID,
    world,
    buildCommands,
  };
}

function buildCommands(world: WorldState): CommandMap {
  const commands: CommandMap = new Map();
  const living = world.entities.filter((entity) => !entity.injury.dead);

  for (const entity of living) {
    const target = living.find((candidate) => candidate.teamId !== entity.teamId);
    if (!target) {
      continue;
    }

    commands.set(entity.id, [
      {
        kind: "attackNearest",
        mode: "strike",
        intensity: q(1.0),
      },
      {
        kind: "defend",
        mode: entity.id === 1 ? "parry" : "dodge",
        intensity: q(0.55),
      },
    ]);
  }

  return commands;
}
