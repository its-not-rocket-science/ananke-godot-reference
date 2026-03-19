## AnankeController.gd
##
## Polls the Ananke sidecar at 20 Hz, parses the snapshot JSON, and moves
## scene entities to match simulation positions.
##
## Attach this script to the root Node3D of the demo scene.
##
## TODO (M2): Map pose[].segmentId to Skeleton3D bone names using a mapping
##            resource loaded from mappings/humanoid.json.
## TODO (M3): Drive AnimationTree blend parameters from animation hints.
## TODO (M4): Apply SkeletonIK3D constraints from grapple.isHeld data.
## TODO (CE-6): Replace HTTP polling with a WebSocket connection so frames
##              are pushed from the sidecar rather than polled.

extends Node3D

# ── Configuration ──────────────────────────────────────────────────────────────

## Base URL of the Ananke sidecar. Must match PORT in sidecar/server.js.
const SIDECAR_URL := "http://127.0.0.1:3000"

## Poll interval in seconds. 0.05 s = 20 Hz, matching the simulation tick rate.
const POLL_INTERVAL_S := 0.05

## Ananke fixed-point Q scale. Divide any Q value by this to get a float in [0, 1].
## Source: SCALE.Q = 18000 in @its-not-rocket-science/ananke src/units.ts
const SCALE_Q := 18000.0

# ── Node references ────────────────────────────────────────────────────────────

## Entity node map: entity id → Node3D scene node.
## Populated in _ready() from the scene tree.
var _entity_nodes: Dictionary = {}

# ── HTTP request ───────────────────────────────────────────────────────────────

var _http_request: HTTPRequest
var _poll_timer: float = 0.0
var _pending_request: bool = false

# ── Lifecycle ──────────────────────────────────────────────────────────────────

func _ready() -> void:
	# Map entity ids to scene nodes.
	# The node names in demo.tscn correspond to entity ids.
	var entity1 := get_node_or_null("Entity1")
	var entity2 := get_node_or_null("Entity2")
	if entity1:
		_entity_nodes[1] = entity1
	if entity2:
		_entity_nodes[2] = entity2

	# Create the HTTPRequest node used for polling.
	_http_request = HTTPRequest.new()
	add_child(_http_request)
	_http_request.request_completed.connect(_on_state_response)

	print("AnankeController ready. Polling ", SIDECAR_URL, "/state every ", POLL_INTERVAL_S, " s")
	_poll_state()


func _process(delta: float) -> void:
	_poll_timer += delta
	if _poll_timer >= POLL_INTERVAL_S and not _pending_request:
		_poll_timer = 0.0
		_poll_state()

# ── HTTP polling ───────────────────────────────────────────────────────────────

func _poll_state() -> void:
	var err := _http_request.request(SIDECAR_URL + "/state")
	if err != OK:
		push_warning("AnankeController: HTTP request failed (error %d). Is the sidecar running?" % err)
		return
	_pending_request = true


func _on_state_response(
		result: int,
		response_code: int,
		_headers: PackedStringArray,
		body: PackedByteArray
) -> void:
	_pending_request = false

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		push_warning("AnankeController: sidecar returned %d (result=%d)" % [response_code, result])
		return

	var json := JSON.new()
	var parse_err := json.parse(body.get_string_from_utf8())
	if parse_err != OK:
		push_warning("AnankeController: JSON parse error: %s" % json.get_error_message())
		return

	var snapshots = json.data
	if typeof(snapshots) != TYPE_ARRAY:
		push_warning("AnankeController: expected JSON array, got %s" % typeof(snapshots))
		return

	_apply_snapshots(snapshots)

# ── Snapshot application ───────────────────────────────────────────────────────

## Apply a parsed snapshot array to the scene.
func _apply_snapshots(snapshots: Array) -> void:
	for snap in snapshots:
		if typeof(snap) != TYPE_DICTIONARY:
			continue

		var entity_id: int = snap.get("entityId", -1)
		if not _entity_nodes.has(entity_id):
			continue

		var node: Node3D = _entity_nodes[entity_id]

		# ── Position ──────────────────────────────────────────────────────────
		# Ananke uses a right-hand, Y-up coordinate system with Z as depth.
		# Godot also uses Y-up. We map Ananke X→Godot X, Ananke Y→Godot Z,
		# Ananke Z→Godot Y (vertical). Adjust if your scene has a different
		# orientation convention.
		var pos: Dictionary = snap.get("position", {})
		var gx: float = pos.get("x", 0.0)
		var gy: float = pos.get("y", 0.0)  # Ananke lateral Y → Godot Z
		var gz: float = pos.get("z", 0.0)  # Ananke vertical Z → Godot Y
		node.position = Vector3(gx, gz + 0.9, gy)

		# ── Dead / KO state ───────────────────────────────────────────────────
		var dead: bool       = snap.get("dead", false)
		var unconscious: bool = snap.get("unconscious", false)

		# TODO (M3): Set AnimationTree travel targets based on state flags.
		# Example (when AnimationTree is set up):
		#   var anim_tree: AnimationTree = node.get_node("AnimationTree")
		#   if dead:
		#       anim_tree.travel("Dead")
		#   elif unconscious:
		#       anim_tree.travel("KO")

		# ── Animation blend weights ───────────────────────────────────────────
		var anim: Dictionary = snap.get("animation", {})

		# TODO (M3): Drive AnimationTree parameters from AnimationHints.
		# All Q values use SCALE.Q = 18000. Divide by SCALE_Q for float weights.
		# Example:
		#   var anim_tree: AnimationTree = node.get_node("AnimationTree")
		#   anim_tree["parameters/locomotion/blend_amount"] = \
		#       float(anim.get("run", 0)) / SCALE_Q

		# ── Pose modifiers ────────────────────────────────────────────────────
		# var pose: Array = snap.get("pose", [])
		# TODO (M2): For each entry in pose, find the matching bone in
		#            Skeleton3D and set a deformation blend shape weight:
		#   for modifier in pose:
		#       var bone_name: String = _segment_to_bone(modifier["segmentId"])
		#       var weight: float = float(modifier["impairmentQ"]) / SCALE_Q
		#       # Apply weight to blend shape or constraint...

		# ── Grapple constraints ───────────────────────────────────────────────
		# var grapple: Dictionary = snap.get("grapple", {})
		# TODO (M4): When grapple.isHeld is true, activate SkeletonIK3D to
		#            lock this entity's root to the holder.
		#   var is_held: bool = grapple.get("isHeld", false)
		#   var held_by: Array = grapple.get("heldByIds", [])
		#   var grip_q: float = float(grapple.get("gripQ", 0)) / SCALE_Q
		# Use grapple["position"] ("standing", "prone", "pinned") to select
		# the IK target anchor.

# ── Segment → bone name mapping ───────────────────────────────────────────────

## Map an Ananke segment ID to a Godot Skeleton3D bone name.
## TODO (M2): Load this from mappings/humanoid.json instead of hardcoding.
func _segment_to_bone(segment_id: String) -> String:
	var mapping := {
		"thorax":    "Spine",
		"abdomen":   "Spine1",
		"pelvis":    "Hips",
		"head":      "Head",
		"neck":      "Neck",
		"leftArm":   "LeftArm",
		"rightArm":  "RightArm",
		"leftLeg":   "LeftLeg",
		"rightLeg":  "RightLeg",
	}
	return mapping.get(segment_id, "Root")
