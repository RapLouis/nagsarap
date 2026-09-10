import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';

class PendingAttendanceRecord {
  const PendingAttendanceRecord({
    required this.uuid,
    required this.eventId,
    required this.attendanceTime,
    required this.latitude,
    required this.longitude,
    required this.locationAccuracy,
    required this.centerFramePath,
    required this.blinkFramePath,
    required this.turnedFramePath,
    required this.smileFramePath,
    required this.returnedFramePath,
  });

  final String uuid;
  final int eventId;
  final String attendanceTime;

  final double latitude;
  final double longitude;
  final double locationAccuracy;

  final String centerFramePath;
  final String blinkFramePath;
  final String turnedFramePath;
  final String smileFramePath;
  final String returnedFramePath;

  factory PendingAttendanceRecord.fromJson(Map<String, dynamic> json) {
    return PendingAttendanceRecord(
      uuid: json['uuid'].toString(),
      eventId: _readInt(json['event_id']),
      attendanceTime: json['attendance_time'].toString(),
      latitude: _readDouble(json['latitude']),
      longitude: _readDouble(json['longitude']),
      locationAccuracy: _readDouble(json['location_accuracy']),
      centerFramePath: json['center_frame_path'].toString(),
      blinkFramePath: json['blink_frame_path'].toString(),
      turnedFramePath: json['turned_frame_path'].toString(),
      smileFramePath: json['smile_frame_path'].toString(),
      returnedFramePath: json['returned_frame_path'].toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'uuid': uuid,
      'event_id': eventId,
      'attendance_time': attendanceTime,
      'latitude': latitude,
      'longitude': longitude,
      'location_accuracy': locationAccuracy,
      'center_frame_path': centerFramePath,
      'blink_frame_path': blinkFramePath,
      'turned_frame_path': turnedFramePath,
      'smile_frame_path': smileFramePath,
      'returned_frame_path': returnedFramePath,
    };
  }

  bool get allFilesExist {
    return File(centerFramePath).existsSync() &&
        File(blinkFramePath).existsSync() &&
        File(turnedFramePath).existsSync() &&
        File(smileFramePath).existsSync() &&
        File(returnedFramePath).existsSync();
  }

  static int _readInt(dynamic value) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value.toString()) ?? 0;
  }

  static double _readDouble(dynamic value) {
    if (value is double) {
      return value;
    }

    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value.toString()) ?? 0;
  }
}

class OfflineStorageService {
  OfflineStorageService._();

  static final OfflineStorageService instance = OfflineStorageService._();

  static const String _rootFolderName = 'ccis_attendance_offline';

  static const String _pendingFolderName = 'pending';

  static const String _eventsFileName = 'events.json';

  Future<Directory> _rootDirectory() async {
    final documents = await getApplicationDocumentsDirectory();

    final root = Directory('${documents.path}/$_rootFolderName');

    if (!await root.exists()) {
      await root.create(recursive: true);
    }

    return root;
  }

  Future<Directory> _pendingDirectory() async {
    final root = await _rootDirectory();

    final pending = Directory('${root.path}/$_pendingFolderName');

    if (!await pending.exists()) {
      await pending.create(recursive: true);
    }

    return pending;
  }

  // ===========================================================================
  // EVENT CACHE
  // ===========================================================================

  Future<void> cacheEvents(List<Map<String, dynamic>> events) async {
    final root = await _rootDirectory();

    final file = File('${root.path}/$_eventsFileName');

    final payload = <String, dynamic>{
      'cached_at': DateTime.now().toUtc().toIso8601String(),
      'events': events,
    };

    await file.writeAsString(jsonEncode(payload), flush: true);
  }

  Future<List<Map<String, dynamic>>> loadCachedEvents() async {
    try {
      final root = await _rootDirectory();

      final file = File('${root.path}/$_eventsFileName');

      if (!await file.exists()) {
        return <Map<String, dynamic>>[];
      }

      final raw = await file.readAsString();

      if (raw.trim().isEmpty) {
        return <Map<String, dynamic>>[];
      }

      final decoded = jsonDecode(raw);

      if (decoded is! Map) {
        return <Map<String, dynamic>>[];
      }

      final map = Map<String, dynamic>.from(decoded);

      final rawEvents = map['events'];

      if (rawEvents is! List) {
        return <Map<String, dynamic>>[];
      }

      final events = <Map<String, dynamic>>[];

      for (final item in rawEvents) {
        if (item is Map) {
          events.add(Map<String, dynamic>.from(item));
        }
      }

      return events;
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  // ===========================================================================
  // PENDING ATTENDANCE
  // ===========================================================================

  Future<bool> hasPendingForEvent(int eventId) async {
    final records = await getPendingAttendances();

    return records.any((record) => record.eventId == eventId);
  }

  Future<PendingAttendanceRecord> queueAttendance({
    required int eventId,
    required double latitude,
    required double longitude,
    required double locationAccuracy,
    required DateTime attendanceTime,
    required XFile centerFrame,
    required XFile blinkFrame,
    required XFile turnedFrame,
    required XFile smileFrame,
    required XFile returnedFrame,
  }) async {
    final pending = await _pendingDirectory();

    final uuid = _generateUuidV4();

    final recordDirectory = Directory('${pending.path}/$uuid');

    await recordDirectory.create(recursive: true);

    try {
      final centerPath = '${recordDirectory.path}/center.jpg';

      final blinkPath = '${recordDirectory.path}/blink.jpg';

      final turnedPath = '${recordDirectory.path}/turned.jpg';

      final smilePath = '${recordDirectory.path}/smile.jpg';

      final returnedPath = '${recordDirectory.path}/returned.jpg';

      await File(centerFrame.path).copy(centerPath);

      await File(blinkFrame.path).copy(blinkPath);

      await File(turnedFrame.path).copy(turnedPath);

      await File(smileFrame.path).copy(smilePath);

      await File(returnedFrame.path).copy(returnedPath);

      final record = PendingAttendanceRecord(
        uuid: uuid,
        eventId: eventId,
        attendanceTime: attendanceTime.toUtc().toIso8601String(),
        latitude: latitude,
        longitude: longitude,
        locationAccuracy: locationAccuracy,
        centerFramePath: centerPath,
        blinkFramePath: blinkPath,
        turnedFramePath: turnedPath,
        smileFramePath: smilePath,
        returnedFramePath: returnedPath,
      );

      final metadata = File('${recordDirectory.path}/metadata.json');

      await metadata.writeAsString(jsonEncode(record.toJson()), flush: true);

      return record;
    } catch (_) {
      if (await recordDirectory.exists()) {
        await recordDirectory.delete(recursive: true);
      }

      rethrow;
    }
  }

  Future<List<PendingAttendanceRecord>> getPendingAttendances() async {
    final pending = await _pendingDirectory();

    final records = <PendingAttendanceRecord>[];

    await for (final entity in pending.list(followLinks: false)) {
      if (entity is! Directory) {
        continue;
      }

      try {
        final metadata = File('${entity.path}/metadata.json');

        if (!await metadata.exists()) {
          continue;
        }

        final raw = await metadata.readAsString();

        final decoded = jsonDecode(raw);

        if (decoded is! Map) {
          continue;
        }

        final record = PendingAttendanceRecord.fromJson(
          Map<String, dynamic>.from(decoded),
        );

        records.add(record);
      } catch (_) {
        continue;
      }
    }

    records.sort((a, b) => a.attendanceTime.compareTo(b.attendanceTime));

    return records;
  }

  Future<int> pendingCount() async {
    final records = await getPendingAttendances();

    return records.length;
  }

  Future<void> deletePending(PendingAttendanceRecord record) async {
    final directory = Directory(File(record.centerFramePath).parent.path);

    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  Future<void> deletePendingByUuid(String uuid) async {
    final pending = await _pendingDirectory();

    final directory = Directory('${pending.path}/$uuid');

    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  // ===========================================================================
  // UUID V4
  // ===========================================================================

  String _generateUuidV4() {
    final random = Random.secure();

    final bytes = List<int>.generate(16, (_) => random.nextInt(256));

    bytes[6] = (bytes[6] & 0x0f) | 0x40;

    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    String hex(int value) => value.toRadixString(16).padLeft(2, '0');

    final value = bytes.map(hex).join();

    return '${value.substring(0, 8)}-'
        '${value.substring(8, 12)}-'
        '${value.substring(12, 16)}-'
        '${value.substring(16, 20)}-'
        '${value.substring(20, 32)}';
  }
}
