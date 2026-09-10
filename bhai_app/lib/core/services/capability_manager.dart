import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class CapabilityStatus {
  const CapabilityStatus({
    required this.internetAvailable,
    required this.bluetoothAvailable,
    required this.bluetoothPermissionGranted,
    required this.locationAvailable,
    required this.locationPermissionGranted,
    required this.notificationPermissionGranted,
    required this.backgroundOperationAvailable,
  });

  final bool internetAvailable;
  final bool bluetoothAvailable;
  final bool bluetoothPermissionGranted;
  final bool locationAvailable;
  final bool locationPermissionGranted;
  final bool notificationPermissionGranted;
  final bool backgroundOperationAvailable;

  bool get isFullyCapable =>
      bluetoothPermissionGranted && locationPermissionGranted && notificationPermissionGranted;
}

class CapabilityManager {
  CapabilityManager._();
  static final CapabilityManager _instance = CapabilityManager._();
  factory CapabilityManager() => _instance;

  Future<CapabilityStatus> checkCapabilities() async {
    bool hasNet = false;
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      hasNet = !connectivityResult.contains(ConnectivityResult.none);
    } catch (_) {
      hasNet = false;
    }

    final locStatus = await Permission.location.status;
    final notifStatus = await Permission.notification.status;
    final bleScan = await Permission.bluetoothScan.status;
    final bleConnect = await Permission.bluetoothConnect.status;

    final locGranted = locStatus.isGranted || locStatus.isLimited;
    final notifGranted = notifStatus.isGranted;
    final bleGranted = bleScan.isGranted && bleConnect.isGranted;

    return CapabilityStatus(
      internetAvailable: hasNet,
      bluetoothAvailable: true,
      bluetoothPermissionGranted: bleGranted,
      locationAvailable: locGranted,
      locationPermissionGranted: locGranted,
      notificationPermissionGranted: notifGranted,
      backgroundOperationAvailable: true,
    );
  }
}
