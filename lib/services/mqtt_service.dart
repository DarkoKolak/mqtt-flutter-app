import 'dart:io';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import '../models/mqtt_connection.dart';

class MqttService {
  late MqttServerClient client;

  bool get isConnected =>
      client.connectionStatus?.state == MqttConnectionState.connected;

  Stream<List<MqttReceivedMessage<MqttMessage>>>? get messages => client.updates;

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

    client = isWs
        ? MqttServerClient(server, conn.clientId)
        : MqttServerClient.withPort(server, conn.clientId, conn.port);

    client.port = conn.port;

    client.logging(on: false);
    client.keepAlivePeriod = 20;
    client.connectTimeoutPeriod = 10;

    client.onConnected = () {
      print('[MQTT] Connected');
      onConnected?.call();
    };

    client.onDisconnected = () {
      final st = client.connectionStatus?.state;
      final rc = client.connectionStatus?.returnCode;
      print('[MQTT] Disconnected. state=$st returnCode=$rc');
      onDisconnected?.call();
    };

    client.onFailedConnectionAttempt = (int code) {
      print('[MQTT] Failed connection attempt code=$code');
      onFailed?.call(Exception('Failed connection attempt code=$code'));
    };

    if (isWs) {
      client.useWebSocket = true;
      client.websocketProtocols = const ['mqtt'];
    } else {
      client.secure = conn.useTls;
      if (conn.useTls) {
        client.securityContext = SecurityContext.defaultContext;
      }
    }

    client.connectionMessage = MqttConnectMessage()
        .withClientIdentifier(conn.clientId)
        .startClean()
        .withWillQos(MqttQos.atMostOnce);

    try {
      print('[MQTT] Connecting to $server (protocol=${conn.protocol}, tls=${conn.useTls})');
      await client.connect(conn.username, conn.password);
    } catch (e) {
      client.disconnect();
      onFailed?.call(e);
      rethrow;
    }

    final status = client.connectionStatus;
    if (status?.state != MqttConnectionState.connected) {
      final rc = status?.returnCode;
      client.disconnect();
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
    if (!isConnected) {
      throw StateError('MQTT client is not connected');
    }
    client.subscribe(topic, qos);
  }

void unsubscribe(String topic) {
  try {
    if (!isConnected) return;
    client.unsubscribe(topic);
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
    if (!isConnected) {
      throw StateError('MQTT client is not connected');
    }
    final builder = MqttClientPayloadBuilder();
    builder.addUTF8String(message);
    client.publishMessage(topic, qos, builder.payload!, retain: retain);
  }

  void disconnect() {
    try {
      client.disconnect();
    } catch (_) {}
  }
}
