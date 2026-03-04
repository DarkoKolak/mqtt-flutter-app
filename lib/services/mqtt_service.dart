import 'dart:async';
import 'dart:io';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import '../models/mqtt_connection.dart';

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

    // Make this client current BEFORE callbacks can fire
    _client = localClient;

    localClient.port = conn.port;

    localClient.logging(on: false);

    // Keepalive + timeouts
    localClient.keepAlivePeriod = 20;
    localClient.connectTimeoutPeriod = 10;

    // Avoid auto reconnect surprises while debugging
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

      // HARD timeout so UI never stays "Connecting..." forever
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

  String _normalizeWsPath(String p) {
    final path = p.trim().isEmpty ? '/mqtt' : p.trim();
    return path.startsWith('/') ? path : '/$path';
  }

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
    } catch (e) {
      print('[MQTT] Unsubscribe ignored error: $e');
    }
  }

  void publish(
    String topic,
    String message, {
    required MqttQos qos,
    required bool retain,
  }) {
    final c = _client;
    if (c == null || !isConnected) {
      throw StateError('MQTT client is not connected');
    }
    final builder = MqttClientPayloadBuilder();
    builder.addUTF8String(message);
    c.publishMessage(topic, qos, builder.payload!, retain: retain);
  }

  void disconnect() {
    final c = _client;
    _client = null; // invalidate immediately so old callbacks are ignored
    try {
      c?.disconnect();
    } catch (_) {}
  }
}