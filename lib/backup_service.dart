import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';

class BackupService extends ChangeNotifier {
  static const _channel = MethodChannel('com.example.phototry/upload');

  static final BackupService _instance = BackupService._internal();
  factory BackupService() => _instance;
  BackupService._internal();

  Timer? _pollTimer;
  bool isUploading = false;
  int total = 0;
  int uploaded = 0;
  String statusMessage = '';

  double get progress => total > 0 ? uploaded / total : 0.0;

  Future<void> fetchProgress() async {
    final data = await _channel.invokeMapMethod<String, dynamic>('getProgress');
    if (data == null) return;
    final running = data['running'] as bool? ?? false;
    uploaded = data['uploaded'] as int? ?? 0;
    total = data['total'] as int? ?? 0;
    statusMessage = data['status'] as String? ?? '';
    isUploading = running;
    notifyListeners();
    if (running) {
      _startPolling();
    } else {
      _pollTimer?.cancel();
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => fetchProgress());
  }

  Future<bool> startUpload() async {
    final permission = await PhotoManager.requestPermissionExtend();
    if (!permission.hasAccess) {
      statusMessage = 'Gallery permission denied.';
      notifyListeners();
      return false;
    }

    isUploading = true;
    total = 0;
    uploaded = 0;
    statusMessage = 'Starting background upload...';
    notifyListeners();

    await _channel.invokeMethod('startUpload');
    _startPolling();
    return true;
  }

  Future<void> stopUpload() async {
    _pollTimer?.cancel();
    await _channel.invokeMethod('stopUpload');
    isUploading = false;
    statusMessage = 'Upload stopped.';
    notifyListeners();
  }

  // Singleton — never call super.dispose(); that permanently marks the
  // ChangeNotifier as dead and silently kills every future notifyListeners().
  void cancelPolling() {
    _pollTimer?.cancel();
  }
}