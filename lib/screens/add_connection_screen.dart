import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../models/mqtt_connection.dart';
import '../providers/connection_provider.dart';

class AddConnectionScreen extends StatefulWidget {
  final MqttConnection? existing;

  const AddConnectionScreen({super.key, this.existing});

  @override
  State<AddConnectionScreen> createState() => _AddConnectionScreenState();
}

class _AddConnectionScreenState extends State<AddConnectionScreen> {
  final _formKey = GlobalKey<FormState>();

  final _urlController = TextEditingController();
  final _hostController = TextEditingController();
  final _portController = TextEditingController();
  final _wsPathController = TextEditingController();
  final _userController = TextEditingController();
  final _passController = TextEditingController();
  final _nameController = TextEditingController();

  IconData selectedIcon = Icons.cloud;
  String? _pickedImagePath;
  final _picker = ImagePicker();


  String protocol = 'TCP';
  bool useTls = false;

  final List<IconData> _iconOptions = const [
  Icons.router,                
  Icons.wifi,                   
  Icons.sensors,               
  Icons.devices,                
  Icons.lightbulb,             
  Icons.power,                 
  Icons.thermostat,            
  Icons.lock,                  
  Icons.videocam,               
  Icons.speaker,              
  Icons.water_drop,            
  Icons.local_fire_department,  
  ];

  @override
  void initState() {
    super.initState();

    final ex = widget.existing;
    if (ex != null) {
      _nameController.text = ex.name;
      _hostController.text = ex.host;
      _portController.text = ex.port.toString();
      _wsPathController.text = ex.wsPath.isEmpty ? '/mqtt' : ex.wsPath;

      _userController.text = ex.username ?? '';
      _passController.text = '';

      protocol = ex.protocol;
      useTls = ex.useTls;

      selectedIcon = ex.iconOrDefault;
      _pickedImagePath = ex.imagePath;

      _urlController.text = _buildUrlFromFields();
    } else {
      _portController.text = '1883';
      _wsPathController.text = '/mqtt';
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _wsPathController.dispose();
    _userController.dispose();
    _passController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;

    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? 'Edit Connection' : 'Add Connection')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              const Text('Connection Avatar', style: TextStyle(fontSize: 16)),
              const SizedBox(height: 10),

              Row(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: Colors.grey[850],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Center(
                      child: _pickedImagePath != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.file(
                                File(_pickedImagePath!),
                                fit: BoxFit.cover,
                                width: 64,
                                height: 64,
                                errorBuilder: (_, __, ___) => Icon(selectedIcon, size: 36),
                              ),
                            )
                          : Icon(selectedIcon, size: 36),
                    ),
                  ),
                  const SizedBox(width: 12),

                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          icon: const Icon(Icons.image),
                          label: const Text('Pick photo'),
                          onPressed: _pickAndSaveImage,
                        ),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Remove'),
                          onPressed: _pickedImagePath == null
                              ? null
                              : () => setState(() => _pickedImagePath = null),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),
              const Text('Or choose an icon', style: TextStyle(fontSize: 16)),
              const SizedBox(height: 10),

              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _iconOptions.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 6,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemBuilder: (_, i) {
                  final icon = _iconOptions[i];
                  final selected = _pickedImagePath == null && selectedIcon == icon;

                  return InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => setState(() {
                      selectedIcon = icon;
                      _pickedImagePath = null;
                    }),
                    child: Container(
                      decoration: BoxDecoration(
                        color: selected ? Colors.blue.withOpacity(0.25) : Colors.grey[850],
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: selected ? Colors.blue : Colors.transparent),
                      ),
                      child: Icon(icon),
                    ),
                  );
                },
              ),

              const SizedBox(height: 20),

              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (v) => v == null || v.trim().isEmpty ? 'Enter a name' : null,
              ),

              const SizedBox(height: 20),

              TextFormField(
                controller: _urlController,
                decoration: const InputDecoration(
                  labelText: 'Broker URL (recommended)',
                  hintText:
                      'mqtt://host:1883 | mqtts://host:8883 | ws://host:80/mqtt | wss://host:443/mqtt',
                ),
              ),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: _applyFromUrl,
                child: const Text('Apply from URL'),
              ),

              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 10),

              DropdownButtonFormField<String>(
                value: protocol,
                items: const [
                  DropdownMenuItem(value: 'TCP', child: Text('TCP')),
                  DropdownMenuItem(value: 'WebSocket', child: Text('WebSocket')),
                ],
                onChanged: (v) => setState(() => protocol = v ?? 'TCP'),
                decoration: const InputDecoration(labelText: 'Protocol'),
              ),

              CheckboxListTile(
                title: const Text('Use TLS / SSL'),
                value: useTls,
                contentPadding: EdgeInsets.zero,
                onChanged: (v) => setState(() => useTls = v ?? false),
              ),

              TextFormField(
                controller: _hostController,
                decoration: InputDecoration(
                  labelText: 'Host',
                  prefixText: _hostPrefix(),
                  hintText: 'test.mosquitto.org',
                ),
                validator: (v) => v == null || v.trim().isEmpty ? 'Enter host' : null,
              ),

              const SizedBox(height: 10),

              TextFormField(
                controller: _portController,
                decoration: const InputDecoration(labelText: 'Port'),
                keyboardType: TextInputType.number,
                validator: (v) => v == null || int.tryParse(v) == null ? 'Enter port' : null,
              ),

              const SizedBox(height: 10),

              if (protocol == 'WebSocket')
                TextFormField(
                  controller: _wsPathController,
                  decoration: const InputDecoration(labelText: 'WebSocket Path'),
                  validator: (v) => v == null || v.trim().isEmpty ? 'Enter path' : null,
                ),

              const SizedBox(height: 20),

              TextFormField(
                controller: _userController,
                decoration: const InputDecoration(labelText: 'Username (optional)'),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _passController,
                decoration: const InputDecoration(labelText: 'Password (optional)'),
                obscureText: true,
              ),

              const SizedBox(height: 30),

              ElevatedButton(
                onPressed: _saveConnection,
                child: Text(isEdit ? 'Save Changes' : 'Save Connection'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _hostPrefix() {
    if (protocol == 'WebSocket') return useTls ? 'wss://' : 'ws://';
    return useTls ? 'mqtts://' : '';
  }

  String _buildUrlFromFields() {
    final host = _hostController.text.trim();
    final port = _portController.text.trim();
    if (host.isEmpty || port.isEmpty) return '';

    if (protocol == 'WebSocket') {
      final path = _wsPathController.text.trim().isEmpty ? '/mqtt' : _wsPathController.text.trim();
      return '${useTls ? 'wss' : 'ws'}://$host:$port$path';
    }
    return '${useTls ? 'mqtts' : 'mqtt'}://$host:$port';
  }

  void _applyFromUrl() {
    final raw = _urlController.text.trim();
    if (raw.isEmpty) return;

    Uri uri;
    try {
      uri = Uri.parse(raw);
    } catch (_) {
      _snack('Invalid URL');
      return;
    }

    final scheme = uri.scheme.toLowerCase();
    if (uri.host.isEmpty || scheme.isEmpty) {
      _snack('URL must include scheme and host');
      return;
    }

    if (scheme == 'mqtt') {
      protocol = 'TCP';
      useTls = false;
    } else if (scheme == 'mqtts') {
      protocol = 'TCP';
      useTls = true;
    } else if (scheme == 'ws') {
      protocol = 'WebSocket';
      useTls = false;
    } else if (scheme == 'wss') {
      protocol = 'WebSocket';
      useTls = true;
    } else {
      _snack('Unsupported scheme: ${uri.scheme}');
      return;
    }

    final port = uri.hasPort
        ? uri.port
        : (protocol == 'WebSocket'
            ? (useTls ? 443 : 80)
            : (useTls ? 8883 : 1883));

    final path = protocol == 'WebSocket' ? (uri.path.isEmpty ? '/mqtt' : uri.path) : '';

    setState(() {
      _hostController.text = uri.host;
      _portController.text = port.toString();
      if (protocol == 'WebSocket') _wsPathController.text = path;
    });

    _snack('Applied: ${uri.host}:$port');
  }

  Future<void> _pickAndSaveImage() async {
    try {
      final xfile = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (xfile == null) return;

      final dir = await getApplicationDocumentsDirectory();
      final ext = xfile.path.split('.').last;
      final fileName = 'conn_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final saved = await File(xfile.path).copy('${dir.path}/$fileName');

      setState(() {
        _pickedImagePath = saved.path;
      });
    } catch (e) {
      _snack('Image pick failed: $e');
    }
  }

  Future<void> _saveConnection() async {
    if (!_formKey.currentState!.validate()) return;

    final name = _nameController.text.trim();
    final host = _hostController.text.trim();
    final port = int.parse(_portController.text.trim());
    final wsPath = protocol == 'WebSocket' ? _wsPathController.text.trim() : '';

    final username = _userController.text.trim().isEmpty ? null : _userController.text.trim();
    final password = _passController.text.trim().isEmpty ? null : _passController.text.trim();

    final provider = context.read<ConnectionProvider>();

    if (widget.existing == null) {
      final conn = _pickedImagePath != null
          ? MqttConnection.withImage(
              name: name,
              host: host,
              port: port,
              useTls: useTls,
              protocol: protocol,
              wsPath: wsPath,
              imagePath: _pickedImagePath!,
              username: username,
              password: password,
            )
          : MqttConnection.withIcon(
              name: name,
              host: host,
              port: port,
              useTls: useTls,
              protocol: protocol,
              wsPath: wsPath,
              icon: selectedIcon,
              username: username,
              password: password,
            );

      await provider.addConnection(conn);
    } else {
      final updated = widget.existing!.copyWith(
        name: name,
        host: host,
        port: port,
        useTls: useTls,
        protocol: protocol,
        wsPath: wsPath,
        imagePath: _pickedImagePath,
        iconCodePoint: _pickedImagePath == null ? selectedIcon.codePoint : null,
        iconFontFamily: _pickedImagePath == null ? selectedIcon.fontFamily : null,
        iconFontPackage: _pickedImagePath == null ? selectedIcon.fontPackage : null,
        username: username,
        password: password,
      );

      await provider.updateConnection(updated);
    }

    if (!mounted) return;
    Navigator.pop(context);
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
