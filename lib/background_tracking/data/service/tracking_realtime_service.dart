import 'package:supabase_flutter/supabase_flutter.dart';

class TrackingRealtimeService {
  TrackingRealtimeService._();
  static final TrackingRealtimeService instance = TrackingRealtimeService._();

  final _client = Supabase.instance.client;
  RealtimeChannel? _channel;

  void subscribeToSessionPoints({
    required String sessionId,
    required void Function(Map<String, dynamic> newRow) onInsert,
    void Function(Map<String, dynamic> row)? onUpdate,
    void Function()? onSubscribed,
    void Function(Object error)? onError,
  }) {
    _channel?.unsubscribe();

    _channel = _client
        .channel('tracking-points-$sessionId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'tracking_points',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'session_id',
            value: sessionId,
          ),
          callback: (payload) {
            final row = payload.newRecord;
            onInsert(Map<String, dynamic>.from(row));
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'tracking_points',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'session_id',
            value: sessionId,
          ),
          callback: (payload) {
            if (onUpdate != null) {
              onUpdate(Map<String, dynamic>.from(payload.newRecord));
            }
          },
        )
        .subscribe((status, error) {
          if (status == RealtimeSubscribeStatus.subscribed) {
            onSubscribed?.call();
          }
          if (error != null) {
            onError?.call(error);
          }
        });
  }

  Future<void> dispose() async {
    if (_channel != null) {
      await _client.removeChannel(_channel!);
      _channel = null;
    }
  }
}
