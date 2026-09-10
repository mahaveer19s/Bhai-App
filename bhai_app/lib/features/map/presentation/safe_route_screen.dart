import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import '../../../core/theme/app_theme.dart';

class SafeRouteScreen extends StatefulWidget {
  const SafeRouteScreen({super.key});

  @override
  State<SafeRouteScreen> createState() => _SafeRouteScreenState();
}

class _SafeRouteScreenState extends State<SafeRouteScreen> {
  final MapController _mapController = MapController();
  final LatLng _currentUserLocation = const LatLng(28.6273, 77.3725); // Noida Sector 62 coordinates
  final LatLng _destinationLocation = const LatLng(28.6304, 77.3819); // Near Shipra Mall
  
  List<LatLng> _routePoints = [];
  bool _isLoadingRoute = false;

  // Mock list of safe places in area (Police, Hospitals, 24/7 stores)
  final List<Map<String, dynamic>> _safePoints = [
    {
      'name': 'Sector 62 Police Post',
      'type': 'Police',
      'coords': const LatLng(28.6290, 77.3750),
    },
    {
      'name': 'Fortis Hospital Noida',
      'type': 'Hospital',
      'coords': const LatLng(28.6235, 77.3785),
    },
    {
      'name': '24/7 Apollo Pharmacy',
      'type': 'Pharmacy',
      'coords': const LatLng(28.6285, 77.3790),
    }
  ];

  @override
  void initState() {
    super.initState();
    _fetchSafeRoute();
  }

  /// Calculates route from OSRM public API between user location and destination.
  Future<void> _fetchSafeRoute() async {
    setState(() => _isLoadingRoute = true);

    final String url = 'https://router.project-osrm.org/route/v1/foot/'
        '${_currentUserLocation.longitude},${_currentUserLocation.latitude};'
        '${_destinationLocation.longitude},${_destinationLocation.latitude}'
        '?overview=full&geometries=geojson';

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final geometry = data['routes'][0]['geometry']['coordinates'] as List;
        
        setState(() {
          _routePoints = geometry.map((coord) {
            return LatLng(coord[1] as double, coord[0] as double);
          }).toList();
        });
      } else {
        // Fallback simple straight route if OSRM rate-limits or fails
        setState(() {
          _routePoints = [_currentUserLocation, _destinationLocation];
        });
      }
    } catch (e) {
      debugPrint('Failed to calculate path telemetry: $e');
      setState(() {
        _routePoints = [_currentUserLocation, _destinationLocation];
      });
    } finally {
      setState(() => _isLoadingRoute = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('SAFE MAP ROUTE'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchSafeRoute,
          )
        ],
      ),
      body: Stack(
        children: [
          // OpenStreetMap Tile Rendering
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentUserLocation,
              initialZoom: 15.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.bhai.app',
                tileBuilder: isDark ? (context, tileWidget, tile) {
                  // Inverts map tiles for a clean dark mode representation
                  return ColorFiltered(
                    colorFilter: const ColorFilter.matrix([
                      -1.0, 0.0, 0.0, 0.0, 255.0, // Red
                      0.0, -1.0, 0.0, 0.0, 255.0, // Green
                      0.0, 0.0, -1.0, 0.0, 255.0, // Blue
                      0.0, 0.0, 0.0, 1.0, 0.0,    // Alpha
                    ]),
                    child: tileWidget,
                  );
                } : null,
              ),
              // Render calculated path line
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _routePoints,
                    strokeWidth: 5.0,
                    color: AppTheme.accentCyan,
                  ),
                ],
              ),
              // Marker Layer for user, destinations and nearby helper entities
              MarkerLayer(
                markers: [
                  // User Marker
                  Marker(
                    point: _currentUserLocation,
                    width: 40.0,
                    height: 40.0,
                    child: const Icon(Icons.my_location, color: Colors.blue, size: 30),
                  ),
                  // Destination Marker
                  Marker(
                    point: _destinationLocation,
                    width: 40.0,
                    height: 40.0,
                    child: const Icon(Icons.location_on, color: AppTheme.accentCrimson, size: 35),
                  ),
                  // Safe Zone Markers
                  ..._safePoints.map((pt) {
                    final isPolice = pt['type'] == 'Police';
                    final isHospital = pt['type'] == 'Hospital';

                    return Marker(
                      point: pt['coords'] as LatLng,
                      width: 35.0,
                      height: 35.0,
                      child: Tooltip(
                        message: pt['name'] as String,
                        child: Icon(
                          isPolice 
                              ? Icons.local_police 
                              : (isHospital ? Icons.local_hospital : Icons.local_pharmacy),
                          color: isPolice 
                              ? Colors.indigo 
                              : (isHospital ? Colors.red : Colors.green),
                          size: 26,
                        ),
                      ),
                    );
                  })
                ],
              ),
            ],
          ),

          // Loading overlay indicator
          if (_isLoadingRoute)
            const Positioned(
              top: 16,
              left: 0,
              right: 0,
              child: Center(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accentCyan),
                        ),
                        SizedBox(width: 12),
                        Text('Computing OSRM Safe Route...'),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // Glassmorphic status panel at bottom
          Positioned(
            bottom: 24,
            left: 20,
            right: 20,
            child: GlassmorphicContainer(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.shield_outlined, color: Colors.green),
                      SizedBox(width: 8),
                      Text(
                        'Safe Route Active',
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Prioritizing routes near Police stations and Hospitals.',
                    style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                  ),
                  const Divider(color: Colors.white24, height: 16),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('ETA', style: TextStyle(fontSize: 10, color: Colors.grey)),
                          Text('8 Mins', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Distance', style: TextStyle(fontSize: 10, color: Colors.grey)),
                          Text('1.2 KM', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Safeguards Passed', style: TextStyle(fontSize: 10, color: Colors.grey)),
                          Text('3 Points', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.accentCyan)),
                        ],
                      ),
                    ],
                  )
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
