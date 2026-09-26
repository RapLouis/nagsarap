class LivenessChallenge {
  const LivenessChallenge({
    required this.nonce,
    required this.direction,
    required this.sessionId,
    this.expiresAt,
    this.networkUnavailable = false,
    this.message = '',
  });

  final String nonce;
  final String direction;
  final String sessionId;
  final int? expiresAt;
  final bool networkUnavailable;
  final String message;

  bool get isLeft => direction == 'left';
  bool get isRight => direction == 'right';
}
