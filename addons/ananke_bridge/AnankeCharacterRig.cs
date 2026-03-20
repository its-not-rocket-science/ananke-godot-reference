using System.Collections.Generic;
using Godot;

namespace Ananke.Bridge;

public partial class AnankeCharacterRig : Node3D
{
    [Export] public int EntityId { get; set; }
    [Export] public NodePath SkeletonPath { get; set; } = "Visual/Skeleton3D";
    [Export] public NodePath MapperPath { get; set; } = "SkeletonMapper";
    [Export] public NodePath AnimationDriverPath { get; set; } = "AnimationDriver";
    [Export] public NodePath GrappleApplicatorPath { get; set; } = "GrappleApplicator";
    [Export] public NodePath HeldAnchorPath { get; set; } = "HeldAnchor";

    private Skeleton3D? _skeleton;
    private SkeletonMapper? _mapper;
    private AnimationDriver? _animationDriver;
    private GrappleApplicator? _grappleApplicator;
    private Node3D? _heldAnchor;

    public override void _Ready()
    {
        AddToGroup("ananke_character_rig");
        _skeleton = GetNodeOrNull<Skeleton3D>(SkeletonPath);
        _mapper = GetNodeOrNull<SkeletonMapper>(MapperPath);
        _animationDriver = GetNodeOrNull<AnimationDriver>(AnimationDriverPath);
        _grappleApplicator = GetNodeOrNull<GrappleApplicator>(GrappleApplicatorPath);
        _heldAnchor = GetNodeOrNull<Node3D>(HeldAnchorPath);
    }

    public Node3D? GetHeldAnchor() => _heldAnchor;

    public void ApplyState(AnankeInterpolatedEntityState state, IReadOnlyDictionary<int, AnankeCharacterRig> rigs)
    {
        GlobalPosition = new Vector3(state.PositionMetres.X, state.PositionMetres.Z, state.PositionMetres.Y);

        if (state.Facing.LengthSquared() > 0.001f)
        {
            LookAt(GlobalPosition + new Vector3(state.Facing.X, state.Facing.Z, state.Facing.Y), Vector3.Up, true);
        }

        if (_skeleton is not null && _mapper is not null)
        {
            _mapper.ApplyPose(_skeleton, state.PoseModifiers);
        }

        _animationDriver?.ApplyHints(state.Animation);
        _grappleApplicator?.ApplyConstraint(state, rigs);
    }
}
