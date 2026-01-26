import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/connection_provider.dart';
import 'screens/connections_screen.dart';
import 'screens/topics_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ConnectionProvider(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Flutter MQTTX',
        theme: ThemeData.dark(),
        home: const MainScreen(),
      ),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  static const List<Widget> _screens = <Widget>[
    ConnectionsScreen(),
    TopicsScreen(),
  ];

  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ConnectionProvider>();

    final topicsIconColor =
        provider.isConnected ? Colors.green : null; // null = default theme color

    return Scaffold(
      body: _screens[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.cloud),
            label: 'Connections',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.list, color: topicsIconColor),
            label: provider.isConnected ? 'Topics (Connected)' : 'Topics',
          ),
        ],
        onTap: _onItemTapped,
      ),
    );
  }
}
