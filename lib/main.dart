import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'background_tracking/data/service/background_tracking_service.dart';
import 'background_tracking/presentation/screens/driver_screen.dart';
import 'background_tracking/presentation/screens/viewer_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'TU_SUPABASE_URL',
    anonKey: 'TU_SUPABASE_ANON_KEY',
  );

  await BackgroundTrackingService.instance.init();
  runApp(const RastreoDemoApp());
}

/// BUS "REALTIME" con último valor
class LocationBus {
  LocationBus._();
  static final LocationBus instance = LocationBus._();

  final StreamController<LatLng> _controller =
      StreamController<LatLng>.broadcast();

  LatLng? _last;

  Stream<LatLng> get stream => _controller.stream;
  LatLng? get last => _last;

  void emit(LatLng location) {
    _last = location;
    if (!_controller.isClosed) {
      _controller.add(location);
    }
  }

  Future<void> dispose() async {
    await _controller.close();
  }
}

/// Puente entre flutter_background_geolocation y el bus local
class TrackingBridge {
  TrackingBridge._();
  static final TrackingBridge instance = TrackingBridge._();

  StreamSubscription<TrackingPoint>? _sub;

  void start() {
    _sub ??= BackgroundTrackingService.instance.stream.listen((point) {
      LocationBus.instance.emit(LatLng(point.latitude, point.longitude));
    });
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }
}

/// Ruta demo / real para pintar referencia en el mapa
class DemoRoute {
  DemoRoute._();

  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static LatLng pointA = const LatLng(
    14.5876983794952,
    -90.51379445428621,
  ); // EUROPLAZA

  static LatLng pointB = const LatLng(
    14.584228945836376,
    -90.51422506734473,
  ); // DÉCIMA PLAZA

  static List<LatLng> points = <LatLng>[pointA, pointB];

  static void setPointA(LatLng value) {
    pointA = value;
    _rebuildPoints();
  }

  static void setPointB(LatLng value) {
    pointB = value;
    _rebuildPoints();
  }

  static void setFromCurrent({LatLng? pointAValue, LatLng? pointBValue}) {
    if (pointAValue != null) pointA = pointAValue;
    if (pointBValue != null) pointB = pointBValue;
    _rebuildPoints();
  }

  static void _rebuildPoints() {
    points = <LatLng>[pointA, pointB];
    revision.value++;
  }
}

class RastreoDemoApp extends StatelessWidget {
  const RastreoDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rastreo Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.green),
      home: const HomeTabs(),
    );
  }
}

class HomeTabs extends StatefulWidget {
  const HomeTabs({super.key});

  @override
  State<HomeTabs> createState() => _HomeTabsState();
}

class _HomeTabsState extends State<HomeTabs> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    TrackingBridge.instance.start();
  }

  @override
  void dispose() {
    TrackingBridge.instance.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[const DriverScreen(), const ViewerScreen()];

    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.delivery_dining),
            label: 'Driver',
          ),
          NavigationDestination(icon: Icon(Icons.map), label: 'Viewer'),
        ],
      ),
    );
  }
}
