import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:typed_data/typed_data.dart';

import '../models/mqtt_connection.dart';
import '../models/payload_format.dart';

class MqttService {
  MqttServerClient? _client;

  bool get isConnected =>
      _client?.connectionStatus?.state == MqttConnectionState.connected;

  Stream<List<MqttReceivedMessage<MqttMessage>>>? get messages => _client?.updates;

  Future<void> connect(
    MqttConnection conn, {
    void Function()? onConnected,
    void Function()? onDisconnected,
    void Function(Object error)? onFailed,
  }) async {
    final isWs = conn.protocol == 'WebSocket';

    final server = isWs
        ? '${conn.useTls ? 'wss' : 'ws'}://${conn.host}:${conn.port}${_normalizeWsPath(conn.wsPath)}'
        : conn.host;

    final localClient = isWs
        ? MqttServerClient(server, conn.clientId)
        : MqttServerClient.withPort(server, conn.clientId, conn.port);

    _client = localClient;

    localClient.port = conn.port;
    localClient.logging(on: false);

    localClient.keepAlivePeriod = 20;
    localClient.connectTimeoutPeriod = 10;

    localClient.autoReconnect = false;
    localClient.resubscribeOnAutoReconnect = false;

    localClient.onConnected = () {
      if (!identical(_client, localClient)) return;
      print('[MQTT] Connected');
      onConnected?.call();
    };

    localClient.onDisconnected = () {
      if (!identical(_client, localClient)) return;
      final st = localClient.connectionStatus?.state;
      final rc = localClient.connectionStatus?.returnCode;
      print('[MQTT] Disconnected. state=$st returnCode=$rc');
      onDisconnected?.call();
    };

    localClient.onFailedConnectionAttempt = (int code) {
      if (!identical(_client, localClient)) return;
      print('[MQTT] Failed connection attempt code=$code');
      onFailed?.call(Exception('Failed connection attempt code=$code'));
    };

    if (isWs) {
      localClient.useWebSocket = true;
      localClient.websocketProtocols = const ['mqtt'];
    } else {
      localClient.secure = conn.useTls;
      if (conn.useTls) {
        localClient.securityContext = SecurityContext.defaultContext;
      }
    }

    localClient.connectionMessage = MqttConnectMessage()
        .withClientIdentifier(conn.clientId)
        .startClean()
        .withWillQos(MqttQos.atMostOnce);

    try {
      print('[MQTT] Connecting to $server (protocol=${conn.protocol}, tls=${conn.useTls})');

      await localClient
          .connect(conn.username, conn.password)
          .timeout(const Duration(seconds: 12), onTimeout: () {
        throw TimeoutException('MQTT connect timed out after 12s');
      });
    } catch (e) {
      if (identical(_client, localClient)) {
        try {
          localClient.disconnect();
        } catch (_) {}
      }
      onFailed?.call(e);
      rethrow;
    }

    final status = localClient.connectionStatus;
    if (status?.state != MqttConnectionState.connected) {
      final rc = status?.returnCode;
      try {
        localClient.disconnect();
      } catch (_) {}
      final err = Exception('MQTT connect failed: $rc');
      onFailed?.call(err);
      throw err;
    }
  }

  // ---------------- Publish multi-format ----------------

  void publishPayload(
    String topic,
    String input, {
    required MqttQos qos,
    required bool retain,
    required PayloadFormat format,
  }) {
    final c = _client;
    if (c == null || !isConnected) {
      throw StateError('MQTT client is not connected');
    }

    final bytes = _encodeInput(input, format);

    final builder = MqttClientPayloadBuilder();
    builder.addBuffer(Uint8Buffer()..addAll(bytes)); // Windows-safe

    c.publishMessage(topic, qos, builder.payload!, retain: retain);
  }

  // Backwards compatible
  void publish(
    String topic,
    String message, {
    required MqttQos qos,
    required bool retain,
  }) {
    publishPayload(
      topic,
      message,
      qos: qos,
      retain: retain,
      format: PayloadFormat.text,
    );
  }

  Uint8List _encodeInput(String input, PayloadFormat format) {
    switch (format) {
      case PayloadFormat.text:
        return Uint8List.fromList(utf8.encode(input));

      case PayloadFormat.json:
        final decoded = json.decode(input);
        final normalized = json.encode(decoded);
        return Uint8List.fromList(utf8.encode(normalized));

      case PayloadFormat.base64:
        return base64.decode(_stripWhitespace(input));

      case PayloadFormat.hex:
        return _hexToBytes(_stripWhitespace(input));
    }
  }

  String _stripWhitespace(String s) => s.replaceAll(RegExp(r'\s+'), '');

  Uint8List _hexToBytes(String hex) {
    final cleaned = hex.startsWith('0x') ? hex.substring(2) : hex;
    if (cleaned.isEmpty) return Uint8List(0);
    if (cleaned.length % 2 != 0) {
      throw const FormatException('HEX must have even length (2 chars per byte).');
    }

    final out = Uint8List(cleaned.length ~/ 2);
    for (int i = 0; i < cleaned.length; i += 2) {
      final byteStr = cleaned.substring(i, i + 2);
      final v = int.tryParse(byteStr, radix: 16);
      if (v == null) throw FormatException('Invalid HEX byte: "$byteStr"');
      out[i ~/ 2] = v;
    }
    return out;
  }

  // ---------------- Sub / Unsub ----------------

  void subscribe(String topic, MqttQos qos) {
    final c = _client;
    if (c == null || !isConnected) {
      throw StateError('MQTT client is not connected');
    }
    c.subscribe(topic, qos);
  }

  void unsubscribe(String topic) {
    final c = _client;
    if (c == null) return;
    try {
      if (!isConnected) return;
      c.unsubscribe(topic);
    } catch (_) {}
  }

  void disconnect() {
    final c = _client;
    _client = null;
    try {
      c?.disconnect();
    } catch (_) {}
  }

  String _normalizeWsPath(String p) {
    final path = p.trim().isEmpty ? '/mqtt' : p.trim();
    return path.startsWith('/') ? path : '/$path';
  }
}