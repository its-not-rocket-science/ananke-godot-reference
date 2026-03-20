using System;
using System.Collections.Generic;
using System.Text.Json.Serialization;
using Godot;

namespace Ananke.Bridge;

public sealed class AnankeFrameEnvelope
{
    [JsonPropertyName("schema")]
    public string Schema { get; set; } = string.Empty;

    [JsonPropertyName("scenarioId")]
    public string ScenarioId { get; set; } = string.Empty;

    [JsonPropertyName("tick")]
    public int Tick { get; set; }

    [JsonPropertyName("timestampMs")]
    public double TimestampMs { get; set; }

    [JsonPropertyName("entities")]
    public List<AnankeEntityFrame> Entities { get; set; } = new();
}

public sealed class AnankeEntityFrame
{
    [JsonPropertyName("entityId")]
    public int EntityId { get; set; }

    [JsonPropertyName("teamId")]
    public int TeamId { get; set; }

    [JsonPropertyName("tick")]
    public int Tick { get; set; }

    [JsonPropertyName("position_m")]
    public AnankeVector3 PositionMetres { get; set; } = new();

    [JsonPropertyName("velocity_mps")]
    public AnankeVector3 VelocityMetresPerSecond { get; set; } = new();

    [JsonPropertyName("facing")]
    public AnankeVector3 Facing { get; set; } = new();

    [JsonPropertyName("animation")]
    public AnankeAnimationHints Animation { get; set; } = new();

    [JsonPropertyName("poseModifiers")]
    public List<AnankePoseModifier> PoseModifiers { get; set; } = new();

    [JsonPropertyName("grapple")]
    public AnankeGrappleConstraint Grapple { get; set; } = new();

    [JsonPropertyName("condition")]
    public AnankeCondition Condition { get; set; } = new();
}

public sealed class AnankeVector3
{
    [JsonPropertyName("x")]
    public float X { get; set; }

    [JsonPropertyName("y")]
    public float Y { get; set; }

    [JsonPropertyName("z")]
    public float Z { get; set; }

    public Vector3 ToGodotVector() => new(X, Y, Z);

    public static AnankeVector3 Lerp(AnankeVector3 from, AnankeVector3 to, float weight)
    {
        return new AnankeVector3
        {
            X = Mathf.Lerp(from.X, to.X, weight),
            Y = Mathf.Lerp(from.Y, to.Y, weight),
            Z = Mathf.Lerp(from.Z, to.Z, weight),
        };
    }
}

public sealed class AnankeAnimationHints
{
    [JsonPropertyName("idle")] public int Idle { get; set; }
    [JsonPropertyName("walk")] public int Walk { get; set; }
    [JsonPropertyName("run")] public int Run { get; set; }
    [JsonPropertyName("sprint")] public int Sprint { get; set; }
    [JsonPropertyName("crawl")] public int Crawl { get; set; }
    [JsonPropertyName("guardingQ")] public int GuardingQ { get; set; }
    [JsonPropertyName("attackingQ")] public int AttackingQ { get; set; }
    [JsonPropertyName("shockQ")] public int ShockQ { get; set; }
    [JsonPropertyName("fearQ")] public int FearQ { get; set; }
    [JsonPropertyName("prone")] public bool Prone { get; set; }
    [JsonPropertyName("unconscious")] public bool Unconscious { get; set; }
    [JsonPropertyName("dead")] public bool Dead { get; set; }
    [JsonPropertyName("primaryState")] public string PrimaryState { get; set; } = "idle";
    [JsonPropertyName("locomotionBlendQ")] public int LocomotionBlendQ { get; set; }
    [JsonPropertyName("injuryWeightQ")] public int InjuryWeightQ { get; set; }

    public static AnankeAnimationHints Lerp(AnankeAnimationHints from, AnankeAnimationHints to, float weight)
    {
        var snapToCurrent = weight >= 0.5f;
        return new AnankeAnimationHints
        {
            Idle = Mathf.RoundToInt(Mathf.Lerp(from.Idle, to.Idle, weight)),
            Walk = Mathf.RoundToInt(Mathf.Lerp(from.Walk, to.Walk, weight)),
            Run = Mathf.RoundToInt(Mathf.Lerp(from.Run, to.Run, weight)),
            Sprint = Mathf.RoundToInt(Mathf.Lerp(from.Sprint, to.Sprint, weight)),
            Crawl = Mathf.RoundToInt(Mathf.Lerp(from.Crawl, to.Crawl, weight)),
            GuardingQ = Mathf.RoundToInt(Mathf.Lerp(from.GuardingQ, to.GuardingQ, weight)),
            AttackingQ = Mathf.RoundToInt(Mathf.Lerp(from.AttackingQ, to.AttackingQ, weight)),
            ShockQ = Mathf.RoundToInt(Mathf.Lerp(from.ShockQ, to.ShockQ, weight)),
            FearQ = Mathf.RoundToInt(Mathf.Lerp(from.FearQ, to.FearQ, weight)),
            Prone = snapToCurrent ? to.Prone : from.Prone,
            Unconscious = snapToCurrent ? to.Unconscious : from.Unconscious,
            Dead = snapToCurrent ? to.Dead : from.Dead,
            PrimaryState = snapToCurrent ? to.PrimaryState : from.PrimaryState,
            LocomotionBlendQ = Mathf.RoundToInt(Mathf.Lerp(from.LocomotionBlendQ, to.LocomotionBlendQ, weight)),
            InjuryWeightQ = Mathf.RoundToInt(Mathf.Lerp(from.InjuryWeightQ, to.InjuryWeightQ, weight)),
        };
    }
}

public sealed class AnankePoseModifier
{
    [JsonPropertyName("segmentId")]
    public string SegmentId { get; set; } = string.Empty;

    [JsonPropertyName("impairmentQ")]
    public int ImpairmentQ { get; set; }

    [JsonPropertyName("structuralQ")]
    public int StructuralQ { get; set; }

    [JsonPropertyName("surfaceQ")]
    public int SurfaceQ { get; set; }

    [JsonPropertyName("localOffset_m")]
    public AnankeVector3 LocalOffsetMetres { get; set; } = new();

    public static AnankePoseModifier Lerp(AnankePoseModifier from, AnankePoseModifier to, float weight)
    {
        return new AnankePoseModifier
        {
            SegmentId = to.SegmentId,
            ImpairmentQ = Mathf.RoundToInt(Mathf.Lerp(from.ImpartmentOrImpairment(), to.ImpartmentOrImpairment(), weight)),
            StructuralQ = Mathf.RoundToInt(Mathf.Lerp(from.StructuralQ, to.StructuralQ, weight)),
            SurfaceQ = Mathf.RoundToInt(Mathf.Lerp(from.SurfaceQ, to.SurfaceQ, weight)),
            LocalOffsetMetres = AnankeVector3.Lerp(from.LocalOffsetMetres, to.LocalOffsetMetres, weight),
        };
    }

    private int ImpartmentOrImpairment() => ImpairmentQ;
}

public sealed class AnankeGrappleConstraint
{
    [JsonPropertyName("isHolder")] public bool IsHolder { get; set; }
    [JsonPropertyName("holdingEntityId")] public int? HoldingEntityId { get; set; }
    [JsonPropertyName("isHeld")] public bool IsHeld { get; set; }
    [JsonPropertyName("heldByIds")] public List<int> HeldByIds { get; set; } = new();
    [JsonPropertyName("position")] public string Position { get; set; } = "standing";
    [JsonPropertyName("gripQ")] public int GripQ { get; set; }

    public static AnankeGrappleConstraint Snap(AnankeGrappleConstraint from, AnankeGrappleConstraint to, float weight)
        => weight >= 0.5f ? to : from;
}

public sealed class AnankeCondition
{
    [JsonPropertyName("shockQ")] public int ShockQ { get; set; }
    [JsonPropertyName("fearQ")] public int FearQ { get; set; }
    [JsonPropertyName("consciousnessQ")] public int ConsciousnessQ { get; set; }
    [JsonPropertyName("fluidLossQ")] public int FluidLossQ { get; set; }
    [JsonPropertyName("dead")] public bool Dead { get; set; }

    public static AnankeCondition Lerp(AnankeCondition from, AnankeCondition to, float weight)
    {
        return new AnankeCondition
        {
            ShockQ = Mathf.RoundToInt(Mathf.Lerp(from.ShockQ, to.ShockQ, weight)),
            FearQ = Mathf.RoundToInt(Mathf.Lerp(from.FearQ, to.FearQ, weight)),
            ConsciousnessQ = Mathf.RoundToInt(Mathf.Lerp(from.ConsciousnessQ, to.ConsciousnessQ, weight)),
            FluidLossQ = Mathf.RoundToInt(Mathf.Lerp(from.FluidLossQ, to.FluidLossQ, weight)),
            Dead = weight >= 0.5f ? to.Dead : from.Dead,
        };
    }
}

public sealed class AnankeInterpolatedEntityState
{
    public int EntityId { get; init; }
    public int TeamId { get; init; }
    public int Tick { get; init; }
    public float InterpolationFactor { get; init; }
    public Vector3 PositionMetres { get; init; }
    public Vector3 VelocityMetresPerSecond { get; init; }
    public Vector3 Facing { get; init; }
    public AnankeAnimationHints Animation { get; init; } = new();
    public IReadOnlyList<AnankePoseModifier> PoseModifiers { get; init; } = Array.Empty<AnankePoseModifier>();
    public AnankeGrappleConstraint Grapple { get; init; } = new();
    public AnankeCondition Condition { get; init; } = new();
}
