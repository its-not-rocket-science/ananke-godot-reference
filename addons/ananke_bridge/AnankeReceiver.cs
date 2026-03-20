using System;
using System.Text.Json;
using Godot;

namespace Ananke.Bridge;

public partial class AnankeReceiver : Node
{
    [Signal]
    public delegate void ConnectionStateChangedEventHandler(bool connected);

    public event Action<AnankeFrameEnvelope>? FrameReceived;

    [Export] public string Endpoint { get; set; } = "ws://127.0.0.1:7373/ws";
    [Export] public float ReconnectDelaySeconds { get; set; } = 1.0f;

    private readonly JsonSerializerOptions _jsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
    };

    private WebSocketPeer _socket = new();
    private bool _connected;
    private double _reconnectAtMs;

    public override void _Ready()
    {
        ConnectSocket();
    }

    public override void _Process(double delta)
    {
        _socket.Poll();
        var state = _socket.GetReadyState();

        if (state == WebSocketPeer.State.Open)
        {
            if (!_connected)
            {
                _connected = true;
                EmitSignal(SignalName.ConnectionStateChanged, true);
            }

            while (_socket.GetAvailablePacketCount() > 0)
            {
                var payload = _socket.GetPacket().GetStringFromUtf8();
                TryEmitFrame(payload);
            }

            return;
        }

        if (_connected && state != WebSocketPeer.State.Connecting)
        {
            _connected = false;
            EmitSignal(SignalName.ConnectionStateChanged, false);
            _reconnectAtMs = Time.GetTicksMsec() + (long)(ReconnectDelaySeconds * 1000.0f);
        }

        if (state == WebSocketPeer.State.Closed && Time.GetTicksMsec() >= _reconnectAtMs)
        {
            ConnectSocket();
        }
    }

    private void ConnectSocket()
    {
        _socket = new WebSocketPeer();
        var error = _socket.ConnectToUrl(Endpoint);
        if (error != Error.Ok)
        {
            GD.PushWarning($"AnankeReceiver failed to connect to {Endpoint}: {error}");
            _reconnectAtMs = Time.GetTicksMsec() + (long)(ReconnectDelaySeconds * 1000.0f);
        }
    }

    private void TryEmitFrame(string payload)
    {
        try
        {
            var frame = JsonSerializer.Deserialize<AnankeFrameEnvelope>(payload, _jsonOptions);
            if (frame is null)
            {
                GD.PushWarning("AnankeReceiver received an empty frame payload.");
                return;
            }

            FrameReceived?.Invoke(frame);
        }
        catch (Exception exception)
        {
            GD.PushWarning($"AnankeReceiver failed to parse frame JSON: {exception.Message}");
        }
    }
}
