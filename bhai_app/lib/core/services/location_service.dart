import 'package:geolocator/geolocator.dart';

class LocationService {
  LocationService._();
  static final LocationService _instance = LocationService._();
  factory LocationService() => _instance;

  Future<bool> checkPermission() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return true;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      return permission == LocationPermission.whileInUse || permission == LocationPermission.always || permission == LocationPermission.unableToDetermine;
    } catch (_) {
      return true; // Fallback for laptop & web environments
    }
  }

  Position _mockPosition() => Position(
        latitude: 28.6273,
        longitude: 77.3725,
        timestamp: DateTime.now(),
        accuracy: 15.0,
        altitude: 0.0,
        altitudeAccuracy: 0.0,
        heading: 0.0,
        headingAccuracy: 0.0,
        speed: 0.0,
        speedAccuracy: 0.0,
      );

  Future<Position?> getBestAvailableLocation() async {
    try {
      final hasPerm = await checkPermission();
      if (!hasPerm) return _mockPosition();
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 4),
        ),
      );
    } catch (_) {
      try {
        final last = await Geolocator.getLastKnownPosition();
        return last ?? _mockPosition();
      } catch (_) {
        return _mockPosition();
      }
    }
  }

  Stream<Position> activeEmergencyLocations() {
    const settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    );
    return Geolocator.getPositionStream(locationSettings: settings);
  }
}
