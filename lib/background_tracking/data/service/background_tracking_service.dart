import 'dart:async';
import 'dart:math';

import 'package:flutter_background_geolocation/flutter_background_geolocation.dart'
    as bg;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'tracking_repository.dart';

class TrackingPoint {
  final double latitude;
  final double longitude;
  final double? accuracy;
  final double? speed;
  final double? heading;
  final DateTime timestamp;
  final bool? isMoving;
  final Map<String, dynamic>? extras;

  TrackingPoint({
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.accuracy,
    this.speed,
    this.heading,
    this.isMoving,
    this.extras,
  });

  LatLng toLatLng() => LatLng(latitude, longitude);

  factory TrackingPoint.fromBgLocation(bg.Location location) {
    return TrackingPoint(
      latitude: location.coords.latitude,
      longitude: location.coords.longitude,
      accuracy: location.coords.accuracy,
      speed: location.coords.speed,
      heading: location.coords.heading,
      timestamp: DateTime.tryParse(location.timestamp) ?? DateTime.now(),
      isMoving: location.isMoving,
      extras: location.extras != null
          ? Map<String, dynamic>.from(location.extras!)
          : null,
    );
  }
}

class TrackingStatusSnapshot {
  final bool enabled;
  final String activity;
  final bool isMoving;
  final int storedCount;
  final TrackingPoint? lastPoint;

  const TrackingStatusSnapshot({
    required this.enabled,
    required this.activity,
    required this.isMoving,
    required this.storedCount,
    required this.lastPoint,
  });
}

class BackgroundTrackingService {
  BackgroundTrackingService._();
  static final BackgroundTrackingService instance =
      BackgroundTrackingService._();
  static const String _activeSessionStorageKey =
      'background_tracking.active_session_id';

  final StreamController<TrackingPoint> _locationController =
      StreamController<TrackingPoint>.broadcast();

  final StreamController<TrackingStatusSnapshot> _statusController =
      StreamController<TrackingStatusSnapshot>.broadcast();

  TrackingPoint? _lastPoint;
  bool _initialized = false;
  String? _currentSessionId;
  String _lastActivity = 'unknown';
  bool _isMoving = false;
  bool _sessionRestored = false;

  Stream<TrackingPoint> get stream => _locationController.stream;
  Stream<TrackingStatusSnapshot> get statusStream => _statusController.stream;
  TrackingPoint? get lastPoint => _lastPoint;
  bool get sessionRestored => _sessionRestored;

  Future<void> init() async {
    if (_initialized) return;

    bg.BackgroundGeolocation.onLocation(
      (bg.Location location) async {
        final point = TrackingPoint.fromBgLocation(location);
        _lastPoint = point;
        _isMoving = location.isMoving;

        if (!_locationController.isClosed) {
          _locationController.add(point);
        }

        if (_currentSessionId != null) {
          await TrackingRepository.instance.insertPoint(
            sessionId: _currentSessionId!,
            point: point,
            activity: _lastActivity,
          );
        }

        await _emitStatus();
      },
      (bg.LocationError error) async {
        await _emitStatus();
      },
    );

    bg.BackgroundGeolocation.onMotionChange((bg.Location location) async {
      final point = TrackingPoint.fromBgLocation(location);
      _lastPoint = point;
      _isMoving = location.isMoving;

      if (!_locationController.isClosed) {
        _locationController.add(point);
      }

      await _emitStatus();
    });

    bg.BackgroundGeolocation.onActivityChange((
      bg.ActivityChangeEvent event,
    ) async {
      _lastActivity = event.activity;
      await _emitStatus();
    });

    bg.BackgroundGeolocation.onProviderChange((
      bg.ProviderChangeEvent event,
    ) async {
      await _emitStatus();
    });

    bg.BackgroundGeolocation.onHeartbeat((bg.HeartbeatEvent event) async {
      try {
        final location = await bg.BackgroundGeolocation.getCurrentPosition(
          samples: 1,
          persist: true,
          extras: {'source': 'heartbeat'},
        );

        final point = TrackingPoint.fromBgLocation(location);
        _lastPoint = point;
        _isMoving = location.isMoving;

        if (!_locationController.isClosed) {
          _locationController.add(point);
        }
      } catch (_) {}

      await _emitStatus();
    });

    bg.BackgroundGeolocation.onConnectivityChange((
      bg.ConnectivityChangeEvent event,
    ) async {
      await _emitStatus();
    });

    bg.BackgroundGeolocation.onEnabledChange((bool enabled) async {
      await _emitStatus();
    });

    await bg.BackgroundGeolocation.ready(
      bg.Config(
        geolocation: bg.GeoConfig(
          desiredAccuracy: bg.DesiredAccuracy.high,
          distanceFilter: 10.0,
          stopTimeout: 2,
          locationAuthorizationRequest: 'Always',
          pausesLocationUpdatesAutomatically: false,
          showsBackgroundLocationIndicator: true,
        ),
        activity: bg.ActivityConfig(
          minimumActivityRecognitionConfidence: 70,
          disableStopDetection: false,
          motionTriggerDelay: 10000,
        ),
        app: bg.AppConfig(
          stopOnTerminate: false,
          startOnBoot: true,
          heartbeatInterval: 60,
          preventSuspend: true,
          enableHeadless: true,
        ),
        persistence: bg.PersistenceConfig(
          persistMode: bg.PersistMode.all,
          maxDaysToPersist: 7,
          extras: {'module': 'delivery-demo'},
        ),
        http: bg.HttpConfig(
          method: 'POST',
          autoSync: false,
          batchSync: false,
          headers: {'Content-Type': 'application/json'},
        ),
        logger: bg.LoggerConfig(
          debug: true,
          logLevel: bg.LogLevel.verbose,
          logMaxDays: 3,
        ),
      ),
    );

    await _restoreTrackingSession();

    _initialized = true;
    await _emitStatus();
  }

  Future<void> startTracking({required String sessionId}) async {
    _currentSessionId = sessionId;
    _sessionRestored = false;
    await _persistCurrentSessionId(sessionId);

    await bg.BackgroundGeolocation.setConfig(
      bg.Config(
        persistence: bg.PersistenceConfig(
          extras: {'sessionId': sessionId, 'type': 'delivery-driver'},
        ),
        http: bg.HttpConfig(params: {'sessionId': sessionId}),
      ),
    );

    final firstPoint = await getCurrentPosition();

    if (firstPoint != null) {
      await TrackingRepository.instance.createSession(
        sessionId: sessionId,
        driverId: 'driver-demo-001',
        startLat: firstPoint.latitude,
        startLng: firstPoint.longitude,
        meta: {'source': 'flutter_background_geolocation'},
      );
    }

    await bg.BackgroundGeolocation.start();
    await _emitStatus();
  }

  String generateSessionId() {
    final randomValue = Random.secure().nextInt(1 << 32);
    final timestamp = DateTime.now().toUtc().microsecondsSinceEpoch;
    return 'tracking-$timestamp-${randomValue.toRadixString(16)}';
  }

  Future<void> stopTracking() async {
    await bg.BackgroundGeolocation.stop();

    if (_currentSessionId != null && _lastPoint != null) {
      await TrackingRepository.instance.closeSession(
        sessionId: _currentSessionId!,
        endLat: _lastPoint!.latitude,
        endLng: _lastPoint!.longitude,
        meta: {'closed_from': 'app_stop'},
      );
    }

    _currentSessionId = null;
    await _clearPersistedSessionId();
    await _emitStatus();
  }

  Future<bool> isTracking() async {
    final state = await bg.BackgroundGeolocation.state;
    return state.enabled;
  }

  Future<void> forceMoving(bool value) async {
    await bg.BackgroundGeolocation.changePace(value);
    _isMoving = value;
    await _emitStatus();
  }

  Future<TrackingPoint?> getCurrentPosition() async {
    try {
      final location = await bg.BackgroundGeolocation.getCurrentPosition(
        samples: 1,
        persist: true,
        extras: {'source': 'manual_request'},
      );

      final point = TrackingPoint.fromBgLocation(location);
      _lastPoint = point;
      _isMoving = location.isMoving;

      if (!_locationController.isClosed) {
        _locationController.add(point);
      }

      await _emitStatus();
      return point;
    } catch (_) {
      await _emitStatus();
      return null;
    }
  }

  Future<List<TrackingPoint>> getStoredLocations() async {
    final rows = await bg.BackgroundGeolocation.locations;

    return rows.map((row) {
      final data = Map<String, dynamic>.from(row);

      final coords = data['coords'] != null
          ? Map<String, dynamic>.from(data['coords'])
          : <String, dynamic>{};

      return TrackingPoint(
        latitude: (coords['latitude'] as num).toDouble(),
        longitude: (coords['longitude'] as num).toDouble(),
        accuracy: (coords['accuracy'] as num?)?.toDouble(),
        speed: (coords['speed'] as num?)?.toDouble(),
        heading: (coords['heading'] as num?)?.toDouble(),
        timestamp:
            DateTime.tryParse(data['timestamp']?.toString() ?? '') ??
            DateTime.now(),
        isMoving: data['is_moving'] as bool?,
        extras: data['extras'] != null
            ? Map<String, dynamic>.from(data['extras'])
            : null,
      );
    }).toList();
  }

  Future<int> getStoredCount() async {
    return await bg.BackgroundGeolocation.count;
  }

  Future<List<dynamic>> syncNow() async {
    final result = await bg.BackgroundGeolocation.sync();
    await _emitStatus();
    return result;
  }

  Future<void> addDemoGeofence({
    required String identifier,
    required double latitude,
    required double longitude,
    double radius = 120,
  }) async {
    await bg.BackgroundGeolocation.addGeofence(
      bg.Geofence(
        identifier: identifier,
        radius: radius,
        latitude: latitude,
        longitude: longitude,
        notifyOnEntry: true,
        notifyOnExit: true,
        notifyOnDwell: true,
        loiteringDelay: 30000,
        extras: {'type': 'demo-geofence'},
      ),
    );
  }

  Future<TrackingStatusSnapshot> getStatusSnapshot() async {
    final enabled = await isTracking();
    final storedCount = await getStoredCount();

    return TrackingStatusSnapshot(
      enabled: enabled,
      activity: _lastActivity,
      isMoving: _isMoving,
      storedCount: storedCount,
      lastPoint: _lastPoint,
    );
  }

  Future<void> _emitStatus() async {
    if (_statusController.isClosed) return;

    final snapshot = await getStatusSnapshot();
    _statusController.add(snapshot);
  }

  Future<void> dispose() async {
    await bg.BackgroundGeolocation.removeListeners();
    await _locationController.close();
    await _statusController.close();
  }

  Future<void> _restoreTrackingSession() async {
    final prefs = await SharedPreferences.getInstance();
    final persistedSessionId = prefs.getString(_activeSessionStorageKey);
    final state = await bg.BackgroundGeolocation.state;

    if (state.enabled && persistedSessionId != null && persistedSessionId.isNotEmpty) {
      _currentSessionId = persistedSessionId;
      _sessionRestored = true;
      final point = await getCurrentPosition();
      if (point != null) {
        _lastPoint = point;
      }
      return;
    }

    if (!state.enabled) {
      _sessionRestored = false;
      await _clearPersistedSessionId();
    }
  }

  Future<void> _persistCurrentSessionId(String sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeSessionStorageKey, sessionId);
  }

  Future<void> _clearPersistedSessionId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_activeSessionStorageKey);
  }
}
