import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AttendanceRepository {
  static final AttendanceRepository instance = AttendanceRepository._internal();
  AttendanceRepository._internal() {
    _initConnectivityListener();
  }

  static const String _baseUrl = 'https://your-api-domain.com/api'; // Replace with your actual backend URL
  static const String _queueKey = 'offline_attendance_queue';
  static const _storage = FlutterSecureStorage();

  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 4),
      receiveTimeout: const Duration(seconds: 4),
    ),
  );

  void _initConnectivityListener() {
    Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      if (results.any((r) => r != ConnectivityResult.none)) {
        syncPendingAttendance();
      }
    });
  }

  /// Records attendance online or queues locally if network fails
  Future<Map<String, dynamic>> submitAttendance({
    required int eventId,
    required String type, // 'time_in' or 'time_out'
    required String timestamp,
    Map<String, dynamic>? extraFields,
  }) async {
    final payload = {
      'event_id': eventId,
      'type': type,
      'timestamp': timestamp,
      if (extraFields != null) ...extraFields,
    };

    final token = await _storage.read(key: 'auth_token');

    try {
      final response = await _dio.post(
        '/attendance',
        data: payload,
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return {
          'success': true,
          'synced': true,
          'message': 'Attendance recorded successfully',
        };
      } else {
        await _queueLocally(payload);
        return {
          'success': true,
          'synced': false,
          'message': 'Saved locally (Server error)',
        };
      }
    } on DioException catch (_) {
      await _queueLocally(payload);
      return {
        'success': true,
        'synced': false,
        'message': 'Saved locally (Offline mode)',
      };
    } catch (_) {
      await _queueLocally(payload);
      return {
        'success': true,
        'synced': false,
        'message': 'Saved locally (Offline mode)',
      };
    }
  }

  Future<void> _queueLocally(Map<String, dynamic> payload) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> currentQueue = prefs.getStringList(_queueKey) ?? [];
    currentQueue.add(jsonEncode(payload));
    await prefs.setStringList(_queueKey, currentQueue);
  }

  /// Synchronizes offline queued logs once back online
  Future<void> syncPendingAttendance() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> currentQueue = prefs.getStringList(_queueKey) ?? [];

    if (currentQueue.isEmpty) return;

    final token = await _storage.read(key: 'auth_token');
    if (token == null) return;

    final List<String> remainingQueue = [];

    for (final itemStr in currentQueue) {
      try {
        final payload = jsonDecode(itemStr);
        final response = await _dio.post(
          '/attendance',
          data: payload,
          options: Options(headers: {'Authorization': 'Bearer $token'}),
        );

        if (response.statusCode != 200 && response.statusCode != 201) {
          remainingQueue.add(itemStr);
        }
      } catch (_) {
        remainingQueue.add(itemStr);
      }
    }

    await prefs.setStringList(_queueKey, remainingQueue);
  }
}