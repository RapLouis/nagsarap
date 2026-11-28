class LivenessChallenge {
  final String nonce;
  final String direction; // 'left' or 'right'
  final String sessionId;
  final int? expiresAt;
  final List<String> flashColors;

  const LivenessChallenge({
    required this.nonce,
    required this.direction,
    required this.sessionId,
    this.expiresAt,
    this.flashColors = const ['red', 'green', 'blue'],
  });
}

class AttendanceLivenessFrameResult {
  final bool success;
  final String? code;
  final String message;
  final bool faceDetected;
  final double? yaw;
  final double? faceCenterX;
  final double? faceCenterY;
  final bool faceInComfortableZone;
  final double? eyeOpenness;
  final double? mouthWidth;
  final double? blurScore;
  final double? detectionScore;
  final Map<String, dynamic> data;
  final bool networkUnavailable;

  const AttendanceLivenessFrameResult({
    required this.success,
    this.code,
    required this.message,
    this.faceDetected = false,
    this.yaw,
    this.faceCenterX,
    this.faceCenterY,
    this.faceInComfortableZone = true,
    this.eyeOpenness,
    this.mouthWidth,
    this.blurScore,
    this.detectionScore,
    this.data = const {},
    this.networkUnavailable = false,
  });
}

class AttendanceResult {
  final bool success;
  final String? code;
  final String message;
  final Map<String, dynamic>? data;
  final bool networkUnavailable;

  const AttendanceResult({
    required this.success,
    this.code,
    required this.message,
    this.data,
    this.networkUnavailable = false,
  });

  factory AttendanceResult.fromJson(Map<String, dynamic> json) {
    final rawData = json['data'];
    return AttendanceResult(
      success: json['success'] == true,
      code: json['code']?.toString(),
      message: json['message']?.toString() ?? 'Attendance processed.',
      data: rawData is Map ? Map<String, dynamic>.from(rawData) : null,
    );
  }
}

class OfflineSyncResult {
  final int total;
  final int synced;
  final int remaining;
  final String message;

  const OfflineSyncResult({
    required this.total,
    required this.synced,
    required this.remaining,
    required this.message,
  });
}