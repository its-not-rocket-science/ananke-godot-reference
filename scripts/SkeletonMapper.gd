## AnankeDoc: Resolves Ananke segment ids to Skeleton3D bone names and applies
## basic procedural offsets/rotations to the target rig skeleton.
extends RefCounted
class_name SkeletonMapper

const DEFAULT_MAP := {
	"pelvis": "torso",
	"torso": "torso",
	"thorax": "torso",
	"abdomen": "torso",
	"neck": "torso",
	"head": "head",
	"leftArm": "left_arm",
	"rightArm": "right_arm",
	"leftForearm": "left_arm",
	"rightForearm": "right_arm",
	"leftHand": "left_arm",
	"rightHand": "right_arm",
	"leftLeg": "left_leg",
	"rightLeg": "right_leg",
	"leftShin": "left_leg",
	"rightShin": "right_leg",
	"leftFoot": "left_leg",
	"rightFoot": "right_leg",
}

var _bone_names: Dictionary = DEFAULT_MAP.duplicate(true)

func set_mapping(mapping: Dictionary) -> void:
	_bone_names = DEFAULT_MAP.duplicate(true)
	for key in mapping.keys():
		_bone_names[key] = String(mapping[key])

func load_mapping_from_json(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false

	var parsed := JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return false

	var segments: Variant = parsed.get("segments", [])
	if typeof(segments) != TYPE_ARRAY:
		return false

	var mapping := {}
	for segment in segments:
		if typeof(segment) != TYPE_DICTIONARY:
			continue
		var segment_id := String(segment.get("segmentId", ""))
		var bone_name := String(segment.get("boneName", ""))
		if segment_id != "" and bone_name != "":
			mapping[segment_id] = bone_name

	if mapping.is_empty():
		return false

	set_mapping(mapping)
	return true

func resolve_bone_name(segment_id: String) -> String:
	return String(_bone_names.get(segment_id, ""))

func apply_snapshot(rig: Node3D, skeleton: Skeleton3D, snapshot: Dictionary) -> void:
	if rig == null or skeleton == null:
		return

	var position: Dictionary = snapshot.get("position_m", {})
	rig.position = Vector3(
		float(position.get("x", 0.0)),
		float(position.get("z", 0.0)),
		float(position.get("y", 0.0))
	)

	var facing: Dictionary = snapshot.get("facing", {})
	var facing_vec := Vector3(
		float(facing.get("x", 0.0)),
		float(facing.get("z", 0.0)),
		float(facing.get("y", 0.0))
	)
	if facing_vec.length_squared() > 0.0001:
		rig.look_at(rig.global_position + facing_vec.normalized(), Vector3.UP, true)

	var pose: Variant = snapshot.get("poseModifiers", [])
	if typeof(pose) != TYPE_ARRAY:
		return

	for modifier in pose:
		if typeof(modifier) != TYPE_DICTIONARY:
			continue
		var bone_name := resolve_bone_name(String(modifier.get("segmentId", "")))
		if bone_name == "":
			continue
		var bone_idx := skeleton.find_bone(bone_name)
		if bone_idx == -1:
			continue

		var severity := _derive_severity(modifier)
		var offset := _derive_offset(modifier, severity)
		var rotation := _derive_rotation(modifier, severity)
		skeleton.set_bone_pose_position(bone_idx, offset)
		skeleton.set_bone_pose_rotation(bone_idx, rotation)

func reset_pose(skeleton: Skeleton3D) -> void:
	if skeleton == null:
		return
	for bone_idx in range(skeleton.get_bone_count()):
		skeleton.set_bone_pose_position(bone_idx, Vector3.ZERO)
		skeleton.set_bone_pose_rotation(bone_idx, Quaternion.IDENTITY)

func _derive_severity(modifier: Dictionary) -> float:
	for key in ["impairmentQ", "shockQ", "weightQ", "gripQ"]:
		if modifier.has(key):
			return clampf(float(modifier.get(key, 0.0)) / 10000.0, 0.0, 1.0)
	return 0.0

func _derive_offset(modifier: Dictionary, severity: float) -> Vector3:
	var local := modifier.get("localOffset_m", {})
	if typeof(local) == TYPE_DICTIONARY:
		return Vector3(
			float(local.get("x", 0.0)),
			float(local.get("z", 0.0)),
			float(local.get("y", 0.0))
		)
	return Vector3(0.0, -0.03 * severity, 0.0)

func _derive_rotation(modifier: Dictionary, severity: float) -> Quaternion:
	var angle := deg_to_rad(10.0) * severity
	var side := String(modifier.get("segmentId", ""))
	var axis := Vector3.FORWARD if side.contains("left") else Vector3.BACK
	return Quaternion(axis.normalized(), angle)
