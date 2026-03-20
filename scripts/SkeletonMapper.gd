## AnankeDoc: Resolves Ananke segment ids to Skeleton3D bone names and applies
## basic procedural offsets/rotations to the target rig skeleton.
extends RefCounted
class_name SkeletonMapper

const DEFAULT_MAP := {
	"pelvis": "pelvis",
	"torso": "spine",
	"thorax": "chest",
	"abdomen": "spine",
	"neck": "neck",
	"head": "head",
	"leftArm": "left_arm",
	"rightArm": "right_arm",
	"leftForearm": "left_forearm",
	"rightForearm": "right_forearm",
	"leftHand": "left_hand",
	"rightHand": "right_hand",
	"leftLeg": "left_leg",
	"rightLeg": "right_leg",
	"leftShin": "left_shin",
	"rightShin": "right_shin",
	"leftFoot": "left_foot",
	"rightFoot": "right_foot",
}

var _bone_names: Dictionary = DEFAULT_MAP.duplicate(true)

func set_mapping(mapping: Dictionary) -> void:
	_bone_names = DEFAULT_MAP.duplicate(true)
	for key in mapping.keys():
		_bone_names[key] = String(mapping[key])

func resolve_bone_name(segment_id: String) -> String:
	return String(_bone_names.get(segment_id, ""))

func apply_snapshot(rig: Node3D, skeleton: Skeleton3D, snapshot: Dictionary) -> void:
	if rig == null or skeleton == null:
		return

	var position: Dictionary = snapshot.get("position", {})
	rig.position = Vector3(
		float(position.get("x", 0.0)),
		float(position.get("z", 0.0)),
		float(position.get("y", 0.0))
	)

	var pose: Variant = snapshot.get("pose", [])
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

		var pose_position := skeleton.get_bone_pose_position(bone_idx)
		var pose_rotation := skeleton.get_bone_pose_rotation(bone_idx)
		var severity := _derive_severity(modifier)
		var offset := _derive_offset(modifier, severity)
		var rotation := _derive_rotation(modifier, severity)
		skeleton.set_bone_pose_position(bone_idx, pose_position + offset)
		skeleton.set_bone_pose_rotation(bone_idx, pose_rotation * rotation)

func reset_pose(skeleton: Skeleton3D) -> void:
	if skeleton == null:
		return
	for bone_idx in skeleton.get_bone_count():
		skeleton.set_bone_pose_position(bone_idx, Vector3.ZERO)
		skeleton.set_bone_pose_rotation(bone_idx, Quaternion.IDENTITY)

func _derive_severity(modifier: Dictionary) -> float:
	for key in ["impairmentQ", "shockQ", "weightQ", "gripQ"]:
		if modifier.has(key):
			return clampf(float(modifier.get(key, 0.0)) / 18000.0, 0.0, 1.0)
	return 0.0

func _derive_offset(modifier: Dictionary, severity: float) -> Vector3:
	var local := modifier.get("localOffset", {})
	if typeof(local) == TYPE_DICTIONARY:
		return Vector3(
			float(local.get("x", 0.0)),
			float(local.get("z", 0.0)),
			float(local.get("y", 0.0))
		) * 0.01
	return Vector3(0.0, -0.03 * severity, 0.0)

func _derive_rotation(modifier: Dictionary, severity: float) -> Quaternion:
	var angle := deg_to_rad(10.0) * severity
	var side := String(modifier.get("segmentId", ""))
	var axis := Vector3.FORWARD if side.contains("left") else Vector3.BACK
	return Quaternion(axis.normalized(), angle)
