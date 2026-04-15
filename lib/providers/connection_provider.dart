import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:convert' show utf8;

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/mqtt_connection.dart';
import '../models/dashboard_widget.dart';
import '../services/mqtt_service.dart';

enum ConnectionStatus { idle, connecting, connected, failed }

class ConnectionProvider extends ChangeNotifier {
  static const _kConnectionsKey = 'connections_v2';
  static const _kSubsKey = 'subs_by_connection_v1';
  static const _kDashboardKey = 'dashboard_by_connection_v1';
  static const _secure = FlutterSecureStorage();

  final MqttService mqttService = MqttService();

  final List<MqttConnection> connections = [];
  final Map<String, Map<String, int>> subsByConnId = {};
  final Map<String, List<DashboardWidgetConfig>> dashboardByConnId = {};

  MqttConnection? activeConnection;

  ConnectionStatus status = ConnectionStatus.idle;
  String? lastError;
  bool isLoaded = false;

  int _connectEpoch = 0;

  // ✅ Global cache: last payload per topic (survives screen navigation)
  final Map<String, String> lastPayloadByTopic = {};
  final Map<String, DateTime> lastPayloadTsByTopic = {};

  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? _messagesSub;

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

  List<DashboardWidgetConfig> get activeDashboardWidgets {
    final id = activeConnection?.id;
    if (id == null) return const [];
    return dashboardByConnId[id] ?? const [];
  }

  ConnectionProvider() {
    _loadFromStorage();
  }

  String _pwdKey(String connId) => 'mqtt_pwd_$connId';

  Future<void> _loadFromStorage() async {
    final prefs = await SharedPreferences.getInstance();

    // connections
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

    // topics
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

    // dashboard widgets
    final dashStr = prefs.getString(_kDashboardKey);
    if (dashStr != null && dashStr.isNotEmpty) {
      final decoded = json.decode(dashStr) as Map<String, dynamic>;
      dashboardByConnId
        ..clear()
        ..addAll(decoded.map((connId, listObj) {
          final list = (listObj as List<dynamic>)
              .map((e) => DashboardWidgetConfig.fromJson(e as Map<String, dynamic>))
              .toList();
          return MapEntry(connId, list);
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

  Future<void> _saveDashboard() async {
    final prefs = await SharedPreferences.getInstance();
    final data = dashboardByConnId.map((connId, list) {
      return MapEntry(connId, list.map((e) => e.toJson()).toList());
    });
    await prefs.setString(_kDashboardKey, json.encode(data));
  }

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
    dashboardByConnId.remove(id);

    await _secure.delete(key: _pwdKey(id));
    await _saveConnections();
    await _saveSubs();
    await _saveDashboard();

    if (activeConnection?.id == id) disconnect();

    notifyListeners();
  }

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

    subsByConnId[connId]?.remove(topic);
    await _saveSubs();
    notifyListeners();

    if (alsoUnsubscribe && isConnected) {
      try {
        mqttService.unsubscribe(topic);
      } catch (_) {}
    }
  }

  // ---------------- Dashboard CRUD ----------------

  Future<void> addDashboardWidget(DashboardWidgetConfig w) async {
    final connId = activeConnection?.id;
    if (connId == null) return;

    final list = dashboardByConnId.putIfAbsent(connId, () => []);
    list.add(w);

    await _saveDashboard();
    notifyListeners();
  }

  Future<void> deleteDashboardWidget(String widgetId) async {
    final connId = activeConnection?.id;
    if (connId == null) return;

    dashboardByConnId[connId]?.removeWhere((e) => e.id == widgetId);

    await _saveDashboard();
    notifyListeners();
  }

  // ---------------- Global message cache ----------------

  void _startListeningToMessages() {
    _messagesSub?.cancel();
    _messagesSub = mqttService.messages?.listen((events) {
      for (final msg in events) {
        final topic = msg.topic;
        final pub = msg.payload as MqttPublishMessage;

        final bytes = Uint8List.fromList(pub.payload.message);
        final payloadText = _bytesToDisplay(bytes);

        lastPayloadByTopic[topic] = payloadText;
        lastPayloadTsByTopic[topic] = DateTime.now();
      }

      // Notify UI that state changed
      notifyListeners();
    });
  }

  String? lastPayload(String topic) => lastPayloadByTopic[topic];
  DateTime? lastPayloadTs(String topic) => lastPayloadTsByTopic[topic];

  // ---------------- Subscriptions ----------------

  void ensureDashboardSubscriptions() {
    if (!isConnected) return;

    final tiles = activeDashboardWidgets;
    for (final w in tiles) {
      final topics = <String>[];

      if (w.type == DashboardWidgetType.bridge) {
        if (w.bridgeInputTopic.trim().isNotEmpty) topics.add(w.bridgeInputTopic.trim());
      } else {
        if (w.stateTopic.trim().isNotEmpty) topics.add(w.stateTopic.trim());
      }

      for (final t in topics) {
        try {
          mqttService.subscribe(t, _toQos(w.subQos));
        } catch (_) {}
      }
    }
  }

  void _subscribeSavedTopics(String connId) {
    final saved = subsByConnId[connId] ?? const <String, int>{};
    for (final entry in saved.entries) {
      try {
        mqttService.subscribe(entry.key, _toQos(entry.value));
      } catch (_) {}
    }
  }

  // ✅ Call this on connect or when user enters topics/dashboard if needed
  void refreshAllKnownSubscriptions() {
    if (!isConnected || activeConnection == null) return;
    _subscribeSavedTopics(activeConnection!.id);
    ensureDashboardSubscriptions();
  }

  // ---------------- Connection Lifecycle ----------------

  Future<bool> connect(MqttConnection conn) async {
    final int myEpoch = ++_connectEpoch;

    // disconnect old client
    mqttService.disconnect();

    // IMPORTANT: Clear caches on new connection (optional)
    lastPayloadByTopic.clear();
    lastPayloadTsByTopic.clear();

    activeConnection = conn;
    status = ConnectionStatus.connecting;
    lastError = null;
    notifyListeners();

    try {
      await mqttService.connect(
        conn,
        onConnected: () {
          if (myEpoch != _connectEpoch) return;

          status = ConnectionStatus.connected;
          lastError = null;
          activeConnection = conn;

          // ✅ Start one global listener for message cache
          _startListeningToMessages();

          // ✅ Subscribe to saved + dashboard topics.
          // If state topics are retained, broker sends last state immediately.
          _subscribeSavedTopics(conn.id);
          ensureDashboardSubscriptions();

          notifyListeners();
        },
        onDisconnected: () {
          if (myEpoch != _connectEpoch) return;
          status = ConnectionStatus.idle;
          lastError = null;
          notifyListeners();
        },
        onFailed: (e) {
          if (myEpoch != _connectEpoch) return;
          status = ConnectionStatus.failed;
          lastError = e.toString();
          notifyListeners();
        },
      );

      if (myEpoch != _connectEpoch) return false;

      if (!mqttService.isConnected) {
        status = ConnectionStatus.failed;
        lastError = 'Connect finished but client is not connected.';
        notifyListeners();
        return false;
      }

      status = ConnectionStatus.connected;
      activeConnection = conn;

      // Ensure listener + subscriptions
      _startListeningToMessages();
      _subscribeSavedTopics(conn.id);
      ensureDashboardSubscriptions();

      notifyListeners();
      return true;
    } catch (e) {
      if (myEpoch != _connectEpoch) return false;

      status = ConnectionStatus.failed;
      lastError = e.toString();
      notifyListeners();
      return false;
    }
  }

  void disconnect() {
    _connectEpoch++; // invalidate callbacks

    _messagesSub?.cancel();
    _messagesSub = null;

    mqttService.disconnect();
    activeConnection = null;
    status = ConnectionStatus.idle;
    lastError = null;

    // optional: keep cache; but usually clear on disconnect
    lastPayloadByTopic.clear();
    lastPayloadTsByTopic.clear();

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

  static String _bytesToDisplay(Uint8List bytes) {
    try {
      return utf8.decode(bytes);
    } catch (_) {
      final b = StringBuffer();
      for (final v in bytes) {
        b.write(v.toRadixString(16).padLeft(2, '0'));
      }
      return '[BIN ${bytes.length} bytes] ${b.toString().toUpperCase()}';
    }
  }
}