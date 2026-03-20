using System.Collections.Generic;
using Godot;

namespace Ananke.Bridge;

public partial class AnankeDemo : Node3D
{
    [Export] public NodePath ReceiverPath { get; set; } = "AnankeReceiver";
    [Export] public NodePath InterpolatorPath { get; set; } = "AnankeInterpolator";

    private AnankeReceiver? _receiver;
    private AnankeInterpolator? _interpolator;
    private readonly Dictionary<int, AnankeCharacterRig> _rigs = new();

    public override void _Ready()
    {
        _receiver = GetNodeOrNull<AnankeReceiver>(ReceiverPath);
        _interpolator = GetNodeOrNull<AnankeInterpolator>(InterpolatorPath);

        foreach (var node in GetTree().GetNodesInGroup("ananke_character_rig"))
        {
            if (node is AnankeCharacterRig rig)
            {
                _rigs[rig.EntityId] = rig;
            }
        }

        if (_receiver is not null && _interpolator is not null)
        {
            _receiver.FrameReceived += _interpolator.PushFrame;
        }
    }

    public override void _Process(double delta)
    {
        if (_interpolator is null)
        {
            return;
        }

        var nowMs = Time.GetTicksMsec();
        foreach (var (entityId, rig) in _rigs)
        {
            var state = _interpolator.GetInterpolatedState(entityId, nowMs);
            if (state is not null)
            {
                rig.ApplyState(state, _rigs);
            }
        }
    }
}
