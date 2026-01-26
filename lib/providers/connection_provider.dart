import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/mqtt_connection.dart';
import '../services/mqtt_service.dart';

enum ConnectionStatus { idle, connecting, connected, failed }

class ConnectionProvider extends ChangeNotifier {
  static const _kConnectionsKey = 'connections_v2';
  static const _kSubsKey = 'subs_by_connection_v1';
  static const _secure = FlutterSecureStorage();

  final MqttService mqttService = MqttService();

  final List<MqttConnection> connections = [];

  /// connId -> { topic: qosInt }
  final Map<String, Map<String, int>> subsByConnId = {};

  MqttConnection? activeConnection;

  ConnectionStatus status = ConnectionStatus.idle;
  String? lastError;

  bool isLoaded = false;

  bool get isConnected =>
      status == ConnectionStatus.connected &&
      activeConnection != null &&
      mqttService.isConnected;

  bool get isConnecting => status == ConnectionStatus.connecting;

  Map<String, int> get activeSubs {
    final id = activeConnection?.id;
    if (id == null) return {};
    return subsByConnId[id] ?? {};
  }

  ConnectionProvider() {
    _loadFromStorage();
  }

  // ------------------- persistence -------------------

  String _pwdKey(String connId) => 'mqtt_pwd_$connId';

  Future<void> _loadFromStorage() async {
    final prefs = await SharedPreferences.getInstance();

    final connStr = prefs.getString(_kConnectionsKey);
    if (connStr != null && connStr.isNotEmpty) {
      final decoded = json.decode(connStr) as List<dynamic>;
      final loaded = decoded
          .map((e) => MqttConnection.fromJson(e as Map<String, dynamic>))
          .toList();

      final withPasswords = <MqttConnection>[];
      for (final c in loaded) {
        final pwd = await _secure.read(key: _pwdKey(c.id));
        withPasswords.add(c.copyWith(password: pwd));
      }

      connections
        ..clear()
        ..addAll(withPasswords);
    }

    final subsStr = prefs.getString(_kSubsKey);
    if (subsStr != null && subsStr.isNotEmpty) {
      final decoded = json.decode(subsStr) as Map<String, dynamic>;
      subsByConnId
        ..clear()
        ..addAll(decoded.map((connId, topicsObj) {
          final m = Map<String, dynamic>.from(topicsObj as Map);
          final topicToQos = m.map((t, q) => MapEntry(t, (q as num).toInt()));
          return MapEntry(connId, topicToQos);
        }));
    }

    isLoaded = true;
    notifyListeners();
  }

  Future<void> _saveConnections() async {
    final prefs = await SharedPreferences.getInstance();
    final data = connections.map((c) => c.toJson()).toList();
    await prefs.setString(_kConnectionsKey, json.encode(data));
  }

  Future<void> _saveSubs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSubsKey, json.encode(subsByConnId));
  }

  // ------------------- connections CRUD -------------------

  Future<void> addConnection(MqttConnection conn) async {
    connections.add(conn);
    await _saveConnections();

    if ((conn.password ?? '').isNotEmpty) {
      await _secure.write(key: _pwdKey(conn.id), value: conn.password);
    }

    notifyListeners();
  }

  Future<void> updateConnection(MqttConnection updated) async {
    final idx = connections.indexWhere((c) => c.id == updated.id);
    if (idx == -1) return;

    connections[idx] = updated;
    await _saveConnections();

    if ((updated.password ?? '').isEmpty) {
      await _secure.delete(key: _pwdKey(updated.id));
    } else {
      await _secure.write(key: _pwdKey(updated.id), value: updated.password);
    }

    if (activeConnection?.id == updated.id) {
      activeConnection = updated;
    }

    notifyListeners();
  }

  Future<void> deleteConnection(String id) async {
    connections.removeWhere((c) => c.id == id);
    subsByConnId.remove(id);

    await _secure.delete(key: _pwdKey(id));
    await _saveConnections();
    await _saveSubs();

    if (activeConnection?.id == id) disconnect();

    notifyListeners();
  }

  // ------------------- subscriptions (topic + qos) -------------------

  Future<void> addOrUpdateSubForActive(String topic, int qos) async {
    final connId = activeConnection?.id;
    if (connId == null) return;

    final map = subsByConnId.putIfAbsent(connId, () => {});
    map[topic] = qos;

    await _saveSubs();
    notifyListeners();
  }

  Future<void> removeSubForActive(String topic, {bool alsoUnsubscribe = true}) async {
    final connId = activeConnection?.id;
    if (connId == null) return;

    // 1) remove locally first so UI updates instantly
    subsByConnId[connId]?.remove(topic);
    await _saveSubs();
    notifyListeners();

    // 2) then best-effort unsubscribe, never disconnect on failure
    if (alsoUnsubscribe && isConnected) {
      try {
        mqttService.unsubscribe(topic);
      } catch (e) {
        print('[MQTT] Unsubscribe failed but ignored: $e');
      }
    }
  }

  // ------------------- connect/disconnect -------------------

  Future<bool> connect(MqttConnection conn) async {
    activeConnection = conn;
    status = ConnectionStatus.connecting;
    lastError = null;
    notifyListeners();

    try {
      await mqttService.connect(
        conn,
        onConnected: () {
          status = ConnectionStatus.connected;
          lastError = null;
          notifyListeners();
        },
        onDisconnected: () {
          status = ConnectionStatus.idle;
          lastError = null;
          activeConnection = null;
          notifyListeners();
        },
        onFailed: (e) {
          status = ConnectionStatus.failed;
          lastError = e.toString();
          activeConnection = null;
          notifyListeners();
        },
      );

      // If connect returned, it's connected -> resubscribe saved topics
      status = ConnectionStatus.connected;

      final saved = subsByConnId[conn.id] ?? const {};
      for (final entry in saved.entries) {
        try {
          mqttService.subscribe(entry.key, _toQos(entry.value));
        } catch (_) {}
      }

      notifyListeners();
      return true;
    } catch (e) {
      status = ConnectionStatus.failed;
      lastError = e.toString();
      activeConnection = null;
      notifyListeners();
      return false;
    }
  }

  void disconnect() {
    mqttService.disconnect();
    activeConnection = null;
    status = ConnectionStatus.idle;
    lastError = null;
    notifyListeners();
  }

  MqttQos _toQos(int v) {
    switch (v) {
      case 1:
        return MqttQos.atLeastOnce;
      case 2:
        return MqttQos.exactlyOnce;
      default:
        return MqttQos.atMostOnce;
    }
  }
}
