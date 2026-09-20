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

  Future<Position?> getBestAvailableLocation() async {
    try {
      final hasPerm = await checkPermission();
      if (!hasPerm) return null;
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 4),
        ),
      );
    } catch (_) {
      try {
        final last = await Geolocator.getLastKnownPosition();
        return last;
      } catch (_) {
        return null;
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
