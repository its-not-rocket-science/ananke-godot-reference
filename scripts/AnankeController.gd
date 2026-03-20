## AnankeDoc: Orchestrates sidecar connectivity, routes streamed snapshots to
## character rigs, and updates the waiting overlay for connection failures.
extends Node3D

const SIDECAR_URL := "ws://127.0.0.1:7373"
const RECONNECT_INTERVAL_S := 2.0

var _receiver := AnankeReceiver.new()
var _mapper := SkeletonMapper.new()
var _animation_driver := AnimationDriver.new()
var _grapple_applicator := GrappleApplicator.new()
var _entity_nodes: Dictionary = {}
var _reconnect_timer := 0.0

@onready var waiting_overlay: CanvasLayer = $WaitingOverlay
@onready var waiting_label: Label = $WaitingOverlay/PanelContainer/MarginContainer/VBoxContainer/StatusLabel
@onready var waiting_hint: Label = $WaitingOverlay/PanelContainer/MarginContainer/VBoxContainer/HintLabel

func _ready() -> void:
	_register_entities()
	_receiver.snapshots_received.connect(_on_snapshots_received)
	_receiver.connection_status_changed.connect(_on_connection_status_changed)
	_set_overlay_state(true, "Waiting for sidecar", "Start the sidecar to stream frames into Godot.")
	_attempt_connection()

func _process(delta: float) -> void:
	_receiver.poll()
	var status := String(_receiver.get_status().get("status", "disconnected"))
	if not _receiver.is_connected() and status != "connecting":
		_reconnect_timer += delta
		if _reconnect_timer >= RECONNECT_INTERVAL_S:
			_attempt_connection()

func _exit_tree() -> void:
	_receiver.disconnect_from_sidecar()

func _register_entities() -> void:
	for child in get_children():
		if child is CharacterRig:
			var entity_id := int(child.get_meta("entity_id", child.name.trim_prefix("Entity")))
			if entity_id > 0:
				_entity_nodes[entity_id] = child

func _attempt_connection() -> void:
	_reconnect_timer = 0.0
	var err := _receiver.connect_to_sidecar(SIDECAR_URL)
	if err != OK:
		push_warning("AnankeController: unable to start WebSocket connection (%s)" % error_string(err))

func _on_connection_status_changed(status: String, details: String) -> void:
	match status:
		"connected":
			_reconnect_timer = 0.0
			_set_overlay_state(false, "Connected", details)
		"connecting":
			_set_overlay_state(true, "Waiting for sidecar", details)
		"closing", "disconnected":
			_set_overlay_state(true, "Waiting for sidecar", "%s\nRetrying every %.1fs." % [details, RECONNECT_INTERVAL_S])
		"error":
			_set_overlay_state(true, "Connection error", "%s\nRetrying every %.1fs." % [details, RECONNECT_INTERVAL_S])
			push_warning("AnankeController: %s" % details)

func _on_snapshots_received(snapshots: Array, metadata: Dictionary) -> void:
	_set_overlay_state(false, "Streaming", "Receiving tick %d for %d entities." % [int(metadata.get("tick", 0)), int(metadata.get("entity_count", snapshots.size()))])
	for entity_id in _entity_nodes.keys():
		var rig: CharacterRig = _entity_nodes[entity_id]
		_mapper.reset_pose(rig.skeleton)
		rig.set_grapple_state(false, -1, "", 0.0)

	for snapshot in snapshots:
		if typeof(snapshot) != TYPE_DICTIONARY:
			continue
		var entity_id := int(snapshot.get("entityId", -1))
		var rig: CharacterRig = _entity_nodes.get(entity_id)
		if rig == null:
			continue
		_mapper.apply_snapshot(rig, rig.skeleton, snapshot)
		_animation_driver.apply_hints(rig, snapshot)
		_grapple_applicator.apply_grapple(rig, snapshot, _entity_nodes)

func _set_overlay_state(visible_state: bool, title: String, details: String) -> void:
	waiting_overlay.visible = visible_state
	waiting_label.text = title
	waiting_hint.text = details
