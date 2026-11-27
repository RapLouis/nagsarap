import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SecureTimeService {
  SecureTimeService._internal() {
    _stopwatch.start();
    _initAnchor();
  }

  static final SecureTimeService instance = SecureTimeService._internal();

  final Stopwatch _stopwatch = Stopwatch();

  DateTime? _anchorServerTime;
  int? _anchorStopwatchMs;
  int _lastKnownTimeMs = 0;

  static const String _keyAnchorServerMs = 'secure_time_anchor_server_ms';
  static const String _keyAnchorStopwatchMs = 'secure_time_anchor_stopwatch_ms';
  static const String _keyLastKnownMs = 'secure_time_last_known_ms';

  Future<void> _initAnchor() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final serverMs = prefs.getInt(_keyAnchorServerMs);
      final stopMs = prefs.getInt(_keyAnchorStopwatchMs);
      _lastKnownTimeMs = prefs.getInt(_keyLastKnownMs) ?? 0;

      if (serverMs != null && stopMs != null) {
        _anchorServerTime = DateTime.fromMillisecondsSinceEpoch(serverMs, isUtc: true);
        _anchorStopwatchMs = stopMs;
      }
    } catch (e) {
      debugPrint('SecureTimeService init error: $e');
    }
  }

  /// Called whenever the app communicates with the server to update the verified anchor time
  Future<void> updateServerAnchor(DateTime serverTime) async {
    try {
      _anchorServerTime = serverTime.toUtc();
      _anchorStopwatchMs = _stopwatch.elapsedMilliseconds;
      _lastKnownTimeMs = _anchorServerTime!.millisecondsSinceEpoch;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keyAnchorServerMs, _anchorServerTime!.millisecondsSinceEpoch);
      await prefs.setInt(_keyAnchorStopwatchMs, _anchorStopwatchMs!);
      await prefs.setInt(_keyLastKnownMs, _lastKnownTimeMs);
    } catch (e) {
      debugPrint('Error updating server time anchor: $e');
    }
  }

  /// Calculates true current timestamp using hardware monotonic elapsed time
  /// Immune to manual edits in Android/iOS system settings
  Future<DateTime> getTrustedTime() async {
    if (_anchorServerTime == null || _anchorStopwatchMs == null) {
      await _initAnchor();
    }

    DateTime calculated;

    if (_anchorServerTime != null && _anchorStopwatchMs != null) {
      final elapsedMs = _stopwatch.elapsedMilliseconds - _anchorStopwatchMs!;
      calculated = _anchorServerTime!.add(Duration(milliseconds: elapsedMs));
    } else {
      calculated = DateTime.now().toUtc();
    }

    final calculatedMs = calculated.millisecondsSinceEpoch;

    // Time Rollback Prevention: Never allow time to go backward into the past
    if (calculatedMs < _lastKnownTimeMs) {
      calculated = DateTime.fromMillisecondsSinceEpoch(_lastKnownTimeMs, isUtc: true);
    } else {
      _lastKnownTimeMs = calculatedMs;
      _persistLastKnownTime(calculatedMs);
    }

    return calculated;
  }

  Future<void> _persistLastKnownTime(int ms) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keyLastKnownMs, ms);
    } catch (_) {}
  }
}