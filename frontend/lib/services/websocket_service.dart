import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

class WebSocketService {
  WebSocketChannel? _channel;
  bool _isConnected = false;
  Function(String)? _onAiAlertReceived;

  bool get isConnected => _isConnected;

  void setAiAlertCallback(Function(String) callback) {
    _onAiAlertReceived = callback;
  }

  void connect(String convoyId, String profileId) {
    if (_isConnected) return;
    
    final uri = Uri.parse('ws://localhost:8000/telemetry/ws/convoy/$convoyId?profile_id=$profileId');
    try {
      _channel = WebSocketChannel.connect(uri);
      _isConnected = true;
      
      _channel!.stream.listen(
        (message) {
          _handleIncomingMessage(message);
        },
        onDone: () {
          _isConnected = false;
          print('WebSocket connection closed.');
        },
        onError: (error) {
          _isConnected = false;
          print('WebSocket error: $error');
        },
        cancelOnError: false,
      );
    } catch (e) {
      _isConnected = false;
      print('Failed to connect to WebSocket: $e');
    }
  }

  void _handleIncomingMessage(dynamic message) {
    try {
      final String payloadStr = message.toString();
      final Map<String, dynamic> data = jsonDecode(payloadStr);
      
      if (data['type'] == 'ai_alert' && data['message'] != null) {
        final alertText = data['message'] as String;
        if (_onAiAlertReceived != null) {
          _onAiAlertReceived!(alertText);
        }
      }
    } catch (e) {
      print('Error parsing incoming WebSocket message: $e');
    }
  }

  void streamTelemetry({
    required double latitude,
    required double longitude,
    required double speed,
    required double bearing,
  }) {
    if (!_isConnected || _channel == null) {
      print('WebSocket is not connected. Telemetry packet skipped.');
      return;
    }
    
    final packet = {
      'latitude': latitude,
      'longitude': longitude,
      'speed': speed,
      'bearing': bearing,
    };
    
    try {
      _channel!.sink.add(jsonEncode(packet));
    } catch (e) {
      print('Error sending telemetry packet: $e');
    }
  }

  void disconnect() {
    if (_channel != null) {
      _channel!.sink.close();
      _isConnected = false;
      _channel = null;
    }
  }
}
