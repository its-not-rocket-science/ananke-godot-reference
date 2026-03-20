import {
  SCALE,
  q,
  clampQ,
  qMul,
  deriveAnimationHints,
  derivePoseModifiers,
  deriveGrappleConstraint,
  type Entity,
  type RigSnapshot,
  type AnimationHints,
  type PoseModifier,
  type GrapplePoseConstraint,
} from "@its-not-rocket-science/ananke";

export interface WireVector3 {
  x: number;
  y: number;
  z: number;
}

export interface WireCondition {
  shockQ: number;
  fearQ: number;
  consciousnessQ: number;
  fluidLossQ: number;
  dead: boolean;
}

export interface WireAnimation extends AnimationHints {
  primaryState: string;
  locomotionBlendQ: number;
  injuryWeightQ: number;
}

export interface WirePoseModifier extends PoseModifier {
  localOffset_m: WireVector3;
}

export interface WireEntityFrame {
  entityId: number;
  teamId: number;
  tick: number;
  position_m: WireVector3;
  velocity_mps: WireVector3;
  facing: WireVector3;
  animation: WireAnimation;
  poseModifiers: WirePoseModifier[];
  grapple: GrapplePoseConstraint;
  condition: WireCondition;
  massKg: number;
  cogOffset_m: { x: number; y: number };
}

export interface WireFrame {
  schema: "ananke.bridge.frame.v1";
  scenarioId: string;
  tick: number;
  timestampMs: number;
  entities: WireEntityFrame[];
}

export function serialiseFrame(args: {
  scenarioId: string;
  tick: number;
  timestampMs: number;
  snapshots: RigSnapshot[];
  entities: Entity[];
}): WireFrame {
  const entityById = new Map(args.entities.map((entity) => [entity.id, entity]));

  return {
    schema: "ananke.bridge.frame.v1",
    scenarioId: args.scenarioId,
    tick: args.tick,
    timestampMs: args.timestampMs,
    entities: args.snapshots.map((snapshot) => {
      const entity = entityById.get(snapshot.entityId);
      if (!entity) {
        throw new Error(`Missing entity ${snapshot.entityId} for snapshot serialisation.`);
      }

      const animation = deriveAnimationHints(entity);
      const pose = derivePoseModifiers(entity);
      const grapple = deriveGrappleConstraint(entity);

      return {
        entityId: snapshot.entityId,
        teamId: snapshot.teamId,
        tick: snapshot.tick,
        position_m: toRealMetres(entity.position_m),
        velocity_mps: toRealMetres(entity.velocity_mps),
        facing: normaliseFacing(entity.action.facingDirQ ?? { x: q(1), y: 0, z: 0 }),
        animation: enrichAnimation(animation, pose),
        poseModifiers: pose.map((modifier) => ({
          ...modifier,
          localOffset_m: poseOffsetForSegment(modifier.segmentId, modifier.impairmentQ),
        })),
        grapple,
        condition: {
          shockQ: entity.injury.shock,
          fearQ: entity.condition.fearQ ?? 0,
          consciousnessQ: entity.injury.consciousness,
          fluidLossQ: entity.injury.fluidLoss,
          dead: entity.injury.dead,
        },
        massKg: snapshot.mass.totalMass_kg / SCALE.kg,
        cogOffset_m: snapshot.mass.cogOffset_m,
      } satisfies WireEntityFrame;
    }),
  };
}

function enrichAnimation(animation: AnimationHints, pose: PoseModifier[]): WireAnimation {
  const locomotionBlendQ = Math.max(
    animation.idle,
    animation.walk,
    animation.run,
    animation.sprint,
    animation.crawl,
  );
  const injuryWeightQ = pose.reduce((worst, modifier) => Math.max(worst, modifier.impairmentQ), 0);

  return {
    ...animation,
    primaryState: primaryStateFor(animation),
    locomotionBlendQ,
    injuryWeightQ,
  };
}

function primaryStateFor(animation: AnimationHints): string {
  if (animation.dead) {
    return "dead";
  }
  if (animation.unconscious) {
    return "unconscious";
  }
  if (animation.prone || animation.crawl > 0) {
    return "prone";
  }
  if (animation.attackingQ > 0) {
    return "attack";
  }
  if (animation.sprint > 0 || animation.run > 0) {
    return "flee";
  }
  return "idle";
}

function poseOffsetForSegment(segmentId: string, impairmentQ: number): WireVector3 {
  const weightQ = clampQ(impairmentQ, 0, SCALE.Q);
  const offsetQ = qMul(weightQ, q(0.06));
  const offset = offsetQ / SCALE.Q;

  switch (segmentId) {
    case "head":
      return { x: 0, y: -offset * 0.35, z: 0 };
    case "torso":
      return { x: 0, y: -offset * 0.5, z: 0 };
    case "leftArm":
      return { x: -offset, y: 0, z: 0 };
    case "rightArm":
      return { x: offset, y: 0, z: 0 };
    case "leftLeg":
      return { x: -offset * 0.45, y: -offset, z: 0 };
    case "rightLeg":
      return { x: offset * 0.45, y: -offset, z: 0 };
    default:
      return { x: 0, y: 0, z: 0 };
  }
}

function toRealMetres(value: { x: number; y: number; z: number }): WireVector3 {
  return {
    x: value.x / SCALE.m,
    y: value.y / SCALE.m,
    z: value.z / SCALE.m,
  };
}

function normaliseFacing(value: { x: number; y: number; z: number }): WireVector3 {
  const magnitude = Math.hypot(value.x, value.y, value.z) || 1;
  return {
    x: value.x / magnitude,
    y: value.y / magnitude,
    z: value.z / magnitude,
  };
}
