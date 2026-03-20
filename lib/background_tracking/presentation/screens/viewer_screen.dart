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
  bool _loadingSessions = true;
  String? _selectedSessionId;
  List<Map<String, dynamic>> _sessions = const [];

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
      await _loadSessions();
      await _loadSelectedSession();

      if (mounted) {
        _fitToFullRoute();
      }
    });
  }

  Future<void> _loadSessions() async {
    try {
      final sessions = await TrackingRepository.instance.listSessions();

      if (!mounted) return;

      setState(() {
        _sessions = sessions;
        _selectedSessionId = sessions.isNotEmpty
            ? sessions.first['session_id']?.toString()
            : null;
        _loadingSessions = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loadingSessions = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudieron cargar sesiones: $e')),
      );
    }
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

  Future<void> _loadSelectedSession() async {
    final sessionId = _selectedSessionId;
    if (sessionId == null) {
      if (!mounted) return;

      setState(() {
        _trail
          ..clear()
          ..add(_current);
        _loadingRemote = false;
        _realtimeConnected = false;
        _dataSource = 'local';
      });
      return;
    }

    setState(() {
      _loadingRemote = true;
      _realtimeConnected = false;
      _trail.clear();
    });

    try {
      final rows = await TrackingRepository.instance.getPointsBySession(
        sessionId,
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
          _dataSource = 'remote';
          _trail
            ..clear()
            ..add(_current);
        });
      }

      _listenRealtime();
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
    final sessionId = _selectedSessionId;
    if (sessionId == null) return;

    TrackingRealtimeService.instance.subscribeToSessionPoints(
      sessionId: sessionId,
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
    final status = _loadingSessions
        ? 'Viewer: cargando sesiones...'
        : _selectedSessionId == null
        ? 'Viewer: sin session seleccionada'
        : _loadingRemote
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
      body: Stack(
        children: [
          Positioned.fill(
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
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: _ViewerOverlayCard(
              status: status,
              current: _current,
              selectedSessionId: _selectedSessionId,
              sessions: _sessions,
              loadingSessions: _loadingSessions,
              trailLength: _trail.length,
              lastUpdateText: _lastUpdateText(),
              autoFollowViewer: _autoFollowViewer,
              realtimeConnected: _realtimeConnected,
              dataSource: _dataSource,
              pointA: DemoRoute.pointA,
              pointB: DemoRoute.pointB,
              onSessionChanged: (value) async {
                if (value == null || value == _selectedSessionId) {
                  return;
                }

                setState(() {
                  _selectedSessionId = value;
                });

                await _loadSelectedSession();

                if (mounted) {
                  _fitToFullRoute();
                }
              },
              onRefresh: () async {
                setState(() {
                  _loadingSessions = true;
                });

                await _loadSessions();
                await _loadSelectedSession();

                if (mounted) {
                  _fitToFullRoute();
                }
              },
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  FilledButton.icon(
                    onPressed: _fitToFullRoute,
                    icon: const Icon(Icons.route),
                    label: const Text('Ruta completa'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _centerOnViewer,
                    icon: const Icon(Icons.my_location),
                    label: const Text('Ir al viewer'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _toggleAutoFollow,
                    icon: Icon(
                      _autoFollowViewer ? Icons.gps_fixed : Icons.gps_not_fixed,
                    ),
                    label: Text(
                      _autoFollowViewer ? 'Auto-follow ON' : 'Auto-follow OFF',
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _clearTrail,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Limpiar trail'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ViewerOverlayCard extends StatelessWidget {
  const _ViewerOverlayCard({
    required this.status,
    required this.current,
    required this.selectedSessionId,
    required this.sessions,
    required this.loadingSessions,
    required this.trailLength,
    required this.lastUpdateText,
    required this.autoFollowViewer,
    required this.realtimeConnected,
    required this.dataSource,
    required this.pointA,
    required this.pointB,
    required this.onSessionChanged,
    required this.onRefresh,
  });

  final String status;
  final LatLng current;
  final String? selectedSessionId;
  final List<Map<String, dynamic>> sessions;
  final bool loadingSessions;
  final int trailLength;
  final String lastUpdateText;
  final bool autoFollowViewer;
  final bool realtimeConnected;
  final String dataSource;
  final LatLng pointA;
  final LatLng pointB;
  final Future<void> Function(String? value) onSessionChanged;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final lat = current.latitude.toStringAsFixed(6);
    final lng = current.longitude.toStringAsFixed(6);

    return Card(
      elevation: 10,
      color: Colors.white.withOpacity(0.94),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
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
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: selectedSessionId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Session',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: sessions.map((session) {
                      final sessionId = session['session_id']?.toString() ?? '';
                      final status = session['status']?.toString() ?? '-';
                      return DropdownMenuItem<String>(
                        value: sessionId,
                        child: Text('$sessionId ($status)'),
                      );
                    }).toList(),
                    onChanged: loadingSessions
                        ? null
                        : (value) async {
                            await onSessionChanged(value);
                          },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Recargar sesiones',
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  avatar: const Icon(Icons.route, size: 18),
                  label: Text('Trail: $trailLength'),
                ),
                Chip(
                  avatar: const Icon(Icons.access_time, size: 18),
                  label: Text('Ultima: $lastUpdateText'),
                ),
                Chip(
                  avatar: Icon(
                    autoFollowViewer ? Icons.gps_fixed : Icons.gps_not_fixed,
                    size: 18,
                  ),
                  label: Text(
                    autoFollowViewer ? 'Auto-follow ON' : 'Auto-follow OFF',
                  ),
                ),
                Chip(
                  avatar: Icon(
                    realtimeConnected ? Icons.cloud_done : Icons.cloud_off,
                    size: 18,
                  ),
                  label: Text(
                    realtimeConnected ? 'Realtime ON' : 'Realtime OFF',
                  ),
                ),
                Chip(
                  avatar: const Icon(Icons.storage, size: 18),
                  label: Text('Source: $dataSource'),
                ),
                Chip(
                  avatar: const Icon(Icons.tag, size: 18),
                  label: Text('Session: ${selectedSessionId ?? '-'}'),
                ),
                Chip(
                  avatar: const Icon(Icons.flag, size: 18),
                  label: Text(
                    'A ${pointA.latitude.toStringAsFixed(5)}, ${pointA.longitude.toStringAsFixed(5)}',
                  ),
                ),
                Chip(
                  avatar: const Icon(Icons.place, size: 18),
                  label: Text(
                    'B ${pointB.latitude.toStringAsFixed(5)}, ${pointB.longitude.toStringAsFixed(5)}',
                  ),
                ),
              ],
            ),
          ],
        ),
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
