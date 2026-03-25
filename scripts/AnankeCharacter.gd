## AnankeCharacter.gd
##
## Procedural humanoid character node driven by Ananke RigSnapshot data.
## No external assets — the character is built from coloured primitive meshes.
##
## Usage:
##   var char := Node3D.new()
##   char.set_script(preload("res://scripts/AnankeCharacter.gd"))
##   add_child(char)
##   char.setup(entity_id, team_id, "Knight")
##   # Each simulation tick:
##   char.apply_snapshot(snapshot_dict)

extends Node3D

# ── Constants ──────────────────────────────────────────────────────────────────

## Ananke fixed-point Q scale. Divide any Q value by this to get a float in [0, 1].
## SCALE.Q = 10_000 in src/units.ts — verify with: node -e "import('@its-not-rocket-science/ananke').then(m=>console.log(m.SCALE.Q))"
const SCALE_Q := 10000.0

## Team colours
const COLOUR_TEAM1  := Color(0.20, 0.45, 0.90)   # steel blue
const COLOUR_TEAM2  := Color(0.85, 0.22, 0.15)   # crimson
const COLOUR_DEAD   := Color(0.35, 0.35, 0.35)   # dark grey

## Flash colours
const COLOUR_ATTACK_FLASH := Color(1.00, 0.90, 0.20)  # gold
const COLOUR_SHOCK_FLASH  := Color(0.95, 0.15, 0.10)  # red

## Arm animation targets (radians)
const ARM_SWING_ANGLE   := -0.8
const SHIELD_UP_ANGLE   := -0.5

## Prone tilt speed (radians per second)
const TILT_SPEED := 8.0

# ── Animation state enum ───────────────────────────────────────────────────────

enum AnimState {
	IDLE,
	GUARDING,
	ATTACKING,
	SHOCKED,
	PRONE,
	UNCONSCIOUS,
	DEAD,
}

# ── Identity ───────────────────────────────────────────────────────────────────

var _entity_id: int  = 0
var _team_id:   int  = 1
var _disp_name: String = ""

# ── Scene nodes (set in _build_character) ──────────────────────────────────────

var _pivot:          Node3D        = null
var _body_mesh:      MeshInstance3D = null
var _head_mesh:      MeshInstance3D = null
var _left_arm_node:  Node3D        = null
var _right_arm_node: Node3D        = null
var _left_leg_node:  Node3D        = null
var _right_leg_node: Node3D        = null
var _state_label:    Label3D       = null
var _name_label:     Label3D       = null

## Maps Ananke segment IDs → MeshInstance3D nodes for per-segment damage tinting.
var _segment_nodes: Dictionary = {}

# ── Materials (one per part so we can tint them independently) ─────────────────

var _body_mat:      StandardMaterial3D = null
var _head_mat:      StandardMaterial3D = null
var _left_arm_mat:  StandardMaterial3D = null
var _right_arm_mat: StandardMaterial3D = null
var _left_leg_mat:  StandardMaterial3D = null
var _right_leg_mat: StandardMaterial3D = null

# ── Animation state ────────────────────────────────────────────────────────────

var _anim_state:    AnimState = AnimState.IDLE
var _base_colour:   Color     = COLOUR_TEAM1

## Flash timer. Counts down from positive value to 0; flash is active while > 0.
var _flash_timer:   float = 0.0
var _flash_colour:  Color = COLOUR_ATTACK_FLASH

## Prone / tilt angle (used for PRONE, UNCONSCIOUS, DEAD states).
var _prone_angle_current: float = 0.0
var _prone_angle_target:  float = 0.0

# ── Interpolation ──────────────────────────────────────────────────────────────

var _prev_pos:   Vector3 = Vector3.ZERO
var _target_pos: Vector3 = Vector3.ZERO
var _lerp_t:     float   = 1.0   # start at 1 so no lerp before first snapshot

# ── Grapple ────────────────────────────────────────────────────────────────────

var _is_held: bool = false

# ── Public API ────────────────────────────────────────────────────────────────

## Call once after add_child() to initialise the character.
func setup(entity_id: int, team_id: int, display_name: String) -> void:
	_entity_id = entity_id
	_team_id   = team_id
	_disp_name = display_name
	_base_colour = COLOUR_TEAM1 if team_id == 1 else COLOUR_TEAM2
	_build_character()


## Apply a parsed snapshot dictionary from the sidecar's /state endpoint.
func apply_snapshot(snap: Dictionary) -> void:
	# ── Position interpolation ────────────────────────────────────────────────
	var dead: bool = snap.get("dead", false)
	if not dead:
		var pos: Dictionary = snap.get("position", {})
		# Coordinate mapping: Ananke X→Godot X, Ananke Y→Godot Z, Ananke Z→Godot Y
		var new_pos := Vector3(
			pos.get("x", 0.0),
			pos.get("z", 0.0) + 0.9,   # offset so character stands on the ground plane
			pos.get("y", 0.0)
		)
		_prev_pos   = position
		_target_pos = new_pos
		_lerp_t     = 0.0

	# ── Animation state ───────────────────────────────────────────────────────
	var anim: Dictionary = snap.get("animation", {})
	var new_state := _determine_anim_state(snap, anim)
	if new_state != _anim_state:
		_set_anim_state(new_state)

	# ── Per-segment damage colouring ──────────────────────────────────────────
	var pose: Array = snap.get("pose", [])
	for seg in pose:
		if typeof(seg) != TYPE_DICTIONARY:
			continue
		var seg_id:      String = seg.get("segmentId", "")
		var surface_q:   float  = float(seg.get("surfaceQ",   0)) / SCALE_Q
		var structural_q: float = float(seg.get("structuralQ", 0)) / SCALE_Q
		_update_segment_colour(seg_id, surface_q, structural_q)

	# ── Grapple ───────────────────────────────────────────────────────────────
	var grapple: Dictionary = snap.get("grapple", {})
	_is_held = grapple.get("isHeld", false)


# ── AnankeController interface (duck-typed) ────────────────────────────────────
# These three methods make AnankeCharacter compatible with AnankeController.gd +
# AnimationDriver.gd + GrappleApplicator.gd without requiring CharacterRig.gd.

## Returns null — procedural rig has no Skeleton3D; SkeletonMapper skips bone poses.
func get_skeleton() -> Skeleton3D:
	return null


## Called by AnimationDriver.gd each tick.
func set_animation_state(state_name: String, blend_amount: float, _animation: Dictionary) -> void:
	var next_state: AnimState
	match state_name:
		"Dead":   next_state = AnimState.DEAD
		"KO":     next_state = AnimState.UNCONSCIOUS
		"Prone":  next_state = AnimState.PRONE
		"Attack": next_state = AnimState.ATTACKING
		"Guard":  next_state = AnimState.GUARDING
		_:        next_state = AnimState.SHOCKED if blend_amount > 0.3 else AnimState.IDLE
	if next_state != _anim_state:
		_set_anim_state(next_state)


## Called by GrappleApplicator.gd each tick.
## Also drives _is_held so _process inhibits position lerp while constrained.
func set_grapple_state(active: bool, _peer_id: int, pose_name: String, grip: float) -> void:
	_is_held = active
	if active:
		if _right_arm_mat:
			_right_arm_mat.albedo_color = _base_colour.lerp(Color(1.0, 0.65, 0.0), grip)
		if _state_label:
			_state_label.text     = "GRAPPLE[%s]" % pose_name
			_state_label.modulate = Color(1.0, 0.70, 0.0)
	else:
		_restore_base_colours()
		if _state_label:
			_state_label.modulate = Color.WHITE


# ── Godot lifecycle ────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	# Guard: do nothing until setup() has been called.
	if _pivot == null:
		return

	# ── Position interpolation (skip when held — AnankeController drives pos) ──
	if not _is_held:
		_lerp_t = minf(_lerp_t + delta * 20.0, 1.0)
		position = _prev_pos.lerp(_target_pos, _lerp_t)

	# ── Prone / tilt ──────────────────────────────────────────────────────────
	_prone_angle_current = move_toward(
		_prone_angle_current,
		_prone_angle_target,
		TILT_SPEED * delta
	)
	_pivot.rotation.x = _prone_angle_current

	# ── Arm poses ─────────────────────────────────────────────────────────────
	var target_right_x: float = ARM_SWING_ANGLE if _anim_state == AnimState.ATTACKING  else 0.0
	var target_left_x:  float = SHIELD_UP_ANGLE if _anim_state == AnimState.GUARDING   else 0.0

	_right_arm_node.rotation.x = move_toward(
		_right_arm_node.rotation.x, target_right_x, 6.0 * delta
	)
	_left_arm_node.rotation.x = move_toward(
		_left_arm_node.rotation.x, target_left_x, 6.0 * delta
	)

	# ── Flash timer ───────────────────────────────────────────────────────────
	if _flash_timer > 0.0:
		_flash_timer -= delta
		if _flash_timer <= 0.0:
			_flash_timer = 0.0
			_restore_base_colours()
		else:
			# Lerp all body materials toward the flash colour.
			var frac: float = _flash_timer / 0.25  # normalise against max flash duration
			_tint_all_materials(_base_colour.lerp(_flash_colour, frac))


# ── Character construction ────────────────────────────────────────────────────

func _build_character() -> void:
	# Root pivot — rotated for prone/unconscious/dead states.
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	add_child(_pivot)

	# ── Body (torso capsule) ──────────────────────────────────────────────────
	_body_mat  = _make_material(_base_colour)
	_body_mesh = _make_capsule_mesh(0.18, 0.70, _body_mat)
	_body_mesh.name = "Body"
	_body_mesh.position = Vector3(0.0, 1.25, 0.0)
	_pivot.add_child(_body_mesh)

	# ── Head (sphere) ─────────────────────────────────────────────────────────
	_head_mat  = _make_material(_base_colour)
	_head_mesh = _make_sphere_mesh(0.13, _head_mat)
	_head_mesh.name = "Head"
	_head_mesh.position = Vector3(0.0, 1.80, 0.0)
	_pivot.add_child(_head_mesh)

	# ── Left arm ──────────────────────────────────────────────────────────────
	_left_arm_mat  = _make_material(_base_colour)
	_left_arm_node = _make_limb_pivot(
		Vector3(-0.30, 1.55, 0.0),
		0.07, 0.50,
		Vector3(0.0, -0.25, 0.0),
		_left_arm_mat,
		"LeftArm"
	)
	_pivot.add_child(_left_arm_node)

	# ── Right arm ─────────────────────────────────────────────────────────────
	_right_arm_mat  = _make_material(_base_colour)
	_right_arm_node = _make_limb_pivot(
		Vector3(0.30, 1.55, 0.0),
		0.07, 0.50,
		Vector3(0.0, -0.25, 0.0),
		_right_arm_mat,
		"RightArm"
	)
	_pivot.add_child(_right_arm_node)

	# ── Left leg ──────────────────────────────────────────────────────────────
	_left_leg_mat  = _make_material(_base_colour)
	_left_leg_node = _make_limb_pivot(
		Vector3(-0.12, 0.90, 0.0),
		0.09, 0.80,
		Vector3(0.0, -0.40, 0.0),
		_left_leg_mat,
		"LeftLeg"
	)
	_pivot.add_child(_left_leg_node)

	# ── Right leg ─────────────────────────────────────────────────────────────
	_right_leg_mat  = _make_material(_base_colour)
	_right_leg_node = _make_limb_pivot(
		Vector3(0.12, 0.90, 0.0),
		0.09, 0.80,
		Vector3(0.0, -0.40, 0.0),
		_right_leg_mat,
		"RightLeg"
	)
	_pivot.add_child(_right_leg_node)

	# ── Labels ────────────────────────────────────────────────────────────────
	_name_label = Label3D.new()
	_name_label.name      = "NameLabel"
	_name_label.text      = _disp_name
	_name_label.position  = Vector3(0.0, 2.10, 0.0)
	_name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_label.modulate  = Color.WHITE
	_name_label.font_size = 24
	_pivot.add_child(_name_label)

	_state_label = Label3D.new()
	_state_label.name      = "StateLabel"
	_state_label.text      = "IDLE"
	_state_label.position  = Vector3(0.0, 2.30, 0.0)
	_state_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_state_label.modulate  = Color.WHITE
	_state_label.font_size = 20
	_pivot.add_child(_state_label)

	# ── Segment → node mapping ────────────────────────────────────────────────
	# Limb mesh nodes are children of their pivot Node3D (index 0).
	_segment_nodes = {
		"thorax":   _body_mesh,
		"abdomen":  _body_mesh,
		"pelvis":   _body_mesh,
		"head":     _head_mesh,
		"neck":     _head_mesh,
		"leftArm":  _left_arm_node.get_child(0),
		"rightArm": _right_arm_node.get_child(0),
		"leftLeg":  _left_leg_node.get_child(0),
		"rightLeg": _right_leg_node.get_child(0),
	}


# ── Animation state machine ────────────────────────────────────────────────────

func _determine_anim_state(snap: Dictionary, anim: Dictionary) -> AnimState:
	if snap.get("dead", false):
		return AnimState.DEAD
	if snap.get("unconscious", false):
		return AnimState.UNCONSCIOUS
	if anim.get("prone", false):
		return AnimState.PRONE
	var shock_q:    float = float(anim.get("shockQ",     0)) / SCALE_Q
	var attack_q:   float = float(anim.get("attackingQ", 0)) / SCALE_Q
	var guard_q:    float = float(anim.get("guardingQ",  0)) / SCALE_Q
	if shock_q > 0.3:
		return AnimState.SHOCKED
	if attack_q > 0.2:
		return AnimState.ATTACKING
	if guard_q > 0.3:
		return AnimState.GUARDING
	return AnimState.IDLE


func _set_anim_state(new_state: AnimState) -> void:
	_anim_state = new_state

	match new_state:
		AnimState.IDLE:
			_prone_angle_target = 0.0
			if _state_label:
				_state_label.text     = "IDLE"
				_state_label.modulate = Color.WHITE
			_restore_base_colours()

		AnimState.GUARDING:
			_prone_angle_target = 0.0
			if _state_label:
				_state_label.text     = "GUARD"
				_state_label.modulate = Color.CYAN
			_restore_base_colours()

		AnimState.ATTACKING:
			_prone_angle_target = 0.0
			if _state_label:
				_state_label.text     = "ATTACK"
				_state_label.modulate = Color.YELLOW
			# Trigger attack flash (gold, 0.15 s).
			_flash_colour = COLOUR_ATTACK_FLASH
			_flash_timer  = 0.15

		AnimState.SHOCKED:
			if _state_label:
				_state_label.text     = "SHOCKED"
				_state_label.modulate = Color.RED
			# Trigger shock flash (red, 0.25 s).
			_flash_colour = COLOUR_SHOCK_FLASH
			_flash_timer  = 0.25

		AnimState.PRONE:
			_prone_angle_target = PI / 2.0
			if _state_label:
				_state_label.text     = "PRONE"
				_state_label.modulate = Color.ORANGE

		AnimState.UNCONSCIOUS:
			_prone_angle_target = PI / 2.5
			if _state_label:
				_state_label.text     = "KO"
				_state_label.modulate = Color(0.60, 0.10, 0.80)  # purple
			# Darken base colour.
			_tint_all_materials(_base_colour * 0.5)

		AnimState.DEAD:
			_prone_angle_target = PI / 2.0
			if _state_label:
				_state_label.text     = "DEAD"
				_state_label.modulate = Color.DIM_GRAY
			_tint_all_materials(COLOUR_DEAD)


# ── Segment damage colouring ──────────────────────────────────────────────────

func _update_segment_colour(seg_id: String, surface_q: float, structural_q: float) -> void:
	if not _segment_nodes.has(seg_id):
		return
	var mesh_node: MeshInstance3D = _segment_nodes[seg_id]

	var damage: float = maxf(surface_q, structural_q * 1.5)
	var tint: Color
	if damage < 0.15:
		tint = Color.WHITE
	elif damage < 0.50:
		tint = Color(1.0, 0.8, 0.7)   # pale pink — light injury
	else:
		tint = Color(0.7, 0.2, 0.2)   # dark red — heavy injury

	var mat: StandardMaterial3D = mesh_node.get_surface_override_material(0)
	if mat:
		mat.albedo_color = _base_colour * tint


# ── Helpers ───────────────────────────────────────────────────────────────────

func _make_material(colour: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.roughness    = 0.7
	mat.metallic     = 0.1
	return mat


func _make_capsule_mesh(radius: float, height: float, mat: StandardMaterial3D) -> MeshInstance3D:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.set_surface_override_material(0, mat)
	return mi


func _make_sphere_mesh(radius: float, mat: StandardMaterial3D) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.set_surface_override_material(0, mat)
	return mi


## Creates a limb pivot Node3D containing one CapsuleMesh child offset by mesh_offset.
func _make_limb_pivot(
	pivot_pos:   Vector3,
	radius:      float,
	height:      float,
	mesh_offset: Vector3,
	mat:         StandardMaterial3D,
	node_name:   String
) -> Node3D:
	var pivot := Node3D.new()
	pivot.name     = node_name
	pivot.position = pivot_pos

	var mesh_inst := _make_capsule_mesh(radius, height, mat)
	mesh_inst.name     = node_name + "Mesh"
	mesh_inst.position = mesh_offset
	pivot.add_child(mesh_inst)

	return pivot


func _restore_base_colours() -> void:
	_tint_all_materials(_base_colour)


func _tint_all_materials(colour: Color) -> void:
	var all_mats: Array[StandardMaterial3D] = [
		_body_mat, _head_mat,
		_left_arm_mat, _right_arm_mat,
		_left_leg_mat, _right_leg_mat,
	]
	for mat in all_mats:
		if mat:
			mat.albedo_color = colour
