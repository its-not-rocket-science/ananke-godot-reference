## AnankeDoc: Builds a reusable placeholder humanoid rig scene with a simple
## Skeleton3D hierarchy and exposes presentation hooks for animation/grapple UI.
extends Node3D
class_name CharacterRig

@export var body_color := Color(0.35, 0.55, 0.95, 1.0)

@onready var skeleton: Skeleton3D = $Visual/Skeleton3D
@onready var state_label: Label3D = $StateLabel
@onready var grapple_marker: Marker3D = $GrappleMarker

var _body_materials: Dictionary = {}

func _ready() -> void:
	_apply_body_color()
	set_animation_state("Idle", 0.0, {})
	set_grapple_state(false, -1, "", 0.0)

func get_skeleton() -> Skeleton3D:
	return skeleton

func set_animation_state(state_name: String, blend_amount: float, animation: Dictionary) -> void:
	var extra := ""
	if animation.has("primaryState"):
		extra = "\nsource=%s" % String(animation.get("primaryState", ""))
	state_label.text = "%s\nblend=%.2f%s" % [state_name, blend_amount, extra]
	var accent := body_color.lerp(Color(0.85, 0.2, 0.2, 1.0), blend_amount)
	for material in _body_materials.values():
		(material as StandardMaterial3D).albedo_color = accent

func set_grapple_state(active: bool, holder_id: int, pose_name: String, grip: float) -> void:
	grapple_marker.visible = active
	var right_arm_mat := _body_materials.get("RightArm") as StandardMaterial3D
	if active:
		state_label.text += "\ngrapple #%d %s grip=%.2f" % [holder_id, pose_name, grip]
		# Tint right arm gold proportional to grip strength — proxy for hand-close blend shape.
		if right_arm_mat != null:
			right_arm_mat.albedo_color = body_color.lerp(Color(1.0, 0.65, 0.0, 1.0), grip)
	else:
		if right_arm_mat != null:
			right_arm_mat.albedo_color = body_color

func _apply_body_color() -> void:
	for node_name in ["Torso", "Head", "LeftArm", "RightArm", "LeftLeg", "RightLeg"]:
		var mesh_instance := get_node_or_null("Visual/%s" % node_name) as MeshInstance3D
		if mesh_instance == null:
			continue
		var material := StandardMaterial3D.new()
		material.albedo_color = body_color
		mesh_instance.material_override = material
		_body_materials[node_name] = material
