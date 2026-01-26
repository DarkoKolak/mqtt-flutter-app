import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:provider/provider.dart';

import '../providers/connection_provider.dart';

enum MsgDir { incoming, outgoing }

class MessagesScreen extends StatefulWidget {
  final String topic;
  const MessagesScreen({super.key, required this.topic});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  final TextEditingController _controller = TextEditingController();
  final List<_UiMsg> _messages = [];

  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? _sub;

  // publish options
  int _pubQos = 0;
  bool _retain = false;

  // view option
  bool _prettyJson = true;

  @override
  void initState() {
    super.initState();

    final mqtt = context.read<ConnectionProvider>().mqttService;

    _sub = mqtt.messages?.listen((events) {
      for (final m in events) {
        if (m.topic != widget.topic) continue;

        final pub = m.payload as MqttPublishMessage;
        final payload = MqttPublishPayload.bytesToStringAsString(pub.payload.message);

        final qos = pub.header?.qos ?? MqttQos.atMostOnce;
        final retain = pub.header?.retain ?? false;

        if (!mounted) return;
        setState(() {
          _messages.add(_UiMsg(
            dir: MsgDir.incoming,
            text: payload,
            ts: DateTime.now(),
            qos: qos,
            retain: retain,
          ));
        });
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    final provider = context.read<ConnectionProvider>();
    if (!provider.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not connected')),
      );
      return;
    }

    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final qos = _toQos(_pubQos);

    provider.mqttService.publish(
      widget.topic,
      text,
      qos: qos,
      retain: _retain,
    );

    setState(() {
      _messages.add(_UiMsg(
        dir: MsgDir.outgoing,
        text: text,
        ts: DateTime.now(),
        qos: qos,
        retain: _retain,
      ));
      _controller.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ConnectionProvider>();

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: Text(widget.topic),
        actions: [
          IconButton(
            icon: Icon(_prettyJson ? Icons.data_object : Icons.text_fields),
            tooltip: _prettyJson ? 'Pretty JSON ON' : 'Pretty JSON OFF',
            onPressed: () => setState(() => _prettyJson = !_prettyJson),
          ),
          if (provider.isConnected)
            IconButton(
              icon: const Icon(Icons.link_off),
              tooltip: 'Disconnect',
              onPressed: () {
                provider.disconnect();
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Disconnected')),
                );
              },
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              color: provider.isConnected
                  ? Colors.green.withOpacity(0.2)
                  : Colors.red.withOpacity(0.2),
              child: Text(
                provider.isConnected
                    ? 'Connected: ${provider.activeConnection?.name ?? 'Unknown'}'
                    : 'Not connected',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Divider(height: 1),

            Expanded(
              child: ListView.builder(
                reverse: true,
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final msg = _messages[_messages.length - 1 - index];
                  return _MessageBubble(
                    msg: msg,
                    prettyJson: _prettyJson,
                  );
                },
              ),
            ),

            // Publish options row
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                child: Row(
                  children: [
                    DropdownButton<int>(
                      value: _pubQos,
                      items: const [
                        DropdownMenuItem(value: 0, child: Text('QoS 0')),
                        DropdownMenuItem(value: 1, child: Text('QoS 1')),
                        DropdownMenuItem(value: 2, child: Text('QoS 2')),
                      ],
                      onChanged: provider.isConnected ? (v) => setState(() => _pubQos = v ?? 0) : null,
                    ),
                    const SizedBox(width: 12),
                    Row(
                      children: [
                        const Text('Retain'),
                        Switch(
                          value: _retain,
                          onChanged: provider.isConnected ? (v) => setState(() => _retain = v) : null,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Composer
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        enabled: provider.isConnected,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) {
                          if (provider.isConnected) _send();
                        },
                        decoration: InputDecoration(
                          hintText: provider.isConnected
                              ? 'Type a message...'
                              : 'Connect first to send messages',
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.send),
                      onPressed: provider.isConnected ? _send : null,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
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

class _UiMsg {
  final MsgDir dir;
  final String text;
  final DateTime ts;
  final MqttQos qos;
  final bool retain;

  _UiMsg({
    required this.dir,
    required this.text,
    required this.ts,
    required this.qos,
    required this.retain,
  });
}

class _MessageBubble extends StatelessWidget {
  final _UiMsg msg;
  final bool prettyJson;

  const _MessageBubble({required this.msg, required this.prettyJson});

  @override
  Widget build(BuildContext context) {
    final isOut = msg.dir == MsgDir.outgoing;
    final align = isOut ? CrossAxisAlignment.end : CrossAxisAlignment.start;

    final meta = 'QoS ${_qosInt(msg.qos)}${msg.retain ? ' • retain' : ''} • ${_ts(msg.ts)}';

    final displayText = prettyJson ? _pretty(msg.text) : msg.text;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Column(
        crossAxisAlignment: align,
        children: [
          Container(
            constraints: const BoxConstraints(maxWidth: 320),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isOut ? Colors.blue.withOpacity(0.25) : Colors.grey.withOpacity(0.25),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isOut ? Colors.blue.withOpacity(0.35) : Colors.grey.withOpacity(0.35),
              ),
            ),
            child: Text(displayText),
          ),
          const SizedBox(height: 4),
          Text(
            meta,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
          ),
        ],
      ),
    );
  }

  static int _qosInt(MqttQos qos) {
    if (qos == MqttQos.atLeastOnce) return 1;
    if (qos == MqttQos.exactlyOnce) return 2;
    return 0;
  }

  static String _ts(DateTime d) {
    final s = d.toLocal().toString().split('.').first;
    return s;
  }

  static String _pretty(String raw) {
    final t = raw.trim();
    if (!(t.startsWith('{') || t.startsWith('['))) return raw;
    try {
      final obj = json.decode(t);
      const encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(obj);
    } catch (_) {
      return raw;
    }
  }
}
