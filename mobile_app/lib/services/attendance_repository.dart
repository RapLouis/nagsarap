import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'attendance_service.dart';

class AttendanceRepository {
  static final AttendanceRepository instance = AttendanceRepository._internal();

  AttendanceRepository._internal() {
    _initConnectivityListener();
  }

  void _initConnectivityListener() {
    Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      if (results.any((r) => r != ConnectivityResult.none)) {
        syncPendingAttendance();
      }
    });
  }

  Future<void> syncPendingAttendance() async {
    await AttendanceService.instance.syncPendingAttendances();
  }
}