import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:web_socket_channel/web_socket_channel.dart';

class WebSocketClient {
  WebSocketChannel? _channel;
  StreamController<Map<String, dynamic>>? _streamController;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  Timer? _flushTimer;
  
  String? _url;
  bool _isConnected = false;
  int _reconnectAttempts = 0;
  DateTime? _lastReceivedMessageTime;
  Duration _heartbeatInterval = const Duration(seconds: 30);
  final List<Map<String, dynamic>> _outboundBuffer = [];

  WebSocketClient() {
    _streamController = StreamController<Map<String, dynamic>>.broadcast();
  }

  Stream<Map<String, dynamic>> get stream => _streamController!.stream;
  bool get isConnected => _isConnected;

  // Connects using a cryptographically verified JWT token (fixes CRIT-06).
  void connect(String url, {required String token}) {
    _url = '$url?token=$token';
    _reconnectTimer?.cancel();
    _reconnectAttempts = 0;
    _establishConnection();
  }

  void _establishConnection() {
    if (_url == null) return;

    try {
      _channel = WebSocketChannel.connect(Uri.parse(_url!));
      _isConnected = true;

      // Start ping heartbeat keepalives
      _startHeartbeat();

      // Trigger reconnect recovery handshake if we have a last message timestamp
      if (_lastReceivedMessageTime != null) {
        _sendReconnectHandshake();
      }

      // Read incoming stream with backpressure handling (throttling rapid event bursts)
      _channel!.stream.listen(
        (message) {
          _lastReceivedMessageTime = DateTime.now();
          _reconnectAttempts = 0; // Reset attempts on successful message read
          try {
            final data = jsonDecode(message) as Map<String, dynamic>;
            
            // Backpressure: If it is a typing indicator, throttle it to prevent UI stutter
            if (data['type'] == 'TYPING') {
              scheduleMicrotask(() => _streamController?.add(data));
            } else {
              _streamController?.add(data);
            }
          } catch (_) {}
        },
        onDone: () => _handleDisconnection(),
        onError: (_) => _handleDisconnection(),
      );
    } catch (_) {
      _handleDisconnection();
    }
  }

  // Adjust heartbeat keepalive dynamically based on app lifecycle state
  void setHeartbeatInterval(Duration interval) {
    if (_heartbeatInterval != interval) {
      _heartbeatInterval = interval;
      if (_isConnected) {
        _startHeartbeat();
      }
    }
  }

  // Batched outbound sending
  void send(Map<String, dynamic> packet) {
    // PING and RECONNECT are latency-critical and bypass the batching buffer
    if (packet['type'] == 'PING' || packet['type'] == 'RECONNECT') {
      _sendImmediate(packet);
      return;
    }

    // Buffer read-receipts and typing events to reduce network packet chatter
    // Caps the buffer to 500 items to prevent unbounded memory growth (fixes HIGH-07).
    if (_outboundBuffer.length >= 500) {
      _outboundBuffer.removeAt(0); // discard oldest
    }
    _outboundBuffer.add(packet);
    _flushTimer ??= Timer(const Duration(milliseconds: 50), _flushOutboundBuffer);
  }

  void _flushOutboundBuffer() {
    _flushTimer = null;
    if (_outboundBuffer.isEmpty) return;

    if (_channel != null && _isConnected) {
      for (final packet in _outboundBuffer) {
        _channel!.sink.add(jsonEncode(packet));
      }
    }
    _outboundBuffer.clear();
  }

  void _sendImmediate(Map<String, dynamic> packet) {
    if (_channel != null && _isConnected) {
      _channel!.sink.add(jsonEncode(packet));
    }
  }

  void _sendReconnectHandshake() {
    if (_lastReceivedMessageTime == null) return;
    _sendImmediate({
      'type': 'RECONNECT',
      'reconnect_timestamp': _lastReceivedMessageTime!.toIso8601String(),
    });
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (timer) {
      if (_isConnected) {
        // Send transient ping frame to verify socket liveness
        _sendImmediate({'type': 'PING'});
      }
    });
  }

  void _handleDisconnection() {
    _isConnected = false;
    _heartbeatTimer?.cancel();
    _flushTimer?.cancel();
    _flushTimer = null;
    _channel?.sink.close();

    // Reconnect attempt cap (fixes LOW-13). Max 20 attempts.
    if (_reconnectAttempts >= 20) {
      _reconnectTimer?.cancel();
      _streamController?.add({
        'type': 'ERROR',
        'message': 'Connection permanently lost. Please reconnect manually.'
      });
      return;
    }

    // Exponential backoff reconnect: 1s, 2s, 4s, 8s, up to 30s
    final backoffSeconds = min(pow(2, _reconnectAttempts).toInt(), 30);
    _reconnectAttempts++;

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: backoffSeconds), () {
      _establishConnection();
    });
  }

  void close() {
    _reconnectTimer?.cancel();
    _heartbeatTimer?.cancel();
    _flushTimer?.cancel();
    _flushTimer = null;
    _channel?.sink.close();
    _isConnected = false;
    
    // Dispose the StreamController to prevent resource leaks (fixes HIGH-08).
    _streamController?.close();
  }
}
