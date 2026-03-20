## AnankeDoc: Builds a reusable placeholder humanoid rig scene with a simple
## Skeleton3D hierarchy and exposes presentation hooks for animation/grapple UI.
extends Node3D
class_name CharacterRig

@export var body_color := Color(0.35, 0.55, 0.95, 1.0)

@onready var skeleton: Skeleton3D = $Skeleton3D
@onready var torso_mesh: MeshInstance3D = $Visuals/Torso
@onready var state_label: Label3D = $StateLabel
@onready var grapple_marker: Marker3D = $GrappleMarker

var _bones_ready := false
var _body_material: StandardMaterial3D

func _ready() -> void:
	_build_skeleton_once()
	_apply_body_color()
	set_animation_state("Idle", 0.0, {})
	set_grapple_state(false, -1, "", 0.0)

func set_animation_state(state_name: String, blend_amount: float, animation: Dictionary) -> void:
	var extra := ""
	if animation.has("primaryState"):
		extra = "\nsource=%s" % String(animation.get("primaryState", ""))
	state_label.text = "%s\nblend=%.2f%s" % [state_name, blend_amount, extra]
	if _body_material != null:
		_body_material.albedo_color = body_color.lerp(Color(0.85, 0.2, 0.2, 1.0), blend_amount)

func set_grapple_state(active: bool, holder_id: int, pose_name: String, grip: float) -> void:
	grapple_marker.visible = active
	if active:
		state_label.text += "\ngrapple #%d %s %.2f" % [holder_id, pose_name, grip]

func _build_skeleton_once() -> void:
	if _bones_ready:
		return
	_bones_ready = true
	var specs := [
		{"name": "pelvis", "parent": -1, "rest": Transform3D(Basis.IDENTITY, Vector3(0.0, 0.9, 0.0))},
		{"name": "spine", "parent": 0, "rest": Transform3D(Basis.IDENTITY, Vector3(0.0, 0.18, 0.0))},
		{"name": "chest", "parent": 1, "rest": Transform3D(Basis.IDENTITY, Vector3(0.0, 0.22, 0.0))},
		{"name": "neck", "parent": 2, "rest": Transform3D(Basis.IDENTITY, Vector3(0.0, 0.18, 0.0))},
		{"name": "head", "parent": 3, "rest": Transform3D(Basis.IDENTITY, Vector3(0.0, 0.16, 0.0))},
		{"name": "left_arm", "parent": 2, "rest": Transform3D(Basis.IDENTITY, Vector3(-0.18, 0.12, 0.0))},
		{"name": "left_forearm", "parent": 5, "rest": Transform3D(Basis.IDENTITY, Vector3(-0.24, -0.02, 0.0))},
		{"name": "left_hand", "parent": 6, "rest": Transform3D(Basis.IDENTITY, Vector3(-0.18, 0.0, 0.0))},
		{"name": "right_arm", "parent": 2, "rest": Transform3D(Basis.IDENTITY, Vector3(0.18, 0.12, 0.0))},
		{"name": "right_forearm", "parent": 8, "rest": Transform3D(Basis.IDENTITY, Vector3(0.24, -0.02, 0.0))},
		{"name": "right_hand", "parent": 9, "rest": Transform3D(Basis.IDENTITY, Vector3(0.18, 0.0, 0.0))},
		{"name": "left_leg", "parent": 0, "rest": Transform3D(Basis.IDENTITY, Vector3(-0.1, -0.32, 0.0))},
		{"name": "left_shin", "parent": 11, "rest": Transform3D(Basis.IDENTITY, Vector3(0.0, -0.36, 0.0))},
		{"name": "left_foot", "parent": 12, "rest": Transform3D(Basis.IDENTITY, Vector3(0.0, -0.3, 0.08))},
		{"name": "right_leg", "parent": 0, "rest": Transform3D(Basis.IDENTITY, Vector3(0.1, -0.32, 0.0))},
		{"name": "right_shin", "parent": 14, "rest": Transform3D(Basis.IDENTITY, Vector3(0.0, -0.36, 0.0))},
		{"name": "right_foot", "parent": 15, "rest": Transform3D(Basis.IDENTITY, Vector3(0.0, -0.3, 0.08))},
	]

	for spec in specs:
		skeleton.add_bone(spec.name)
	for index in specs.size():
		skeleton.set_bone_rest(index, specs[index].rest)
		if specs[index].parent >= 0:
			skeleton.set_bone_parent(index, specs[index].parent)
		skeleton.set_bone_pose_position(index, Vector3.ZERO)
		skeleton.set_bone_pose_rotation(index, Quaternion.IDENTITY)

func _apply_body_color() -> void:
	_body_material = StandardMaterial3D.new()
	_body_material.albedo_color = body_color
	torso_mesh.material_override = _body_material
