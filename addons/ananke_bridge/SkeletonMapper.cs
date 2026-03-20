using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;
using Godot;

namespace Ananke.Bridge;

public partial class SkeletonMapper : Node
{
    [Export] public string MappingPath { get; set; } = "res://addons/ananke_bridge/mappings/humanoid.json";

    private readonly Dictionary<string, string> _segmentToBone = new(StringComparer.OrdinalIgnoreCase);

    public override void _Ready()
    {
        LoadMapping();
    }

    public string ResolveBoneName(string segmentId)
        => _segmentToBone.TryGetValue(segmentId, out var boneName) ? boneName : string.Empty;

    public void ApplyPose(Skeleton3D skeleton, IReadOnlyList<AnankePoseModifier> poseModifiers)
    {
        foreach (var modifier in poseModifiers)
        {
            var boneName = ResolveBoneName(modifier.SegmentId);
            if (string.IsNullOrEmpty(boneName))
            {
                continue;
            }

            var boneIndex = skeleton.FindBone(boneName);
            if (boneIndex < 0)
            {
                continue;
            }

            skeleton.SetBonePosePosition(boneIndex, modifier.LocalOffsetMetres.ToGodotVector());
        }
    }

    private void LoadMapping()
    {
        _segmentToBone.Clear();

        using var file = FileAccess.Open(MappingPath, FileAccess.ModeFlags.Read);
        if (file is null)
        {
            GD.PushWarning($"SkeletonMapper could not open mapping file at {MappingPath}.");
            return;
        }

        var json = file.GetAsText();
        var mapping = JsonSerializer.Deserialize<BodyPlanMapping>(json, new JsonSerializerOptions
        {
            PropertyNameCaseInsensitive = true,
        });

        if (mapping?.Segments is null)
        {
            GD.PushWarning($"SkeletonMapper failed to parse mapping JSON at {MappingPath}.");
            return;
        }

        foreach (var segment in mapping.Segments)
        {
            if (!string.IsNullOrWhiteSpace(segment.SegmentId) && !string.IsNullOrWhiteSpace(segment.BoneName))
            {
                _segmentToBone[segment.SegmentId] = segment.BoneName;
            }
        }
    }

    private sealed class BodyPlanMapping
    {
        public string BodyPlanId { get; set; } = string.Empty;
        public List<SegmentMapping> Segments { get; set; } = new();
    }

    private sealed class SegmentMapping
    {
        public string SegmentId { get; set; } = string.Empty;
        public string BoneName { get; set; } = string.Empty;
    }
}
