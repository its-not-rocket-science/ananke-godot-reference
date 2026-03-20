## AnankeDoc: Applies lightweight grapple presentation state by snapping marker
## nodes toward the holder/held pair and exposing metadata for the rig scene.
extends RefCounted
class_name GrappleApplicator

func apply_grapple(rig: Node3D, snapshot: Dictionary, peers: Dictionary) -> void:
	if rig == null:
		return
	var grapple: Variant = snapshot.get("grapple", {})
	if typeof(grapple) != TYPE_DICTIONARY:
		_clear_grapple(rig)
		return

	var is_held := bool(grapple.get("isHeld", false))
	var held_by: Array = grapple.get("heldByIds", [])
	if not is_held or held_by.is_empty():
		_clear_grapple(rig)
		return

	var holder_id := int(held_by[0])
	var holder: Node3D = peers.get(holder_id)
	if holder == null:
		_clear_grapple(rig)
		return

	var midpoint := holder.global_position.lerp(rig.global_position, 0.5)
	rig.global_position = rig.global_position.lerp(midpoint, 0.15)
	if rig.has_method("set_grapple_state"):
		rig.call("set_grapple_state", true, holder_id, String(grapple.get("position", "standing")), clampf(float(grapple.get("gripQ", 0.0)) / 18000.0, 0.0, 1.0))

func _clear_grapple(rig: Node) -> void:
	if rig != null and rig.has_method("set_grapple_state"):
		rig.call("set_grapple_state", false, -1, "", 0.0)
