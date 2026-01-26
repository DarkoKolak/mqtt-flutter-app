import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:provider/provider.dart';

import '../providers/connection_provider.dart';
import 'messages_screen.dart';

class TopicsScreen extends StatefulWidget {
  const TopicsScreen({super.key});

  @override
  State<TopicsScreen> createState() => _TopicsScreenState();
}

class _TopicsScreenState extends State<TopicsScreen> {
  final _topicController = TextEditingController();
  int _newQos = 0;

  @override
  void dispose() {
    _topicController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ConnectionProvider>();

    if (!provider.isLoaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final subs = provider.activeSubs;
    final conn = provider.activeConnection;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Topics'),
        actions: [
          if (provider.isConnected)
            IconButton(
              icon: const Icon(Icons.link_off),
              tooltip: 'Disconnect',
              onPressed: () {
                provider.disconnect();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Disconnected')),
                );
              },
            ),
        ],
      ),
      body: Column(
        children: [
          _ConnectionBanner(
            isConnected: provider.isConnected,
            name: conn?.name ?? 'No connection',
            details: conn == null ? '' : '${conn.host}:${conn.port}',
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: provider.isConnected
                  ? Column(
                      children: [
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                TextField(
                                  controller: _topicController,
                                  decoration: const InputDecoration(
                                    labelText: 'New topic',
                                    hintText: 'e.g. home/lamp/1/set',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    SizedBox(
                                      width: 120,
                                      child: DropdownButtonFormField<int>(
                                        value: _newQos,
                                        isExpanded: true,
                                        decoration: const InputDecoration(
                                          labelText: 'QoS',
                                          border: OutlineInputBorder(),
                                        ),
                                        items: const [
                                          DropdownMenuItem(value: 0, child: Text('0')),
                                          DropdownMenuItem(value: 1, child: Text('1')),
                                          DropdownMenuItem(value: 2, child: Text('2')),
                                        ],
                                        onChanged: (v) => setState(() => _newQos = v ?? 0),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: SizedBox(
                                        height: 56,
                                        child: ElevatedButton.icon(
                                          icon: const Icon(Icons.add),
                                          label: const Text('Subscribe'),
                                          onPressed: () async {
                                            final topic = _topicController.text.trim();
                                            if (topic.isEmpty) return;

                                            try {
                                              provider.mqttService.subscribe(topic, _toQos(_newQos));
                                              await provider.addOrUpdateSubForActive(topic, _newQos);

                                              _topicController.clear();
                                              if (!context.mounted) return;

                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(content: Text('Subscribed: $topic (QoS $_newQos)')),
                                              );
                                            } catch (e) {
                                              if (!context.mounted) return;
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(content: Text('Subscribe failed: $e')),
                                              );
                                            }
                                          },
                                        ),
                                      ),
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 8),
                                Text(
                                  _qosHint(_newQos),
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: Colors.white70,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        Expanded(
                          child: subs.isEmpty
                              ? const Center(child: Text('No topics saved for this connection.'))
                              : ListView(
                                  children: subs.entries.map((e) {
                                    final topic = e.key;
                                    final qos = e.value;

                                    return Card(
                                      child: ListTile(
                                        title: Text(topic),
                                        subtitle: Text('QoS $qos'),
                                        onTap: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => MessagesScreen(topic: topic),
                                            ),
                                          );
                                        },
                                        trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            DropdownButton<int>(
                                              value: qos,
                                              items: const [
                                                DropdownMenuItem(value: 0, child: Text('0')),
                                                DropdownMenuItem(value: 1, child: Text('1')),
                                                DropdownMenuItem(value: 2, child: Text('2')),
                                              ],
                                              onChanged: (v) async {
                                                final newQ = v ?? 0;

                                                try {
                                                  provider.mqttService.subscribe(topic, _toQos(newQ));
                                                  await provider.addOrUpdateSubForActive(topic, newQ);
                                                } catch (e) {
                                                  if (!context.mounted) return;
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    SnackBar(content: Text('Failed to update QoS: $e')),
                                                  );
                                                }
                                              },
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.delete_outline),
                                              tooltip: 'Remove topic',
                                              onPressed: () async {
                                                await provider.removeSubForActive(topic, alsoUnsubscribe: false);
                                                if (!context.mounted) return;
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  SnackBar(content: Text('Removed topic: $topic')),
                                                );
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                        ),
                      ],
                    )
                  : const Center(
                      child: Text(
                        'Connect to a broker first.\nGo to Connections and tap a connection.',
                        textAlign: TextAlign.center,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  String _qosHint(int qos) {
    switch (qos) {
      case 1:
        return 'QoS 1: delivered at least once (may duplicate).';
      case 2:
        return 'QoS 2: delivered exactly once (slowest, safest).';
      default:
        return 'QoS 0: delivered at most once (fastest, may drop).';
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

class _ConnectionBanner extends StatelessWidget {
  final bool isConnected;
  final String name;
  final String details;

  const _ConnectionBanner({
    required this.isConnected,
    required this.name,
    required this.details,
  });

  @override
  Widget build(BuildContext context) {
    final color = isConnected ? Colors.green : Colors.red;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        border: Border(
          bottom: BorderSide(color: color.withOpacity(0.25)),
        ),
      ),
      child: Row(
        children: [
          Icon(isConnected ? Icons.check_circle : Icons.cancel, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isConnected ? 'Connected' : 'Not connected',
                  style: TextStyle(fontWeight: FontWeight.bold, color: color),
                ),
                const SizedBox(height: 2),
                Text(
                  details.isEmpty ? name : '$name • $details',
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
