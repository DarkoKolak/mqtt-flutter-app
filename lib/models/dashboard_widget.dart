import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

enum DashboardWidgetType {
  toggle,
  slider,
  bridge,
}

extension DashboardWidgetTypeLabel on DashboardWidgetType {
  String get label {
    switch (this) {
      case DashboardWidgetType.toggle:
        return 'Toggle Button';
      case DashboardWidgetType.slider:
        return 'Slider';
      case DashboardWidgetType.bridge:
        return 'Bridge (React & Publish)';
    }
  }
}

/// Configurable dashboard tile.
/// - toggle: publish on/off to commandTopic, read state from stateTopic
/// - slider: publish numeric value to commandTopic, read state from stateTopic
/// - bridge: read from inputTopic, transform, publish to outputTopic (no direct UI control)
class DashboardWidgetConfig {
  final String id;
  final DashboardWidgetType type;

  final String title;

  /// UI Icon (stored as IconData parts so it can be serialized)
  final int iconCodePoint;
  final String? iconFontFamily;
  final String? iconFontPackage;

  /// For toggle/slider
  final String commandTopic; // publish here
  final String stateTopic;   // subscribe here for state

  /// QoS used for subscribing to state/input topics
  final int subQos;

  /// QoS used when publishing (command/bridge output)
  final int pubQos;

  /// Publish retain flag (often false for commands)
  final bool retain;

  /// Toggle customization
  final String toggleOnPayload;
  final String toggleOffPayload;

  /// Slider customization
  final double sliderMin;
  final double sliderMax;
  final double sliderStep;

  /// Bridge config
  final String bridgeInputTopic;
  final String bridgeOutputTopic;
  final String bridgeTruePayload;
  final String bridgeFalsePayload;

  DashboardWidgetConfig({
    String? id,
    required this.type,
    required this.title,
    required this.iconCodePoint,
    required this.iconFontFamily,
    required this.iconFontPackage,
    required this.commandTopic,
    required this.stateTopic,
    required this.subQos,
    required this.pubQos,
    required this.retain,
    required this.toggleOnPayload,
    required this.toggleOffPayload,
    required this.sliderMin,
    required this.sliderMax,
    required this.sliderStep,
    required this.bridgeInputTopic,
    required this.bridgeOutputTopic,
    required this.bridgeTruePayload,
    required this.bridgeFalsePayload,
  }) : id = id ?? const Uuid().v4();

  IconData get icon => IconData(
        iconCodePoint,
        fontFamily: iconFontFamily,
        fontPackage: iconFontPackage,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'title': title,
        'iconCodePoint': iconCodePoint,
        'iconFontFamily': iconFontFamily,
        'iconFontPackage': iconFontPackage,
        'commandTopic': commandTopic,
        'stateTopic': stateTopic,
        'subQos': subQos,
        'pubQos': pubQos,
        'retain': retain,
        'toggleOnPayload': toggleOnPayload,
        'toggleOffPayload': toggleOffPayload,
        'sliderMin': sliderMin,
        'sliderMax': sliderMax,
        'sliderStep': sliderStep,
        'bridgeInputTopic': bridgeInputTopic,
        'bridgeOutputTopic': bridgeOutputTopic,
        'bridgeTruePayload': bridgeTruePayload,
        'bridgeFalsePayload': bridgeFalsePayload,
      };

  factory DashboardWidgetConfig.fromJson(Map<String, dynamic> json) {
    DashboardWidgetType type = DashboardWidgetType.toggle;
    final typeStr = (json['type'] as String?) ?? 'toggle';
    for (final t in DashboardWidgetType.values) {
      if (t.name == typeStr) {
        type = t;
        break;
      }
    }

    return DashboardWidgetConfig(
      id: json['id'] as String,
      type: type,
      title: (json['title'] as String?) ?? 'Tile',
      iconCodePoint: (json['iconCodePoint'] as num?)?.toInt() ?? Icons.toggle_on.codePoint,
      iconFontFamily: json['iconFontFamily'] as String?,
      iconFontPackage: json['iconFontPackage'] as String?,
      commandTopic: (json['commandTopic'] as String?) ?? '',
      stateTopic: (json['stateTopic'] as String?) ?? '',
      subQos: (json['subQos'] as num?)?.toInt() ?? 0,
      pubQos: (json['pubQos'] as num?)?.toInt() ?? 0,
      retain: (json['retain'] as bool?) ?? false,
      toggleOnPayload: (json['toggleOnPayload'] as String?) ?? 'true',
      toggleOffPayload: (json['toggleOffPayload'] as String?) ?? 'false',
      sliderMin: (json['sliderMin'] as num?)?.toDouble() ?? 0.0,
      sliderMax: (json['sliderMax'] as num?)?.toDouble() ?? 100.0,
      sliderStep: (json['sliderStep'] as num?)?.toDouble() ?? 1.0,
      bridgeInputTopic: (json['bridgeInputTopic'] as String?) ?? '',
      bridgeOutputTopic: (json['bridgeOutputTopic'] as String?) ?? '',
      bridgeTruePayload: (json['bridgeTruePayload'] as String?) ?? 'true',
      bridgeFalsePayload: (json['bridgeFalsePayload'] as String?) ?? 'false',
    );
  }

  DashboardWidgetConfig copyWith({
    DashboardWidgetType? type,
    String? title,
    int? iconCodePoint,
    String? iconFontFamily,
    String? iconFontPackage,
    String? commandTopic,
    String? stateTopic,
    int? subQos,
    int? pubQos,
    bool? retain,
    String? toggleOnPayload,
    String? toggleOffPayload,
    double? sliderMin,
    double? sliderMax,
    double? sliderStep,
    String? bridgeInputTopic,
    String? bridgeOutputTopic,
    String? bridgeTruePayload,
    String? bridgeFalsePayload,
  }) {
    return DashboardWidgetConfig(
      id: id,
      type: type ?? this.type,
      title: title ?? this.title,
      iconCodePoint: iconCodePoint ?? this.iconCodePoint,
      iconFontFamily: iconFontFamily ?? this.iconFontFamily,
      iconFontPackage: iconFontPackage ?? this.iconFontPackage,
      commandTopic: commandTopic ?? this.commandTopic,
      stateTopic: stateTopic ?? this.stateTopic,
      subQos: subQos ?? this.subQos,
      pubQos: pubQos ?? this.pubQos,
      retain: retain ?? this.retain,
      toggleOnPayload: toggleOnPayload ?? this.toggleOnPayload,
      toggleOffPayload: toggleOffPayload ?? this.toggleOffPayload,
      sliderMin: sliderMin ?? this.sliderMin,
      sliderMax: sliderMax ?? this.sliderMax,
      sliderStep: sliderStep ?? this.sliderStep,
      bridgeInputTopic: bridgeInputTopic ?? this.bridgeInputTopic,
      bridgeOutputTopic: bridgeOutputTopic ?? this.bridgeOutputTopic,
      bridgeTruePayload: bridgeTruePayload ?? this.bridgeTruePayload,
      bridgeFalsePayload: bridgeFalsePayload ?? this.bridgeFalsePayload,
    );
  }
}