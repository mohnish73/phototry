import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:photo_manager/photo_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gallery Backup',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const UploadScreen(),
    );
  }
}

class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  static const _channel = MethodChannel('com.example.phototry/upload');

  Timer? _pollTimer;
  bool _isUploading = false;
  int _total = 0;
  int _uploaded = 0;
  String _statusMessage = '';

  @override
  void initState() {
    super.initState();
    // Restore state if upload was running when app was reopened
    _fetchProgress();
  }

  Future<void> _fetchProgress() async {
    final data = await _channel.invokeMapMethod<String, dynamic>('getProgress');
    if (data == null || !mounted) return;
    final running = data['running'] as bool? ?? false;
    setState(() {
      _uploaded = data['uploaded'] as int? ?? 0;
      _total = data['total'] as int? ?? 0;
      _statusMessage = data['status'] as String? ?? '';
      _isUploading = running;
    });
    if (running) {
      _startPolling();
    } else {
      _pollTimer?.cancel();
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _fetchProgress());
  }

  Future<void> _startUpload() async {
    final permission = await PhotoManager.requestPermissionExtend();
    if (!permission.hasAccess) {
      setState(() => _statusMessage = 'Gallery permission denied.');
      return;
    }

    try {
      await _channel.invokeMethod('requestBatteryOptimization');
    } catch (_) {}

    setState(() {
      _isUploading = true;
      _total = 0;
      _uploaded = 0;
      _statusMessage = 'Starting background upload...';
    });

    await _channel.invokeMethod('startUpload');
    _startPolling();
  }

  Future<void> _stopUpload() async {
    _pollTimer?.cancel();
    await _channel.invokeMethod('stopUpload');
    setState(() {
      _isUploading = false;
      _statusMessage = 'Upload stopped.';
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double progress = _total > 0 ? _uploaded / _total : 0.0;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.cloud_upload_outlined,
                    size: 96, color: Colors.deepPurple),
                const SizedBox(height: 24),
                Text(
                  'Gallery Backup',
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Upload continues even when the app is closed.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: Colors.grey[600]),
                ),
                const SizedBox(height: 48),
                if (_isUploading) ...[
                  LinearProgressIndicator(
                    value: _total > 0 ? progress : null,
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '$_uploaded / $_total uploaded',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                ],
                if (_statusMessage.isNotEmpty)
                  Text(
                    _statusMessage,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _statusMessage.contains('denied') ||
                              _statusMessage.contains('stopped') ||
                              _statusMessage.contains('Error')
                          ? Colors.red
                          : Colors.grey[700],
                    ),
                  ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton.icon(
                    onPressed: _isUploading ? null : _startUpload,
                    icon: _isUploading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.upload),
                    label: Text(
                      _isUploading ? 'Uploading...' : 'Upload All Photos',
                      style: const TextStyle(fontSize: 16),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                if (_isUploading) ...[
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _stopUpload,
                    child: const Text('Stop Upload',
                        style: TextStyle(color: Colors.red)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
