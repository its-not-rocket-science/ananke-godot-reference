using System;
using System.Collections.Generic;
using System.Linq;
using Godot;

namespace Ananke.Bridge;

public partial class AnankeInterpolator : Node
{
    private readonly Dictionary<int, EntityBuffer> _buffers = new();

    public void PushFrame(AnankeFrameEnvelope frame)
    {
        foreach (var entity in frame.Entities)
        {
            if (!_buffers.TryGetValue(entity.EntityId, out var buffer))
            {
                buffer = new EntityBuffer();
                _buffers[entity.EntityId] = buffer;
            }

            buffer.Previous = buffer.Current;
            buffer.Current = entity;
            buffer.PreviousTimeMs = buffer.CurrentTimeMs;
            buffer.CurrentTimeMs = frame.TimestampMs;
        }
    }

    public AnankeInterpolatedEntityState? GetInterpolatedState(int entityId, double renderTimeMs)
    {
        if (!_buffers.TryGetValue(entityId, out var buffer) || buffer.Current is null)
        {
            return null;
        }

        var current = buffer.Current;
        var previous = buffer.Previous ?? buffer.Current;
        var t = ComputeInterpolationFactor(buffer, renderTimeMs);

        return new AnankeInterpolatedEntityState
        {
            EntityId = current.EntityId,
            TeamId = current.TeamId,
            Tick = current.Tick,
            InterpolationFactor = t,
            PositionMetres = AnankeVector3.Lerp(previous.PositionMetres, current.PositionMetres, t).ToGodotVector(),
            VelocityMetresPerSecond = AnankeVector3.Lerp(previous.VelocityMetresPerSecond, current.VelocityMetresPerSecond, t).ToGodotVector(),
            Facing = AnankeVector3.Lerp(previous.Facing, current.Facing, t).ToGodotVector().Normalized(),
            Animation = AnankeAnimationHints.Lerp(previous.Animation, current.Animation, t),
            PoseModifiers = InterpolatePose(previous.PoseModifiers, current.PoseModifiers, t),
            Grapple = AnankeGrappleConstraint.Snap(previous.Grapple, current.Grapple, t),
            Condition = AnankeCondition.Lerp(previous.Condition, current.Condition, t),
        };
    }

    private static float ComputeInterpolationFactor(EntityBuffer buffer, double renderTimeMs)
    {
        if (buffer.Previous is null || Math.Abs(buffer.CurrentTimeMs - buffer.PreviousTimeMs) < double.Epsilon)
        {
            return 1.0f;
        }

        var t = (float)((renderTimeMs - buffer.PreviousTimeMs) / (buffer.CurrentTimeMs - buffer.PreviousTimeMs));
        return Mathf.Clamp(t, 0.0f, 1.0f);
    }

    private static IReadOnlyList<AnankePoseModifier> InterpolatePose(
        IReadOnlyList<AnankePoseModifier> previous,
        IReadOnlyList<AnankePoseModifier> current,
        float weight)
    {
        var previousBySegment = previous.ToDictionary(modifier => modifier.SegmentId);
        var currentBySegment = current.ToDictionary(modifier => modifier.SegmentId);
        var allSegments = previousBySegment.Keys.Union(currentBySegment.Keys);
        var blended = new List<AnankePoseModifier>();

        foreach (var segmentId in allSegments)
        {
            var from = previousBySegment.TryGetValue(segmentId, out var previousModifier) ? previousModifier : null;
            var to = currentBySegment.TryGetValue(segmentId, out var currentModifier) ? currentModifier : null;

            if (from is not null && to is not null)
            {
                blended.Add(AnankePoseModifier.Lerp(from, to, weight));
            }
            else if (to is not null)
            {
                blended.Add(to);
            }
            else if (from is not null)
            {
                blended.Add(from);
            }
        }

        return blended;
    }

    private sealed class EntityBuffer
    {
        public AnankeEntityFrame? Previous { get; set; }
        public AnankeEntityFrame? Current { get; set; }
        public double PreviousTimeMs { get; set; }
        public double CurrentTimeMs { get; set; }
    }
}
