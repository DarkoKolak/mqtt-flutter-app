import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:provider/provider.dart';

import '../models/dashboard_widget.dart';
import '../models/payload_format.dart';
import '../providers/connection_provider.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? _sub;

  /// Temporary UI value only while user drags slider
  final Map<String, double> _sliderUiValue = {};

  /// True only while slider is being dragged
  final Map<String, bool> _isDraggingSlider = {};

  /// For bridge: throttle republish
  final Map<String, DateTime> _lastBridgePublishAt = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    _sub?.cancel();

    final provider = context.read<ConnectionProvider>();
    if (!provider.isConnected) return;

    // Re-subscribe to all known topics when entering dashboard
    provider.refreshAllKnownSubscriptions();

    // Listen only for bridge automation logic.
    // The actual state cache is handled globally in ConnectionProvider.
    _sub = provider.mqttService.messages?.listen((events) {
      for (final msg in events) {
        final topic = msg.topic;
        final pub = msg.payload as MqttPublishMessage;
        final bytes = Uint8List.fromList(pub.payload.message);
        final payloadText = _bytesToDisplay(bytes);

        _handleBridgeIfNeeded(topic, payloadText);
      }
    });

    provider.ensureDashboardSubscriptions();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _handleBridgeIfNeeded(String incomingTopic, String payloadText) {
    final provider = context.read<ConnectionProvider>();
    final tiles = provider.activeDashboardWidgets;

    for (final w in tiles.where((t) => t.type == DashboardWidgetType.bridge)) {
      if (w.bridgeInputTopic.trim() != incomingTopic) continue;
      if (!provider.isConnected) continue;
      if (w.bridgeOutputTopic.trim().isEmpty) continue;

      final now = DateTime.now();
      final lastAt = _lastBridgePublishAt[w.id];
      if (lastAt != null && now.difference(lastAt).inMilliseconds < 200) {
        continue;
      }

      final b = _toBool(payloadText);
      final outPayload = b ? w.bridgeTruePayload : w.bridgeFalsePayload;

      try {
        provider.mqttService.publishPayload(
          w.bridgeOutputTopic.trim(),
          outPayload,
          qos: _toQos(w.pubQos),
          retain: w.retain,
          format: PayloadFormat.text,
        );
        _lastBridgePublishAt[w.id] = now;
      } catch (_) {
        // ignore bridge publish errors
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ConnectionProvider>();

    if (!provider.isLoaded) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!provider.isConnected) {
      return const Center(
        child: Text(
          'Connect to a broker first.\nGo to Connections and tap a connection.',
          textAlign: TextAlign.center,
        ),
      );
    }

    final widgets = provider.activeDashboardWidgets;

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: widgets.isEmpty
            ? _EmptyDashboard(onAdd: () => _openAddDialog(context))
            : GridView.builder(
                itemCount: widgets.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 1,
                ),
                itemBuilder: (context, index) {
                  final w = widgets[index];

                  switch (w.type) {
                    case DashboardWidgetType.toggle:
                      return _ToggleTile(
                        config: w,
                        stateText: provider.lastPayload(w.stateTopic.trim()),
                        stateTs: provider.lastPayloadTs(w.stateTopic.trim()),
                        onTap: () => _toggle(w),
                        onLongPress: () => _editOrDelete(context, w),
                      );

                    case DashboardWidgetType.slider:
                      return _SliderTile(
                        config: w,
                        stateText: provider.lastPayload(w.stateTopic.trim()),
                        stateTs: provider.lastPayloadTs(w.stateTopic.trim()),
                        uiValue: _currentSliderValue(w, provider),
                        onChanged: (v) {
                          setState(() {
                            _isDraggingSlider[w.id] = true;
                            _sliderUiValue[w.id] = v;
                          });
                        },
                        onChangeEnd: (v) {
                          setState(() {
                            _sliderUiValue[w.id] = v;
                            _isDraggingSlider[w.id] = false;
                          });
                          _publishSlider(w, v);
                        },
                        onLongPress: () => _editOrDelete(context, w),
                      );

                    case DashboardWidgetType.bridge:
                      return _BridgeTile(
                        config: w,
                        lastIn: provider.lastPayload(w.bridgeInputTopic.trim()),
                        lastInTs: provider.lastPayloadTs(w.bridgeInputTopic.trim()),
                        onLongPress: () => _editOrDelete(context, w),
                      );
                  }
                },
              ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openAddDialog(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  double _currentSliderValue(
    DashboardWidgetConfig w,
    ConnectionProvider provider,
  ) {
    final isDragging = _isDraggingSlider[w.id] ?? false;

    // While dragging, use local UI value
    if (isDragging) {
      return (_sliderUiValue[w.id] ?? w.sliderMin)
          .clamp(w.sliderMin, w.sliderMax)
          .toDouble();
    }

    // Otherwise behave like the button:
    // always follow the latest MQTT state value
    final state = provider.lastPayload(w.stateTopic.trim());
    if (state == null) {
      return (_sliderUiValue[w.id] ?? w.sliderMin)
          .clamp(w.sliderMin, w.sliderMax)
          .toDouble();
    }

    final parsed = double.tryParse(state.trim());
    if (parsed == null) {
      return (_sliderUiValue[w.id] ?? w.sliderMin)
          .clamp(w.sliderMin, w.sliderMax)
          .toDouble();
    }

    final value = parsed.clamp(w.sliderMin, w.sliderMax).toDouble();
    _sliderUiValue[w.id] = value;
    return value;
  }

  void _toggle(DashboardWidgetConfig w) {
    final provider = context.read<ConnectionProvider>();

    final stateText = provider.lastPayload(w.stateTopic.trim()) ?? '';
    final current = _toBool(stateText);

    final payload = current ? w.toggleOffPayload : w.toggleOnPayload;

    try {
      provider.mqttService.publishPayload(
        w.commandTopic.trim(),
        payload,
        qos: _toQos(w.pubQos),
        retain: w.retain,
        format: PayloadFormat.text,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Published to ${w.commandTopic}: $payload')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Publish failed: $e')),
      );
    }
  }

  void _publishSlider(DashboardWidgetConfig w, double value) {
    final provider = context.read<ConnectionProvider>();
    final rounded = _roundToStep(value, w.sliderStep);

    try {
      provider.mqttService.publishPayload(
        w.commandTopic.trim(),
        rounded.toStringAsFixed(_decimalsForStep(w.sliderStep)),
        qos: _toQos(w.pubQos),
        retain: w.retain,
        format: PayloadFormat.text,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Published to ${w.commandTopic}: $rounded')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Publish failed: $e')),
      );
    }
  }

  double _roundToStep(double v, double step) {
    if (step <= 0) return v;
    final n = (v / step).round();
    return n * step;
  }

  int _decimalsForStep(double step) {
    final s = step.toString();
    if (!s.contains('.')) return 0;
    return s.split('.').last.length;
  }

  Future<void> _editOrDelete(BuildContext context, DashboardWidgetConfig w) async {
    final provider = context.read<ConnectionProvider>();

    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Edit'),
              onTap: () => Navigator.pop(ctx, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete'),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );

    if (choice == 'delete') {
      await provider.deleteDashboardWidget(w.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Deleted: ${w.title}')),
      );
    }

    if (choice == 'edit') {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Edit not implemented yet. Delete & recreate for now.'),
        ),
      );
    }
  }

  Future<void> _openAddDialog(BuildContext context) async {
    final provider = context.read<ConnectionProvider>();

    final created = await showDialog<DashboardWidgetConfig>(
      context: context,
      builder: (ctx) => _AddDashboardWidgetDialog(),
    );

    if (created == null) return;

    await provider.addDashboardWidget(created);
    provider.ensureDashboardSubscriptions();

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Added dashboard tile: ${created.title}')),
    );
  }

  static bool _toBool(String s) {
    final t = s.trim().toLowerCase();
    return t == 'true' || t == '1' || t == 'on' || t == 'yes';
  }

  static MqttQos _toQos(int v) {
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

// ---------------- UI widgets ----------------

class _EmptyDashboard extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyDashboard({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.dashboard_customize, size: 64),
          const SizedBox(height: 10),
          const Text(
            'No dashboard tiles yet.\nTap + to add a button/slider.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('Add tile'),
          ),
        ],
      ),
    );
  }
}

class _TileCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const _TileCard({
    required this.child,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      onLongPress: onLongPress,
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: child,
        ),
      ),
    );
  }
}

class _ToggleTile extends StatelessWidget {
  final DashboardWidgetConfig config;
  final String? stateText;
  final DateTime? stateTs;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _ToggleTile({
    required this.config,
    required this.stateText,
    required this.stateTs,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final isOn = stateText == null ? false : _toBool(stateText!);

    return _TileCard(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(config.icon, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  config.title,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            isOn ? 'ON' : 'OFF',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: isOn ? Colors.green : Colors.grey,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'State topic:\n${config.stateTopic}',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
          ),
          const SizedBox(height: 4),
          Text(
            stateTs == null
                ? 'No state received yet'
                : 'Last update: ${stateTs!.toLocal().toString().split(".").first}',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
          ),
        ],
      ),
    );
  }

  static bool _toBool(String s) {
    final t = s.trim().toLowerCase();
    return t == 'true' || t == '1' || t == 'on' || t == 'yes';
  }
}

class _SliderTile extends StatelessWidget {
  final DashboardWidgetConfig config;
  final String? stateText;
  final DateTime? stateTs;
  final double uiValue;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;
  final VoidCallback onLongPress;

  const _SliderTile({
    required this.config,
    required this.stateText,
    required this.stateTs,
    required this.uiValue,
    required this.onChanged,
    required this.onChangeEnd,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final display = uiValue.toStringAsFixed(_decimalsForStep(config.sliderStep));

    return _TileCard(
      onTap: null,
      onLongPress: onLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(config.icon, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  config.title,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            display,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
          ),
          Slider(
            value: uiValue.clamp(config.sliderMin, config.sliderMax),
            min: config.sliderMin,
            max: config.sliderMax,
            divisions: _divisions(config.sliderMin, config.sliderMax, config.sliderStep),
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
          Text(
            'State: ${stateText ?? "(none)"}',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            stateTs == null
                ? 'No state received yet'
                : 'Last update: ${stateTs!.toLocal().toString().split(".").first}',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
          ),
        ],
      ),
    );
  }

  static int _divisions(double min, double max, double step) {
    if (step <= 0) return 100;
    final d = ((max - min) / step).round();
    return d <= 0 ? 100 : d;
  }

  static int _decimalsForStep(double step) {
    final s = step.toString();
    if (!s.contains('.')) return 0;
    return s.split('.').last.length;
  }
}

class _BridgeTile extends StatelessWidget {
  final DashboardWidgetConfig config;
  final String? lastIn;
  final DateTime? lastInTs;
  final VoidCallback onLongPress;

  const _BridgeTile({
    required this.config,
    required this.lastIn,
    required this.lastInTs,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return _TileCard(
      onTap: null,
      onLongPress: onLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(config.icon, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  config.title,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'IN:\n${config.bridgeInputTopic}',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
          ),
          const SizedBox(height: 6),
          Text(
            'OUT:\n${config.bridgeOutputTopic}',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
          ),
          const Spacer(),
          Text(
            'Last IN: ${lastIn ?? "(none)"}',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade300),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            lastInTs == null
                ? 'No input received yet'
                : 'Last update: ${lastInTs!.toLocal().toString().split(".").first}',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
          ),
        ],
      ),
    );
  }
}

class _AddDashboardWidgetDialog extends StatefulWidget {
  @override
  State<_AddDashboardWidgetDialog> createState() => _AddDashboardWidgetDialogState();
}

class _AddDashboardWidgetDialogState extends State<_AddDashboardWidgetDialog> {
  DashboardWidgetType _type = DashboardWidgetType.toggle;

  final _title = TextEditingController();
  final _commandTopic = TextEditingController();
  final _stateTopic = TextEditingController();

  final _bridgeIn = TextEditingController();
  final _bridgeOut = TextEditingController();

  int _subQos = 0;
  int _pubQos = 0;
  bool _retain = false;

  final _onPayload = TextEditingController(text: 'true');
  final _offPayload = TextEditingController(text: 'false');

  final _min = TextEditingController(text: '0');
  final _max = TextEditingController(text: '100');
  final _step = TextEditingController(text: '1');

  final _bridgeTrue = TextEditingController(text: 'true');
  final _bridgeFalse = TextEditingController(text: 'false');

  final List<IconData> _icons = const [
    Icons.power_settings_new,
    Icons.lightbulb,
    Icons.toggle_on,
    Icons.lock,
    Icons.lock_open,
    Icons.sensors,
    Icons.volume_up,
    Icons.ac_unit,
    Icons.water_drop,
    Icons.brightness_6,
    Icons.door_front_door,
    Icons.power,
  ];

  IconData _selectedIcon = Icons.toggle_on;

  @override
  void dispose() {
    _title.dispose();
    _commandTopic.dispose();
    _stateTopic.dispose();
    _bridgeIn.dispose();
    _bridgeOut.dispose();
    _onPayload.dispose();
    _offPayload.dispose();
    _min.dispose();
    _max.dispose();
    _step.dispose();
    _bridgeTrue.dispose();
    _bridgeFalse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Dashboard Tile'),
      content: SingleChildScrollView(
        child: Column(
          children: [
            DropdownButtonFormField<DashboardWidgetType>(
              value: _type,
              decoration: const InputDecoration(
                labelText: 'Type',
                border: OutlineInputBorder(),
              ),
              items: DashboardWidgetType.values
                  .map((t) => DropdownMenuItem(value: t, child: Text(t.label)))
                  .toList(),
              onChanged: (v) => setState(() => _type = v ?? DashboardWidgetType.toggle),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _title,
              decoration: const InputDecoration(
                labelText: 'Title',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<IconData>(
              value: _selectedIcon,
              decoration: const InputDecoration(
                labelText: 'Icon',
                border: OutlineInputBorder(),
              ),
              items: _icons
                  .map(
                    (i) => DropdownMenuItem(
                      value: i,
                      child: Row(
                        children: [
                          Icon(i),
                          const SizedBox(width: 10),
                          Text(i.codePoint.toRadixString(16).toUpperCase()),
                        ],
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _selectedIcon = v ?? Icons.toggle_on),
            ),
            const SizedBox(height: 10),
            _qosRow(),
            const SizedBox(height: 10),
            if (_type == DashboardWidgetType.bridge) ...[
              TextField(
                controller: _bridgeIn,
                decoration: const InputDecoration(
                  labelText: 'Input topic (subscribe)',
                  hintText: 'e.g. home/motion/state',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _bridgeOut,
                decoration: const InputDecoration(
                  labelText: 'Output topic (publish)',
                  hintText: 'e.g. home/light/set',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _bridgeTrue,
                decoration: const InputDecoration(
                  labelText: 'If input is TRUE → publish',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _bridgeFalse,
                decoration: const InputDecoration(
                  labelText: 'If input is FALSE → publish',
                  border: OutlineInputBorder(),
                ),
              ),
            ] else ...[
              TextField(
                controller: _commandTopic,
                decoration: const InputDecoration(
                  labelText: 'Command topic (publish)',
                  hintText: 'e.g. home/light/set',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _stateTopic,
                decoration: const InputDecoration(
                  labelText: 'State topic (subscribe)',
                  hintText: 'e.g. home/light/state',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              if (_type == DashboardWidgetType.toggle) ...[
                TextField(
                  controller: _onPayload,
                  decoration: const InputDecoration(
                    labelText: 'ON payload',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _offPayload,
                  decoration: const InputDecoration(
                    labelText: 'OFF payload',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
              if (_type == DashboardWidgetType.slider) ...[
                TextField(
                  controller: _min,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Min',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _max,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Max',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _step,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Step',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ],
            const SizedBox(height: 10),
            SwitchListTile(
              value: _retain,
              onChanged: (v) => setState(() => _retain = v),
              title: const Text('Retain'),
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }

  Widget _qosRow() {
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<int>(
            value: _subQos,
            decoration: const InputDecoration(
              labelText: 'Sub QoS',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 0, child: Text('0')),
              DropdownMenuItem(value: 1, child: Text('1')),
              DropdownMenuItem(value: 2, child: Text('2')),
            ],
            onChanged: (v) => setState(() => _subQos = v ?? 0),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: DropdownButtonFormField<int>(
            value: _pubQos,
            decoration: const InputDecoration(
              labelText: 'Pub QoS',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 0, child: Text('0')),
              DropdownMenuItem(value: 1, child: Text('1')),
              DropdownMenuItem(value: 2, child: Text('2')),
            ],
            onChanged: (v) => setState(() => _pubQos = v ?? 0),
          ),
        ),
      ],
    );
  }

  void _save() {
    final title = _title.text.trim();
    if (title.isEmpty) return;

    if (_type == DashboardWidgetType.bridge) {
      final inTopic = _bridgeIn.text.trim();
      final outTopic = _bridgeOut.text.trim();
      if (inTopic.isEmpty || outTopic.isEmpty) return;

      Navigator.pop(
        context,
        DashboardWidgetConfig(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          type: DashboardWidgetType.bridge,
          title: title,
          iconCodePoint: _selectedIcon.codePoint,
          iconFontFamily: _selectedIcon.fontFamily,
          iconFontPackage: _selectedIcon.fontPackage,
          commandTopic: '',
          stateTopic: '',
          subQos: _subQos,
          pubQos: _pubQos,
          retain: _retain,
          toggleOnPayload: _onPayload.text,
          toggleOffPayload: _offPayload.text,
          sliderMin: double.tryParse(_min.text) ?? 0,
          sliderMax: double.tryParse(_max.text) ?? 100,
          sliderStep: double.tryParse(_step.text) ?? 1,
          bridgeInputTopic: inTopic,
          bridgeOutputTopic: outTopic,
          bridgeTruePayload: _bridgeTrue.text,
          bridgeFalsePayload: _bridgeFalse.text,
        ),
      );
      return;
    }

    final commandTopic = _commandTopic.text.trim();
    final stateTopic = _stateTopic.text.trim();
    if (commandTopic.isEmpty || stateTopic.isEmpty) return;

    final min = double.tryParse(_min.text) ?? 0;
    final max = double.tryParse(_max.text) ?? 100;
    final step = double.tryParse(_step.text) ?? 1;

    Navigator.pop(
      context,
      DashboardWidgetConfig(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        type: _type,
        title: title,
        iconCodePoint: _selectedIcon.codePoint,
        iconFontFamily: _selectedIcon.fontFamily,
        iconFontPackage: _selectedIcon.fontPackage,
        commandTopic: commandTopic,
        stateTopic: stateTopic,
        subQos: _subQos,
        pubQos: _pubQos,
        retain: _retain,
        toggleOnPayload: _onPayload.text,
        toggleOffPayload: _offPayload.text,
        sliderMin: min,
        sliderMax: max,
        sliderStep: step,
        bridgeInputTopic: _bridgeIn.text.trim(),
        bridgeOutputTopic: _bridgeOut.text.trim(),
        bridgeTruePayload: _bridgeTrue.text,
        bridgeFalsePayload: _bridgeFalse.text,
      ),
    );
  }
}