## AnankeDoc: Maintains the WebSocket link to the Ananke sidecar, parses
## pushed JSON frames, and exposes connection lifecycle signals to the demo.
extends RefCounted
class_name AnankeReceiver

signal snapshots_received(snapshots: Array, metadata: Dictionary)
signal connection_status_changed(status: String, details: String)

const DEFAULT_URL := "ws://127.0.0.1:7373"

var _socket := WebSocketPeer.new()
var _url := DEFAULT_URL
var _is_connecting := false
var _last_status := "disconnected"
var _last_details := "Waiting for sidecar"

func connect_to_sidecar(url: String = DEFAULT_URL) -> int:
	_url = url
	_socket = WebSocketPeer.new()
	_is_connecting = true
	_emit_status("connecting", "Connecting to %s" % _url)
	var err := _socket.connect_to_url(_url)
	if err != OK:
		_is_connecting = false
		_emit_status("error", "Connection failed (%s)" % error_string(err))
	return err

func disconnect_from_sidecar(code: int = 1000, reason: String = "client_shutdown") -> void:
	if _socket.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		_socket.close(code, reason)
	_is_connecting = false
	_emit_status("disconnected", "Disconnected from sidecar")

func poll() -> void:
	_socket.poll()
	match _socket.get_ready_state():
		WebSocketPeer.STATE_CONNECTING:
			if not _is_connecting:
				_is_connecting = true
				_emit_status("connecting", "Connecting to %s" % _url)
		WebSocketPeer.STATE_OPEN:
			if _is_connecting or _last_status != "connected":
				_is_connecting = false
				_emit_status("connected", "Connected to %s" % _url)
			_read_packets()
		WebSocketPeer.STATE_CLOSING:
			_emit_status("closing", "Connection closing")
		WebSocketPeer.STATE_CLOSED:
			var close_code := _socket.get_close_code()
			var reason := _socket.get_close_reason()
			if _last_status != "disconnected" and _last_status != "error":
				if close_code == -1:
					_emit_status("error", "Connection closed before handshake completed")
				else:
					var message := "Connection closed"
					if reason != "":
						message += ": %s" % reason
					_emit_status("disconnected", "%s (code %d)" % [message, close_code])

func is_connected() -> bool:
	return _socket.get_ready_state() == WebSocketPeer.STATE_OPEN

func get_status() -> Dictionary:
	return {
		"status": _last_status,
		"details": _last_details,
		"url": _url,
	}

func _read_packets() -> void:
	while _socket.get_available_packet_count() > 0:
		var packet := _socket.get_packet()
		if _socket.was_string_packet():
			_parse_message(packet.get_string_from_utf8())

func _parse_message(payload: String) -> void:
	var json := JSON.new()
	var parse_err := json.parse(payload)
	if parse_err != OK:
		_emit_status("error", "Invalid frame JSON: %s" % json.get_error_message())
		return

	if typeof(json.data) != TYPE_DICTIONARY:
		_emit_status("error", "Expected object frame payload")
		return

	var frame: Dictionary = json.data
	if frame.get("type", "") != "snapshot":
		return

	var snapshots: Variant = frame.get("snapshots", [])
	if typeof(snapshots) != TYPE_ARRAY:
		_emit_status("error", "Snapshot payload missing array")
		return

	var metadata := {
		"tick": int(frame.get("tick", 0)),
		"sent_at_ms": float(frame.get("sentAtMs", 0.0)),
		"entity_count": int(frame.get("entityCount", 0)),
	}
	snapshots_received.emit(snapshots, metadata)

func _emit_status(status: String, details: String) -> void:
	if status == _last_status and details == _last_details:
		return
	_last_status = status
	_last_details = details
	connection_status_changed.emit(status, details)
