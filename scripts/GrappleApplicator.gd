## AnankeDoc: Applies grapple constraint state from an entity snapshot.
## Handles two roles independently:
##   isHeld   — converges this entity's position toward the holder's anchor.
##   isHolder — notifies the rig to show grip visual (hand-close / arm tint).
extends RefCounted
class_name GrappleApplicator

## Per-frame convergence fraction toward the grapple anchor (isHeld path).
const LERP_SPEED := 0.2

func apply_grapple(rig: Node3D, snapshot: Dictionary, peers: Dictionary) -> void:
	if rig == null:
		return
	var grapple: Variant = snapshot.get("grapple", {})
	if typeof(grapple) != TYPE_DICTIONARY:
		_clear_grapple(rig)
		return

	var is_held   := bool(grapple.get("isHeld",   false))
	var is_holder := bool(grapple.get("isHolder", false))

	if is_held:
		_apply_held(rig, grapple, peers)
	elif is_holder:
		_apply_holder(rig, grapple)
	else:
		_clear_grapple(rig)

# ── isHeld path ───────────────────────────────────────────────────────────────

func _apply_held(rig: Node3D, grapple: Dictionary, peers: Dictionary) -> void:
	var held_by: Array = grapple.get("heldByIds", [])
	if held_by.is_empty():
		_clear_grapple(rig)
		return

	var holder_id := int(held_by[0])
	var holder: Node3D = peers.get(holder_id)
	if holder == null:
		_clear_grapple(rig)
		return

	var grip      := clampf(float(grapple.get("gripQ",    0.0)) / 10000.0, 0.0, 1.0)
	var pose_name := String(grapple.get("position", "standing"))

	# Move toward the holder's grapple anchor for the given pose.
	var anchor := _find_anchor(holder, pose_name)
	var target := anchor.global_position if anchor != null else holder.global_position
	rig.global_position = rig.global_position.lerp(target, LERP_SPEED)

	if rig.has_method("set_grapple_state"):
		rig.call("set_grapple_state", true, holder_id, pose_name, grip)

# ── isHolder path ─────────────────────────────────────────────────────────────

func _apply_holder(rig: Node3D, grapple: Dictionary) -> void:
	var grip      := clampf(float(grapple.get("gripQ",    0.0)) / 10000.0, 0.0, 1.0)
	var pose_name := String(grapple.get("position", "standing"))
	var held_id   := int(grapple.get("holdingEntityId", -1))

	if rig.has_method("set_grapple_state"):
		rig.call("set_grapple_state", true, held_id, pose_name, grip)

# ── Helpers ───────────────────────────────────────────────────────────────────

func _find_anchor(holder: Node3D, pose_name: String) -> Marker3D:
	# Try pose-specific child first (e.g. GrappleMarker/Prone), then generic marker.
	var pose_path := "GrappleMarker/%s" % pose_name.capitalize()
	var marker := holder.get_node_or_null(pose_path) as Marker3D
	if marker == null:
		marker = holder.get_node_or_null("GrappleMarker") as Marker3D
	return marker

func _clear_grapple(rig: Node) -> void:
	if rig != null and rig.has_method("set_grapple_state"):
		rig.call("set_grapple_state", false, -1, "", 0.0)
