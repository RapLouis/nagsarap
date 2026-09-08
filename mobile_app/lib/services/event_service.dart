import 'package:dio/dio.dart';

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

  Future<EventResult> getEvents() async {
    try {
      final response = await _api.dio.get(ApiEndpoints.events);

      if (response.statusCode == 401) {
        return const EventResult(
          success: false,
          message: 'Your login session has expired.',
        );
      }

      final raw = response.data;

      if (raw is! Map) {
        return const EventResult(
          success: false,
          message: 'Invalid response from the server.',
        );
      }

      final data = Map<String, dynamic>.from(raw);

      if (data['success'] == false) {
        return EventResult(
          success: false,
          message: data['message']?.toString() ?? 'Unable to load events.',
        );
      }

      final rawEvents = data['data'];

      if (rawEvents is! List) {
        return const EventResult(
          success: true,
          message: 'No events available.',
          events: [],
        );
      }

      final events = <EventItem>[];

      for (final item in rawEvents) {
        if (item is Map) {
          events.add(EventItem.fromJson(Map<String, dynamic>.from(item)));
        }
      }

      events.sort((a, b) {
        final aDate = a.date;
        final bDate = b.date;

        if (aDate == null && bDate == null) {
          return 0;
        }

        if (aDate == null) {
          return 1;
        }

        if (bDate == null) {
          return -1;
        }

        final dateResult = aDate.compareTo(bDate);

        if (dateResult != 0) {
          return dateResult;
        }

        return a.startTime.compareTo(b.startTime);
      });

      return EventResult(
        success: true,
        message: 'Events loaded.',
        events: events,
      );
    } on DioException catch (e) {
      final response = e.response;

      if (response?.statusCode == 401) {
        return const EventResult(
          success: false,
          message: 'Your login session has expired.',
        );
      }

      if (response?.data is Map) {
        final data = Map<String, dynamic>.from(response!.data as Map);

        return EventResult(
          success: false,
          message: data['message']?.toString() ?? 'Unable to load events.',
        );
      }

      return const EventResult(
        success: false,
        message: 'Unable to connect to the server.',
      );
    } catch (_) {
      return const EventResult(
        success: false,
        message: 'Unable to load events.',
      );
    }
  }
}
