import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

class MqttConnection {
  final String id;
  final String name;
  final String host;
  final int port;
  final bool useTls;
  final String protocol; // TCP, WebSocket
  final String wsPath;

  // Icon OR custom image
  final int? iconCodePoint; // store IconData.codePoint
  final String? iconFontFamily; // usually 'MaterialIcons'
  final String? iconFontPackage; // usually null
  final String? imagePath; // local file path (picked from gallery)

  final String clientId;

  final String? username;
  final String? password;

  MqttConnection({
    required this.name,
    required this.host,
    required this.port,
    required this.useTls,
    required this.protocol,
    required this.wsPath,
    required this.clientId,
    required this.iconCodePoint,
    required this.iconFontFamily,
    required this.iconFontPackage,
    required this.imagePath,
    required this.username,
    required this.password,
    String? id,
  }) : id = id ?? const Uuid().v4();

  /// Convenience constructor for "icon mode"
  factory MqttConnection.withIcon({
    required String name,
    required String host,
    required int port,
    required bool useTls,
    required String protocol,
    required String wsPath,
    required IconData icon,
    String? username,
    String? password,
    String? id,
    String? clientId,
  }) {
    final cid = clientId ?? const Uuid().v4();
    return MqttConnection(
      id: id,
      name: name,
      host: host,
      port: port,
      useTls: useTls,
      protocol: protocol,
      wsPath: wsPath,
      clientId: cid,
      iconCodePoint: icon.codePoint,
      iconFontFamily: icon.fontFamily,
      iconFontPackage: icon.fontPackage,
      imagePath: null,
      username: username,
      password: password,
    );
    }

  /// Convenience constructor for "image mode"
  factory MqttConnection.withImage({
    required String name,
    required String host,
    required int port,
    required bool useTls,
    required String protocol,
    required String wsPath,
    required String imagePath,
    String? username,
    String? password,
    String? id,
    String? clientId,
  }) {
    final cid = clientId ?? const Uuid().v4();
    return MqttConnection(
      id: id,
      name: name,
      host: host,
      port: port,
      useTls: useTls,
      protocol: protocol,
      wsPath: wsPath,
      clientId: cid,
      iconCodePoint: null,
      iconFontFamily: null,
      iconFontPackage: null,
      imagePath: imagePath,
      username: username,
      password: password,
    );
  }

  IconData get iconOrDefault {
    if (iconCodePoint == null) return Icons.cloud;
    return IconData(
      iconCodePoint!,
      fontFamily: iconFontFamily,
      fontPackage: iconFontPackage,
      matchTextDirection: false,
    );
  }

  MqttConnection copyWith({
    String? name,
    String? host,
    int? port,
    bool? useTls,
    String? protocol,
    String? wsPath,
    int? iconCodePoint,
    String? iconFontFamily,
    String? iconFontPackage,
    String? imagePath,
    String? username,
    String? password,
  }) {
    return MqttConnection(
      id: id,
      clientId: clientId,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      useTls: useTls ?? this.useTls,
      protocol: protocol ?? this.protocol,
      wsPath: wsPath ?? this.wsPath,
      iconCodePoint: iconCodePoint ?? this.iconCodePoint,
      iconFontFamily: iconFontFamily ?? this.iconFontFamily,
      iconFontPackage: iconFontPackage ?? this.iconFontPackage,
      imagePath: imagePath ?? this.imagePath,
      username: username ?? this.username,
      password: password ?? this.password,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'clientId': clientId,
        'name': name,
        'host': host,
        'port': port,
        'useTls': useTls,
        'protocol': protocol,
        'wsPath': wsPath,
        'iconCodePoint': iconCodePoint,
        'iconFontFamily': iconFontFamily,
        'iconFontPackage': iconFontPackage,
        'imagePath': imagePath,
        'username': username,
      };

  factory MqttConnection.fromJson(Map<String, dynamic> json) {
    return MqttConnection(
      id: json['id'] as String,
      clientId: json['clientId'] as String,
      name: json['name'] as String,
      host: json['host'] as String,
      port: (json['port'] as num).toInt(),
      useTls: json['useTls'] as bool,
      protocol: json['protocol'] as String,
      wsPath: (json['wsPath'] as String?) ?? '',
      iconCodePoint: (json['iconCodePoint'] as num?)?.toInt(),
      iconFontFamily: json['iconFontFamily'] as String?,
      iconFontPackage: json['iconFontPackage'] as String?,
      imagePath: json['imagePath'] as String?,
      username: json['username'] as String?,
      password: null, // stored in secure storage
    );
  }
}
