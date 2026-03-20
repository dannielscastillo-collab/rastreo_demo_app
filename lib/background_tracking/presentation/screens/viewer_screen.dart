import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../main.dart';
import '../../data/service/tracking_realtime_service.dart';
import '../../data/service/tracking_repository.dart';

class ViewerScreen extends StatefulWidget {
  const ViewerScreen({super.key});

  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends State<ViewerScreen> {
  static const String _sessionId = 'demo-delivery-001';

  final MapController _mapController = MapController();

  StreamSubscription<LatLng>? _sub;
  VoidCallback? _routeListener;

  LatLng _current = DemoRoute.points.first;
  double _zoom = 15;
  final List<LatLng> _trail = <LatLng>[DemoRoute.points.first];
  DateTime? _lastReceivedAt;

  bool _autoFollowViewer = true;
  bool _loadingRemote = true;
  bool _realtimeConnected = false;
  String _dataSource = 'remote';

  @override
  void initState() {
    super.initState();

    final last = LocationBus.instance.last;
    if (last != null) {
      _current = last;
      _trail
        ..clear()
        ..add(last);
    }

    _routeListener = () {
      if (!mounted) return;
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _fitToFullRoute();
        }
      });
    };
    DemoRoute.revision.addListener(_routeListener!);

    _listenLocalFallback();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadInitialPoints();
      _listenRealtime();

      if (mounted) {
        _fitToFullRoute();
      }
    });
  }

  void _listenLocalFallback() {
    _sub = LocationBus.instance.stream.listen((loc) {
      if (!mounted) return;

      setState(() {
        _current = loc;
        _lastReceivedAt = DateTime.now();

        if (_trail.isEmpty || _trail.last != loc) {
          _trail.add(loc);
        }
      });

      if (_autoFollowViewer) {
        _mapController.move(loc, _zoom);
      }
    });
  }

  Future<void> _loadInitialPoints() async {
    try {
      final rows = await TrackingRepository.instance.getPointsBySession(
        _sessionId,
      );

      if (!mounted) return;

      if (rows.isNotEmpty) {
        final remotePoints = rows.map((row) {
          return LatLng(
            (row['latitude'] as num).toDouble(),
            (row['longitude'] as num).toDouble(),
          );
        }).toList();

        setState(() {
          _trail
            ..clear()
            ..addAll(remotePoints);
          _current = remotePoints.last;
          _lastReceivedAt = DateTime.now();
          _dataSource = 'remote';
          _loadingRemote = false;
        });

        _mapController.move(_current, _zoom);
      } else {
        setState(() {
          _loadingRemote = false;
        });
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loadingRemote = false;
        _dataSource = 'local';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo cargar historial remoto: $e')),
      );
    }
  }

  void _listenRealtime() {
    TrackingRealtimeService.instance.subscribeToSessionPoints(
      sessionId: _sessionId,
      onInsert: (row) {
        if (!mounted) return;

        final point = LatLng(
          (row['latitude'] as num).toDouble(),
          (row['longitude'] as num).toDouble(),
        );

        setState(() {
          _current = point;
          _lastReceivedAt = DateTime.now();
          _realtimeConnected = true;
          _dataSource = 'remote';

          if (_trail.isEmpty || _trail.last != point) {
            _trail.add(point);
          }
        });

        if (_autoFollowViewer) {
          _mapController.move(point, _zoom);
        }
      },
      onUpdate: (row) {},
      onSubscribed: () {
        if (!mounted) return;

        setState(() {
          _realtimeConnected = true;
        });
      },
      onError: (error) {
        if (!mounted) return;

        setState(() {
          _realtimeConnected = false;
        });

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Realtime error: $error')));
      },
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    TrackingRealtimeService.instance.dispose();

    if (_routeListener != null) {
      DemoRoute.revision.removeListener(_routeListener!);
    }

    super.dispose();
  }

  void _clearTrail() {
    setState(() {
      _trail
        ..clear()
        ..add(_current);
    });
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

  void _centerOnViewer() {
    _mapController.move(_current, _zoom);
  }

  void _toggleAutoFollow() {
    setState(() {
      _autoFollowViewer = !_autoFollowViewer;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _autoFollowViewer
              ? 'Auto-follow activado'
              : 'Auto-follow desactivado',
        ),
      ),
    );
  }

  String _lastUpdateText() {
    if (_lastReceivedAt == null) return '-';
    final dt = _lastReceivedAt!;
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}:'
        '${dt.second.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final status = _loadingRemote
        ? 'Viewer: cargando historial remoto...'
        : _realtimeConnected
        ? 'Viewer: realtime Supabase activo'
        : 'Viewer: escuchando fallback/local';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Viewer (Tiempo real)'),
        actions: [
          IconButton(
            tooltip: 'Ver ruta completa',
            onPressed: _fitToFullRoute,
            icon: const Icon(Icons.route),
          ),
          IconButton(
            tooltip: _autoFollowViewer
                ? 'Desactivar auto-follow'
                : 'Activar auto-follow',
            onPressed: _toggleAutoFollow,
            icon: Icon(
              _autoFollowViewer ? Icons.gps_fixed : Icons.gps_not_fixed,
            ),
          ),
          IconButton(
            tooltip: 'Ir al viewer',
            onPressed: _centerOnViewer,
            icon: const Icon(Icons.my_location),
          ),
          IconButton(
            tooltip: 'Limpiar ruta recorrida',
            onPressed: _clearTrail,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: Column(
        children: [
          _TopBar(status: status, current: _current),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  avatar: const Icon(Icons.route, size: 18),
                  label: Text('Trail points: ${_trail.length}'),
                ),
                Chip(
                  avatar: const Icon(Icons.access_time, size: 18),
                  label: Text('Última señal: ${_lastUpdateText()}'),
                ),
                Chip(
                  avatar: Icon(
                    _autoFollowViewer ? Icons.gps_fixed : Icons.gps_not_fixed,
                    size: 18,
                  ),
                  label: Text(
                    _autoFollowViewer ? 'Auto-follow ON' : 'Auto-follow OFF',
                  ),
                ),
                Chip(
                  avatar: Icon(
                    _realtimeConnected ? Icons.cloud_done : Icons.cloud_off,
                    size: 18,
                  ),
                  label: Text(
                    _realtimeConnected ? 'Realtime ON' : 'Realtime OFF',
                  ),
                ),
                Chip(
                  avatar: const Icon(Icons.storage, size: 18),
                  label: Text('Source: $_dataSource'),
                ),
                Chip(
                  avatar: const Icon(Icons.flag, size: 18),
                  label: Text(
                    'A ${DemoRoute.pointA.latitude.toStringAsFixed(5)}, ${DemoRoute.pointA.longitude.toStringAsFixed(5)}',
                  ),
                ),
                Chip(
                  avatar: const Icon(Icons.place, size: 18),
                  label: Text(
                    'B ${DemoRoute.pointB.latitude.toStringAsFixed(5)}, ${DemoRoute.pointB.longitude.toStringAsFixed(5)}',
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                center: _current,
                zoom: _zoom,
                onPositionChanged: (pos, hasGesture) {
                  final z = pos.zoom;
                  if (z != null) _zoom = z;

                  if (hasGesture && _autoFollowViewer) {
                    setState(() {
                      _autoFollowViewer = false;
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
                  polylines: [
                    Polyline(points: DemoRoute.points, strokeWidth: 4),
                  ],
                ),
                PolylineLayer(
                  polylines: [Polyline(points: _trail, strokeWidth: 6)],
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: DemoRoute.pointA,
                      width: 100,
                      height: 80,
                      builder: (_) => const _LabeledMarker(
                        icon: Icons.flag,
                        label: 'A',
                        iconColor: Colors.red,
                      ),
                    ),
                    Marker(
                      point: DemoRoute.pointB,
                      width: 100,
                      height: 80,
                      builder: (_) => const _LabeledMarker(
                        icon: Icons.place,
                        label: 'B',
                        iconColor: Colors.blue,
                      ),
                    ),
                    Marker(
                      point: _current,
                      width: 110,
                      height: 85,
                      builder: (_) => const _LabeledMarker(
                        icon: Icons.person_pin_circle,
                        label: 'Viewer',
                        iconColor: Colors.green,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: _fitToFullRoute,
                  icon: const Icon(Icons.route),
                  label: const Text('Ver ruta completa'),
                ),
                OutlinedButton.icon(
                  onPressed: _centerOnViewer,
                  icon: const Icon(Icons.my_location),
                  label: const Text('Ir al viewer'),
                ),
                OutlinedButton.icon(
                  onPressed: _toggleAutoFollow,
                  icon: Icon(
                    _autoFollowViewer ? Icons.gps_fixed : Icons.gps_not_fixed,
                  ),
                  label: Text(
                    _autoFollowViewer ? 'Auto-follow ON' : 'Auto-follow OFF',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _clearTrail,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Limpiar trail'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.status, required this.current});

  final String status;
  final LatLng current;

  @override
  Widget build(BuildContext context) {
    final lat = current.latitude.toStringAsFixed(6);
    final lng = current.longitude.toStringAsFixed(6);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Row(
        children: [
          const Icon(Icons.info_outline),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$status\nLat: $lat  Lng: $lng',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _LabeledMarker extends StatelessWidget {
  const _LabeledMarker({
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
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            boxShadow: const [BoxShadow(blurRadius: 6, color: Colors.black12)],
          ),
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 4),
        Icon(icon, size: 42, color: iconColor),
      ],
    );
  }
}
