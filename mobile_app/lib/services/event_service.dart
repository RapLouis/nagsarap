import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../core/api_endpoints.dart';
import '../models/event_item.dart';
import 'api_service.dart';
import 'attendance_service.dart';
import 'offline_storage_service.dart';

class EventResult {
  const EventResult({
    required this.success,
    required this.message,
    this.events = const [],
    this.fromCache = false,
  });

  final bool success;
  final String message;
  final List<EventItem> events;
  final bool fromCache;
}

class EventService {
  EventService._();

  static final EventService instance = EventService._();

  final ApiService _api = ApiService.instance;

  final OfflineStorageService _offlineStorage = OfflineStorageService.instance;

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
        await _offlineStorage.cacheEvents(<Map<String, dynamic>>[]);

        unawaited(AttendanceService.instance.syncPendingAttendances());

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

      final eventMaps = <Map<String, dynamic>>[];

      for (final item in rawEvents) {
        if (item is Map) {
          eventMaps.add(Map<String, dynamic>.from(item));
        }
      }

      await _offlineStorage.cacheEvents(eventMaps);

      final events = _parseEvents(eventMaps);

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

      /*
       * Do not delay the dashboard while old
       * pending records synchronize.
       */
      unawaited(AttendanceService.instance.syncPendingAttendances());

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

      /*
       * Only use the offline cache when
       * Laravel genuinely cannot be reached.
       *
       * We do not hide real 4xx/5xx responses.
       */
      if (exception.response == null) {
        return _loadOfflineEvents();
      }

      final raw = exception.response?.data;

      if (raw is Map && raw['message'] != null) {
        return EventResult(success: false, message: raw['message'].toString());
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

      return _loadOfflineEvents();
    }
  }

  // ===========================================================================
  // OFFLINE EVENTS
  // ===========================================================================

  Future<EventResult> _loadOfflineEvents() async {
    final cached = await _offlineStorage.loadCachedEvents();

    if (cached.isEmpty) {
      return const EventResult(
        success: false,
        message:
            'No internet connection and no cached events are available yet.',
      );
    }

    final events = _parseEvents(cached);

    return EventResult(
      success: true,
      message: 'Offline mode: showing saved event data.',
      events: events,
      fromCache: true,
    );
  }

  // ===========================================================================
  // PARSE
  // ===========================================================================

  List<EventItem> _parseEvents(List<Map<String, dynamic>> rawEvents) {
    final events = <EventItem>[];

    for (final map in rawEvents) {
      events.add(EventItem.fromJson(map));
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

    return events;
  }
}
