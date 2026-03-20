import 'package:supabase_flutter/supabase_flutter.dart';

import 'background_tracking_service.dart';

class TrackingRepository {
  TrackingRepository._();
  static final TrackingRepository instance = TrackingRepository._();

  final SupabaseClient _client = Supabase.instance.client;

  Future<void> createSession({
    required String sessionId,
    required String driverId,
    required double startLat,
    required double startLng,
    Map<String, dynamic>? meta,
  }) async {
    await _client.from('tracking_sessions').insert({
      'session_id': sessionId,
      'driver_id': driverId,
      'status': 'active',
      'start_lat': startLat,
      'start_lng': startLng,
      'meta': meta ?? {},
    });
  }

  Future<void> closeSession({
    required String sessionId,
    required double endLat,
    required double endLng,
    Map<String, dynamic>? meta,
  }) async {
    await _client
        .from('tracking_sessions')
        .update({
          'status': 'ended',
          'ended_at': DateTime.now().toUtc().toIso8601String(),
          'end_lat': endLat,
          'end_lng': endLng,
          'meta': meta ?? {},
        })
        .eq('session_id', sessionId);
  }

  Future<void> insertPoint({
    required String sessionId,
    required TrackingPoint point,
    String? activity,
    String source = 'flutter_bg_geo',
  }) async {
    await _client.from('tracking_points').insert({
      'session_id': sessionId,
      'latitude': point.latitude,
      'longitude': point.longitude,
      'accuracy': point.accuracy,
      'speed': point.speed,
      'heading': point.heading,
      'is_moving': point.isMoving,
      'activity': activity,
      'recorded_at': point.timestamp.toUtc().toIso8601String(),
      'source': source,
      'extras': point.extras ?? {},
    });
  }

  Future<List<Map<String, dynamic>>> listSessions() async {
    final result = await _client
        .from('tracking_sessions')
        .select('session_id, driver_id, status, ended_at')
        .order('session_id', ascending: false);

    return List<Map<String, dynamic>>.from(result);
  }

  Future<List<Map<String, dynamic>>> getPointsBySession(
    String sessionId,
  ) async {
    final result = await _client
        .from('tracking_points')
        .select()
        .eq('session_id', sessionId)
        .order('recorded_at', ascending: true);

    return List<Map<String, dynamic>>.from(result);
  }

  Stream<List<Map<String, dynamic>>> streamPointsBySession(String sessionId) {
    return _client
        .from('tracking_points')
        .stream(primaryKey: ['id'])
        .eq('session_id', sessionId)
        .order('recorded_at');
  }
}
