import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/sanction_item.dart';
import 'api_service.dart';

class SanctionResult {
  final bool success;
  final String message;
  final List<SanctionItem> sanctions;

  const SanctionResult({
    required this.success,
    required this.message,
    required this.sanctions,
  });
}

class SanctionService {
  SanctionService._();

  static final SanctionService instance = SanctionService._();

  final ApiService _api = ApiService.instance;

  Future<SanctionResult> getSanctions() async {
    try {
      final response = await _api.dio.get('/api/v1/sanctions');

      final raw = response.data;

      if (raw is! Map) {
        return const SanctionResult(
          success: false,
          message: 'Invalid response from the server.',
          sanctions: [],
        );
      }

      final map = Map<String, dynamic>.from(raw);

      final dynamic rawData = map['data'];

      final sanctions = <SanctionItem>[];

      if (rawData is List) {
        for (final item in rawData) {
          if (item is Map) {
            sanctions.add(
              SanctionItem.fromJson(Map<String, dynamic>.from(item)),
            );
          }
        }
      }

      return SanctionResult(
        success: map['success'] == true,
        message: map['message']?.toString() ?? 'Sanctions loaded.',
        sanctions: sanctions,
      );
    } on DioException catch (e) {
      return SanctionResult(
        success: false,
        message: _errorMessage(e),
        sanctions: const [],
      );
    } catch (e) {
      debugPrint('SANCTIONS ERROR: $e');

      return const SanctionResult(
        success: false,
        message: 'Unable to load sanctions.',
        sanctions: [],
      );
    }
  }

  String _errorMessage(DioException exception) {
    final response = exception.response;

    if (response == null) {
      return 'Unable to connect to Laravel.';
    }

    final raw = response.data;

    if (raw is Map) {
      final map = Map<String, dynamic>.from(raw);

      final message = map['message']?.toString();

      if (message != null && message.isNotEmpty) {
        return message;
      }
    }

    if (response.statusCode == 401) {
      return 'Your session has expired. Please log in again.';
    }

    return 'Unable to load sanctions.';
  }
}
