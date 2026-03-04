import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/connection_provider.dart';
import 'add_connection_screen.dart';

class ConnectionsScreen extends StatelessWidget {
  const ConnectionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ConnectionProvider>();

    if (!provider.isLoaded) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    Future<void> confirmAndDelete() async {
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Connections'),
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
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: GridView.builder(
          itemCount: provider.connections.length + 1,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1,
          ),
          itemBuilder: (context, index) {
            if (index == provider.connections.length) {
              return GestureDetector(
                onTap: provider.isConnecting
                    ? null
                    : () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AddConnectionScreen(),
                          ),
                        );
                      },
                child: Card(
                  color: Colors.grey[800],
                  child: const Center(
                    child: Icon(Icons.add, size: 50, color: Colors.white),
                  ),
                ),
              );
            }

            final conn = provider.connections[index];

            final isActive = provider.activeConnection?.id == conn.id;
            final isConnected =
                isActive && provider.isConnected;
            final isConnecting = isActive && provider.isConnecting;

            void openEdit() {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AddConnectionScreen(existing: conn),
                ),
              );
            }

            Future<void> deleteConn() async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Delete connection?'),
                  content: Text(
                    'Do you really want to delete "${conn.name}"?\n\n'
                    'This will also remove all saved topics for this connection.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton.tonal(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              );

              if (ok != true) return;

              await provider.deleteConnection(conn.id);

              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Deleted: ${conn.name}')),
              );
            }

            return GestureDetector(
              onLongPress: openEdit,
              onTap: provider.isConnecting
                  ? null
                  : () async {
                            if (isConnected) {
                        provider.disconnect();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Disconnected: ${conn.name}')),
                        );
                        return;
                      }
                      final ok = await provider.connect(conn);

                      if (!context.mounted) return;

                      if (ok) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Connected: ${conn.name}')),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Connection failed: ${provider.lastError ?? 'Unknown error'}',
                            ),
                          ),
                        );
                      }
                    },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isConnected ? Colors.green : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: Card(
                  color: Colors.grey[900],
                  child: Stack(
                    children: [
                      Positioned(
                        top: 6,
                        left: 6,
                        child: IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18),
                          tooltip: 'Delete',
                          onPressed: provider.isConnecting ? null : deleteConn,
                        ),
                      ),

                      Positioned(
                        top: 6,
                        right: 6,
                        child: IconButton(
                          icon: const Icon(Icons.edit, size: 18),
                          tooltip: 'Edit',
                          onPressed: openEdit,
                        ),
                      ),

                      Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Stack(
                              alignment: Alignment.center,
                              children: [
                                conn.imagePath != null
                                    ? CircleAvatar(
                                        radius: 28,
                                        backgroundImage:
                                            FileImage(File(conn.imagePath!)),
                                      )
                                    : Icon(conn.iconOrDefault, size: 50),
                                if (isConnecting)
                                  const SizedBox(
                                    width: 64,
                                    height: 64,
                                    child: CircularProgressIndicator(strokeWidth: 3),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              conn.name,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              isConnected
                                  ? 'Connected'
                                  : (isConnecting ? 'Connecting...' : 'Tap to connect'),
                              style: TextStyle(
                                fontSize: 12,
                                color: isConnected ? Colors.green : Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
