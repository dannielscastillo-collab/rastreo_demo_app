import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../main.dart';
import '../../data/service/background_tracking_service.dart';

class DriverScreen extends StatefulWidget {
  const DriverScreen({super.key});

  @override
  State<DriverScreen> createState() => _DriverScreenState();
}

class _DriverScreenState extends State<DriverScreen> {
  final MapController _mapController = MapController();

  StreamSubscription<TrackingPoint>? _locationSub;
  StreamSubscription<TrackingStatusSnapshot>? _statusSub;
  VoidCallback? _routeListener;

  bool _running = false;
  bool _loading = true;
  bool _autoFollowDriver = true;

  double _zoom = 15;
  LatLng _current = DemoRoute.points.first;
  final List<LatLng> _trail = <LatLng>[DemoRoute.points.first];

  String _activity = 'unknown';
  bool _isMoving = false;
  int _storedCount = 0;
  String _lastSyncText = 'Sin sync';
  double? _accuracy;
  double? _speed;
  double? _heading;
  DateTime? _lastUpdate;

  @override
  void initState() {
    super.initState();

    LocationBus.instance.emit(_current);

    _routeListener = () {
      if (!mounted) return;
      setState(() {});
    };
    DemoRoute.revision.addListener(_routeListener!);

    _locationSub = BackgroundTrackingService.instance.stream.listen((point) {
      if (!mounted) return;

      final latLng = point.toLatLng();

      setState(() {
        _current = latLng;
        _accuracy = point.accuracy;
        _speed = point.speed;
        _heading = point.heading;
        _lastUpdate = point.timestamp;

        if (_trail.isEmpty || _trail.last != latLng) {
          _trail.add(latLng);
        }
      });

      LocationBus.instance.emit(latLng);

      if (_autoFollowDriver) {
        _mapController.move(latLng, _zoom);
      }
    });

    _statusSub = BackgroundTrackingService.instance.statusStream.listen((
      status,
    ) {
      if (!mounted) return;

      setState(() {
        _running = status.enabled;
        _activity = status.activity;
        _isMoving = status.isMoving;
        _storedCount = status.storedCount;
      });
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _bootstrap();
    });
  }

  Future<void> _bootstrap() async {
    final snapshot = await BackgroundTrackingService.instance
        .getStatusSnapshot();
    final currentPoint = await BackgroundTrackingService.instance
        .getCurrentPosition();

    if (!mounted) return;

    setState(() {
      _running = snapshot.enabled;
      _activity = snapshot.activity;
      _isMoving = snapshot.isMoving;
      _storedCount = snapshot.storedCount;
      _loading = false;

      if (currentPoint != null) {
        _current = currentPoint.toLatLng();
        _accuracy = currentPoint.accuracy;
        _speed = currentPoint.speed;
        _heading = currentPoint.heading;
        _lastUpdate = currentPoint.timestamp;
        _trail
          ..clear()
          ..add(_current);
      }
    });

    LocationBus.instance.emit(_current);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fitToFullRoute();
    });
  }

  Future<void> _start() async {
    setState(() => _loading = true);

    try {
      await BackgroundTrackingService.instance.startTracking(
        sessionId: 'demo-delivery-001',
      );

      final point = await BackgroundTrackingService.instance
          .getCurrentPosition();

      if (!mounted) return;

      setState(() {
        _running = true;
        _loading = false;

        if (point != null) {
          _current = point.toLatLng();
          _accuracy = point.accuracy;
          _speed = point.speed;
          _heading = point.heading;
          _lastUpdate = point.timestamp;
          _trail
            ..clear()
            ..add(_current);
        }
      });

      LocationBus.instance.emit(_current);

      if (_autoFollowDriver) {
        _mapController.move(_current, _zoom);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al iniciar tracking: $e')));
    }
  }

  Future<void> _stop() async {
    setState(() => _loading = true);

    try {
      await BackgroundTrackingService.instance.stopTracking();

      if (!mounted) return;

      setState(() {
        _running = false;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al detener tracking: $e')));
    }
  }

  Future<void> _syncNow() async {
    try {
      final result = await BackgroundTrackingService.instance.syncNow();
      if (!mounted) return;

      setState(() {
        _lastSyncText = 'Sync OK (${result.length})';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sync ejecutado. Registros enviados: ${result.length}'),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _lastSyncText = 'Sync error';
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al sincronizar: $e')));
    }
  }

  Future<void> _forceMoving() async {
    await BackgroundTrackingService.instance.forceMoving(true);
  }

  Future<void> _addDemoGeofence() async {
    try {
      await BackgroundTrackingService.instance.addDemoGeofence(
        identifier: 'dropoff-demo',
        latitude: DemoRoute.pointB.latitude,
        longitude: DemoRoute.pointB.longitude,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Geofence demo agregada en punto B')),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error agregando geofence: $e')));
    }
  }

  Future<void> _setCurrentAsPointA() async {
    try {
      final point = await BackgroundTrackingService.instance
          .getCurrentPosition();
      if (!mounted || point == null) return;

      final latLng = point.toLatLng();

      setState(() {
        DemoRoute.setPointA(latLng);
      });

      _fitToFullRoute();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Punto A actualizado: '
            '${latLng.latitude.toStringAsFixed(6)}, '
            '${latLng.longitude.toStringAsFixed(6)}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error actualizando Punto A: $e')));
    }
  }

  Future<void> _setCurrentAsPointB() async {
    try {
      final point = await BackgroundTrackingService.instance
          .getCurrentPosition();
      if (!mounted || point == null) return;

      final latLng = point.toLatLng();

      setState(() {
        DemoRoute.setPointB(latLng);
      });

      _fitToFullRoute();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Punto B actualizado: '
            '${latLng.latitude.toStringAsFixed(6)}, '
            '${latLng.longitude.toStringAsFixed(6)}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error actualizando Punto B: $e')));
    }
  }

  void _fitToFullRoute() {
    final points = <LatLng>[
      DemoRoute.pointA,
      DemoRoute.pointB,
      ...DemoRoute.points,
      ..._trail,
      _current,
    ];

    final bounds = LatLngBounds.fromPoints(points);

    _mapController.fitBounds(
      bounds,
      options: const FitBoundsOptions(padding: EdgeInsets.all(60)),
    );
  }

  void _centerOnDriver() {
    _mapController.move(_current, _zoom);
  }

  void _toggleAutoFollow() {
    setState(() {
      _autoFollowDriver = !_autoFollowDriver;
    });
  }

  void _showActionsSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            child: Wrap(
              runSpacing: 10,
              children: [
                ListTile(
                  leading: const Icon(Icons.my_location),
                  title: const Text('Usar ubicación actual como Punto A'),
                  subtitle: Text(
                    '${DemoRoute.pointA.latitude.toStringAsFixed(6)}, '
                    '${DemoRoute.pointA.longitude.toStringAsFixed(6)}',
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _setCurrentAsPointA();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.location_on),
                  title: const Text('Usar ubicación actual como Punto B'),
                  subtitle: Text(
                    '${DemoRoute.pointB.latitude.toStringAsFixed(6)}, '
                    '${DemoRoute.pointB.longitude.toStringAsFixed(6)}',
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _setCurrentAsPointB();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.route),
                  title: const Text('Ver ruta completa'),
                  onTap: () {
                    Navigator.pop(context);
                    _fitToFullRoute();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.my_location),
                  title: const Text('Ir al driver'),
                  onTap: () {
                    Navigator.pop(context);
                    _centerOnDriver();
                  },
                ),
                ListTile(
                  leading: Icon(
                    _autoFollowDriver ? Icons.gps_fixed : Icons.gps_not_fixed,
                  ),
                  title: Text(
                    _autoFollowDriver
                        ? 'Desactivar auto-follow'
                        : 'Activar auto-follow',
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _toggleAutoFollow();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.sync),
                  title: const Text('Sync'),
                  onTap: () {
                    Navigator.pop(context);
                    _syncNow();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.directions_run),
                  title: const Text('Force Moving'),
                  onTap: () {
                    Navigator.pop(context);
                    _forceMoving();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.pin_drop),
                  title: const Text('Geofence B'),
                  onTap: () {
                    Navigator.pop(context);
                    _addDemoGeofence();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatDouble(
    double? value, {
    int decimals = 2,
    String fallback = '-',
  }) {
    if (value == null) return fallback;
    return value.toStringAsFixed(decimals);
  }

  String _formatLastUpdate() {
    if (_lastUpdate == null) return '-';
    final dt = _lastUpdate!;
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}:'
        '${dt.second.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _locationSub?.cancel();
    _statusSub?.cancel();
    if (_routeListener != null) {
      DemoRoute.revision.removeListener(_routeListener!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final statusText = _loading
        ? 'Cargando tracking...'
        : _running
        ? 'Tracking real activo'
        : 'Tracking detenido';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Driver'),
        actions: [
          IconButton(
            tooltip: 'Ver ruta completa',
            onPressed: _fitToFullRoute,
            icon: const Icon(Icons.route),
          ),
          IconButton(
            tooltip: 'Más acciones',
            onPressed: _showActionsSheet,
            icon: const Icon(Icons.more_vert),
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              center: _current,
              zoom: _zoom,
              onPositionChanged: (pos, hasGesture) {
                final z = pos.zoom;
                if (z != null) _zoom = z;

                if (hasGesture && _autoFollowDriver) {
                  setState(() {
                    _autoFollowDriver = false;
                  });
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.rastreo_app',
              ),
              PolylineLayer(
                polylines: [Polyline(points: DemoRoute.points, strokeWidth: 4)],
              ),
              PolylineLayer(
                polylines: [Polyline(points: _trail, strokeWidth: 6)],
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: DemoRoute.pointA,
                    width: 90,
                    height: 72,
                    builder: (_) => const _CompactMarker(
                      icon: Icons.flag,
                      label: 'A',
                      iconColor: Colors.red,
                    ),
                  ),
                  Marker(
                    point: DemoRoute.pointB,
                    width: 90,
                    height: 72,
                    builder: (_) => const _CompactMarker(
                      icon: Icons.place,
                      label: 'B',
                      iconColor: Colors.blue,
                    ),
                  ),
                  Marker(
                    point: _current,
                    width: 100,
                    height: 78,
                    builder: (_) => const _CompactMarker(
                      icon: Icons.delivery_dining,
                      label: 'Driver',
                      iconColor: Colors.green,
                    ),
                  ),
                ],
              ),
            ],
          ),
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: _DriverInfoCard(
              statusText: statusText,
              isMoving: _isMoving,
              activity: _activity,
              storedCount: _storedCount,
              accuracy: _formatDouble(_accuracy),
              speed: _formatDouble(_speed),
              update: _formatLastUpdate(),
              autoFollowDriver: _autoFollowDriver,
              pointA: DemoRoute.pointA,
              pointB: DemoRoute.pointB,
            ),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
            heroTag: 'center_driver',
            onPressed: _centerOnDriver,
            child: const Icon(Icons.my_location),
          ),
          const SizedBox(height: 10),
          FloatingActionButton.extended(
            heroTag: 'start_stop_driver',
            onPressed: _loading ? null : (_running ? _stop : _start),
            icon: Icon(_running ? Icons.stop : Icons.play_arrow),
            label: Text(_running ? 'Detener' : 'Iniciar'),
          ),
        ],
      ),
    );
  }
}

class _DriverInfoCard extends StatelessWidget {
  const _DriverInfoCard({
    required this.statusText,
    required this.isMoving,
    required this.activity,
    required this.storedCount,
    required this.accuracy,
    required this.speed,
    required this.update,
    required this.autoFollowDriver,
    required this.pointA,
    required this.pointB,
  });

  final String statusText;
  final bool isMoving;
  final String activity;
  final int storedCount;
  final String accuracy;
  final String speed;
  final String update;
  final bool autoFollowDriver;
  final LatLng pointA;
  final LatLng pointB;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 6,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              statusText,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MiniChip(
                  icon: Icons.motion_photos_auto,
                  label: isMoving ? 'Moving' : 'Stationary',
                ),
                _MiniChip(icon: Icons.directions_car, label: activity),
                _MiniChip(icon: Icons.storage, label: 'Stored $storedCount'),
                _MiniChip(icon: Icons.gps_fixed, label: 'Acc $accuracy m'),
                _MiniChip(icon: Icons.speed, label: 'Speed $speed'),
                _MiniChip(icon: Icons.access_time, label: update),
                _MiniChip(
                  icon: autoFollowDriver
                      ? Icons.gps_fixed
                      : Icons.gps_not_fixed,
                  label: autoFollowDriver ? 'Follow ON' : 'Follow OFF',
                ),
                _MiniChip(
                  icon: Icons.flag,
                  label:
                      'A ${pointA.latitude.toStringAsFixed(5)}, ${pointA.longitude.toStringAsFixed(5)}',
                ),
                _MiniChip(
                  icon: Icons.place,
                  label:
                      'B ${pointB.latitude.toStringAsFixed(5)}, ${pointB.longitude.toStringAsFixed(5)}',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _CompactMarker extends StatelessWidget {
  const _CompactMarker({
    required this.icon,
    required this.label,
    this.iconColor,
  });

  final IconData icon;
  final String label;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            boxShadow: const [BoxShadow(blurRadius: 6, color: Colors.black12)],
          ),
          child: Text(
            label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 4),
        Icon(icon, size: 38, color: iconColor),
      ],
    );
  }
}
