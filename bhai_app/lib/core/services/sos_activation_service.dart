import 'emergency_service.dart';

/// Compatibility facade used by hardware-trigger integrations.
class SosActivationService {
  SosActivationService._();
  static final SosActivationService _instance = SosActivationService._();
  factory SosActivationService() => _instance;

  final _emergency = EmergencyService();

  bool get isSosModeActive => _emergency.isActive;
  Future<EmergencySnapshot> activateSos() => _emergency.activate();
  Future<void> resolveSos() => _emergency.endEmergency();
}
