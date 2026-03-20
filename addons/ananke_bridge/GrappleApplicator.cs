using Godot;

namespace Ananke.Bridge;

public partial class GrappleApplicator : Node
{
    [Export] public NodePath HeldAnchorPath { get; set; } = NodePath.Empty;

    private Node3D? _heldAnchor;

    public override void _Ready()
    {
        _heldAnchor = HeldAnchorPath.IsEmpty ? null : GetNodeOrNull<Node3D>(HeldAnchorPath);
    }

    public void ApplyConstraint(AnankeInterpolatedEntityState state, System.Collections.Generic.IReadOnlyDictionary<int, AnankeCharacterRig> rigMap)
    {
        if (!state.Grapple.IsHeld || state.Grapple.HeldByIds.Count == 0)
        {
            return;
        }

        var holderId = state.Grapple.HeldByIds[0];
        if (!rigMap.TryGetValue(holderId, out var holderRig))
        {
            return;
        }

        var anchor = holderRig.GetHeldAnchor() ?? _heldAnchor;
        if (anchor is null)
        {
            return;
        }

        var owner = GetParentOrNull<Node3D>();
        if (owner is not null)
        {
            owner.GlobalPosition = anchor.GlobalPosition;
        }
    }
}
