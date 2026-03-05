import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:provider/provider.dart';

import '../models/payload_format.dart';
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

  int _pubQos = 0;
  bool _retain = false;

  PayloadFormat _format = PayloadFormat.text;

  bool _prettyJson = true;

  @override
  void initState() {
    super.initState();

    final mqtt = context.read<ConnectionProvider>().mqttService;

    _sub = mqtt.messages?.listen((events) {
      for (final m in events) {
        if (m.topic != widget.topic) continue;

        final pub = m.payload as MqttPublishMessage;

        final Uint8List bytes = Uint8List.fromList(pub.payload.message);
        final payloadText = _bytesToDisplay(bytes);

        final qos = pub.header?.qos ?? MqttQos.atMostOnce;
        final retain = pub.header?.retain ?? false;

        if (!mounted) return;
        setState(() {
          _messages.add(_UiMsg(
            dir: MsgDir.incoming,
            text: payloadText,
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

    try {
      provider.mqttService.publishPayload(
        widget.topic,
        text,
        qos: qos,
        retain: _retain,
        format: _format,
      );

      setState(() {
        _messages.add(_UiMsg(
          dir: MsgDir.outgoing,
          text: _outgoingPreview(text, _format),
          ts: DateTime.now(),
          qos: qos,
          retain: _retain,
        ));
        _controller.clear();
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Publish failed: $e')),
      );
    }
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

            // Row 1: QoS + Retain + Format
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 6,
                  children: [
                    DropdownButton<int>(
                      value: _pubQos,
                      items: const [
                        DropdownMenuItem(value: 0, child: Text('QoS 0')),
                        DropdownMenuItem(value: 1, child: Text('QoS 1')),
                        DropdownMenuItem(value: 2, child: Text('QoS 2')),
                      ],
                      onChanged:
                          provider.isConnected ? (v) => setState(() => _pubQos = v ?? 0) : null,
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Retain'),
                        Switch(
                          value: _retain,
                          onChanged: provider.isConnected ? (v) => setState(() => _retain = v) : null,
                        ),
                      ],
                    ),
                    DropdownButton<PayloadFormat>(
                      value: _format,
                      items: PayloadFormat.values
                          .map(
                            (f) => DropdownMenuItem(
                              value: f,
                              child: Text(f.label),
                            ),
                          )
                          .toList(),
                      onChanged: provider.isConnected
                          ? (v) {
                              if (v == null) return;
                              setState(() => _format = v);
                            }
                          : null,
                    ),
                  ],
                ),
              ),
            ),

            // Row 2: input + send
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
                              ? _hintForFormat(_format)
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

  static String _hintForFormat(PayloadFormat f) {
    switch (f) {
      case PayloadFormat.text:
        return 'Type a message...';
      case PayloadFormat.json:
        return 'Paste JSON (e.g. {"a":1})';
      case PayloadFormat.hex:
        return 'HEX bytes (e.g. DE AD BE EF)';
      case PayloadFormat.base64:
        return 'Base64 (e.g. 3q2+7w==)';
    }
  }

  static String _outgoingPreview(String input, PayloadFormat f) {
    switch (f) {
      case PayloadFormat.text:
        return input;
      case PayloadFormat.json:
        return input; // pretty toggle will format it visually
      case PayloadFormat.hex:
        return '[HEX] $input';
      case PayloadFormat.base64:
        return '[Base64] $input';
    }
  }

  static String _bytesToDisplay(Uint8List bytes) {
    // try UTF-8 first
    try {
      return utf8.decode(bytes);
    } catch (_) {
      // fallback to hex
      final b = StringBuffer();
      for (final v in bytes) {
        b.write(v.toRadixString(16).padLeft(2, '0'));
      }
      return '[BIN ${bytes.length} bytes] ${b.toString().toUpperCase()}';
    }
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
    return d.toLocal().toString().split('.').first;
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