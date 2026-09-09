import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../core/api_endpoints.dart';
import '../models/event_item.dart';
import 'api_service.dart';

class EventResult {
  final bool success;

  final String message;

  final List<EventItem> events;

  const EventResult({
    required this.success,
    required this.message,
    this.events = const [],
  });
}

class EventService {
  EventService._();

  static final EventService instance = EventService._();

  final ApiService _api = ApiService.instance;

  // ===========================================================================
  // GET EVENTS
  // ===========================================================================

  Future<EventResult> getEvents() async {
    try {
      final response = await _api.dio.get(ApiEndpoints.events);

      if (kDebugMode) {
        debugPrint('========== EVENTS API ==========');

        debugPrint('STATUS: ${response.statusCode}');

        debugPrint('DATA: ${response.data}');

        debugPrint('================================');
      }

      if (response.statusCode == 401) {
        return const EventResult(
          success: false,
          message: 'Your login session has expired.',
        );
      }

      if (response.statusCode == null ||
          response.statusCode! < 200 ||
          response.statusCode! >= 300) {
        return EventResult(
          success: false,
          message: 'Unable to load events. HTTP ${response.statusCode}.',
        );
      }

      final raw = response.data;

      if (raw is! Map) {
        return const EventResult(
          success: false,
          message: 'Invalid event response from server.',
        );
      }

      final responseMap = Map<String, dynamic>.from(raw);

      if (responseMap['success'] != true) {
        return EventResult(
          success: false,
          message:
              responseMap['message']?.toString() ?? 'Unable to load events.',
        );
      }

      final rawEvents = responseMap['data'];

      if (rawEvents == null) {
        return const EventResult(
          success: true,
          message: 'No events available.',
          events: [],
        );
      }

      if (rawEvents is! List) {
        return const EventResult(
          success: false,
          message: 'The event API returned an invalid data format.',
        );
      }

      final events = <EventItem>[];

      for (final item in rawEvents) {
        if (item is Map) {
          final map = Map<String, dynamic>.from(item);

          events.add(EventItem.fromJson(map));
        }
      }

      events.sort((EventItem first, EventItem second) {
        final firstDate = first.date;

        final secondDate = second.date;

        if (firstDate == null && secondDate == null) {
          return first.startTime.compareTo(second.startTime);
        }

        if (firstDate == null) {
          return 1;
        }

        if (secondDate == null) {
          return -1;
        }

        final dateComparison = firstDate.compareTo(secondDate);

        if (dateComparison != 0) {
          return dateComparison;
        }

        return first.startTime.compareTo(second.startTime);
      });

      if (kDebugMode) {
        debugPrint('PARSED EVENTS: ${events.length}');

        for (final event in events) {
          debugPrint(
            'EVENT ${event.id}: '
            '${event.name} | '
            '${event.normalizedDate} | '
            'today=${event.isToday} | '
            'active=${event.isActive}',
          );
        }
      }

      return EventResult(
        success: true,
        message: 'Events loaded successfully.',
        events: events,
      );
    } on DioException catch (exception) {
      if (kDebugMode) {
        debugPrint('EVENT DIO ERROR');

        debugPrint('STATUS: ${exception.response?.statusCode}');

        debugPrint('DATA: ${exception.response?.data}');
      }

      if (exception.response?.statusCode == 401) {
        return const EventResult(
          success: false,
          message: 'Your login session has expired.',
        );
      }

      final raw = exception.response?.data;

      if (raw is Map && raw['message'] != null) {
        return EventResult(success: false, message: raw['message'].toString());
      }

      if (exception.response == null) {
        return const EventResult(
          success: false,
          message: 'Unable to connect to Laravel.',
        );
      }

      return EventResult(
        success: false,
        message:
            'Unable to load events. HTTP ${exception.response?.statusCode}.',
      );
    } catch (exception) {
      if (kDebugMode) {
        debugPrint('EVENT PARSE ERROR: $exception');
      }

      return const EventResult(
        success: false,
        message: 'Unable to process the event data.',
      );
    }
  }
}
