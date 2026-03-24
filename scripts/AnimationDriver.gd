## AnankeDoc: Converts snapshot animation hints into lightweight AnimationTree /
## label state updates for the reusable character rig scene.
extends RefCounted
class_name AnimationDriver

const STATE_MAP := {
	"idle": "Idle",
	"walk": "Walk",
	"run": "Run",
	"sprint": "Sprint",
	"crawl": "Crawl",
	"guard": "Guard",
	"attack": "Attack",
	"prone": "Prone",
	"unconscious": "KO",
	"dead": "Dead",
	"flee": "Run",
}

func apply_hints(rig: Node, snapshot: Dictionary) -> void:
	if rig == null:
		return
	var animation: Dictionary = snapshot.get("animation", {})
	var state := _resolve_state(animation)
	var blend := clampf(float(animation.get("injuryWeightQ", 0.0)) / 10000.0, 0.0, 1.0)
	if animation.has("shockQ"):
		blend = max(blend, clampf(float(animation.get("shockQ", 0.0)) / 10000.0, 0.0, 1.0))

	if rig.has_method("set_animation_state"):
		rig.call("set_animation_state", state, blend, animation)

func _resolve_state(animation: Dictionary) -> String:
	if bool(animation.get("dead", false)):
		return "Dead"
	if bool(animation.get("unconscious", false)):
		return "KO"
	var primary := String(animation.get("primaryState", "idle")).to_lower()
	return String(STATE_MAP.get(primary, "Idle"))
