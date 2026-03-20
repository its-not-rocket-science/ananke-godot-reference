using Godot;

namespace Ananke.Bridge;

public partial class AnimationDriver : Node
{
    [Export] public NodePath AnimationTreePath { get; set; } = NodePath.Empty;
    [Export] public float QScale { get; set; } = 10000.0f;

    private AnimationTree? _animationTree;
    private AnimationNodeStateMachinePlayback? _playback;

    public override void _Ready()
    {
        if (AnimationTreePath.IsEmpty)
        {
            return;
        }

        _animationTree = GetNodeOrNull<AnimationTree>(AnimationTreePath);
        if (_animationTree is not null)
        {
            _playback = _animationTree.Get("parameters/playback") as AnimationNodeStateMachinePlayback;
        }
    }

    public void ApplyHints(AnankeAnimationHints hints)
    {
        if (_playback is not null)
        {
            _playback.Travel(ToStateName(hints.PrimaryState));
        }

        if (_animationTree is null)
        {
            return;
        }

        _animationTree.Set("parameters/injury_blend/blend_amount", hints.InjuryWeightQ / QScale);
        _animationTree.Set("parameters/guard_blend/blend_amount", hints.GuardingQ / QScale);
        _animationTree.Set("parameters/attack_blend/blend_amount", hints.AttackingQ / QScale);
    }

    private static string ToStateName(string primaryState)
    {
        return primaryState switch
        {
            "attack" => "Attack",
            "prone" => "Prone",
            "unconscious" => "KO",
            "dead" => "Dead",
            _ => "Idle",
        };
    }
}
