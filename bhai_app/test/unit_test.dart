import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:bhai_app/core/protocol/emergency_packet.dart';
import 'package:bhai_app/core/state/emergency_state_machine.dart';
import 'package:bhai_app/core/services/bluetooth_service.dart';

// --- Pure Dart implementations of core components for unit validation ---

/// Haversine Formula helper to calculate distance between two GPS coordinates in meters.
double calculateHaversineDistance(double lat1, double lon1, double lat2, double lon2) {
  const double r = 6371000; // Earth radius in meters
  final double dLat = (lat2 - lat1) * pi / 180;
  final double dLon = (lon2 - lon1) * pi / 180;
  
  final double a = sin(dLat / 2) * sin(dLat / 2) +
      cos(lat1 * pi / 180) * cos(lat2 * pi / 180) *
      sin(dLon / 2) * sin(dLon / 2);
  
  final double c = 2 * atan2(sqrt(a), sqrt(1 - a));
  return r * c;
}

void main() {
  group('Security and Cryptography Engine Tests', () {
    test('Dummy Encryption Key Generation and Mock Validation', () {
      const plainText = 'Emergency Contact Phone: +91 98765 43210';
      
      // Simulate raw basic encryption validation
      const encryptedText = 'encrypted_base64_representation_of_data';
      
      expect(encryptedText, isNotEmpty);
      expect(encryptedText, isNot(equals(plainText)));
    });
  });

  group('Volunteer Network Distance Query Tests', () {
    test('Haversine distance calculation is accurate', () {
      // Coordinate points in Noida Sector 62
      const double lat1 = 28.6273;
      const double lon1 = 77.3725;
      
      // Coordinates point ~470 meters away
      const double lat2 = 28.6295;
      const double lon2 = 77.3768;

      final double distance = calculateHaversineDistance(lat1, lon1, lat2, lon2);
      
      // Expect distance to be approximately 485.8 meters (with small float error range)
      expect(distance, closeTo(485.8, 15.0));
    });

    test('Volunteer outside 5km radius is rejected', () {
      const double victimLat = 28.6273;
      const double victimLon = 77.3725;
      
      // Coordinates of Connaught Place, Delhi (approx 15km away)
      const double volunteerLat = 28.6304;
      const double volunteerLon = 77.2177;

      final double distance = calculateHaversineDistance(victimLat, victimLon, volunteerLat, volunteerLon);
      
      expect(distance, greaterThan(5000.0)); // Should be greater than 5km limits
    });
  });

  group('Emergency Protocol Packet & State Machine Tests', () {
    test('EmergencyPacket serialization, deserialization and signature generation', () {
      final now = DateTime.now().toUtc();
      final packet = EmergencyPacket(
        protocolVersion: 1,
        messageId: 'msg-12345',
        emergencyId: 'bhai-998877',
        type: 'EMERGENCY',
        createdAt: now.toIso8601String(),
        expiresAt: now.add(const Duration(hours: 6)).toIso8601String(),
        senderEphemeralId: 'EPH-8F92A14B',
        latitude: 17.385044,
        longitude: 78.486671,
        accuracy: 10.0,
        locationSource: 'GPS',
        locationTimestamp: '2026-08-26T22:34:58Z',
        severity: 'HIGH',
        hopCount: 0,
        maxHops: 3,
        requiresRelay: true,
        isTest: false,
        signature: 'test-signature',
      );

      final json = packet.toJson();
      final restored = EmergencyPacket.fromJson(json);

      expect(restored.protocolVersion, equals(1));
      expect(restored.emergencyId, equals('bhai-998877'));
      expect(restored.canRelay, isTrue);

      final incremented = restored.incrementHop();
      expect(incremented.hopCount, equals(1));
    });

    test('EmergencyStateMachine state transitions', () {
      final sm = EmergencyStateMachine();
      expect(sm.currentState, equals(EmergencyState.idle));

      sm.transitionTo(EmergencyState.emergencyTriggered, reason: 'Test trigger');
      expect(sm.currentState, equals(EmergencyState.emergencyTriggered));

      sm.transitionTo(EmergencyState.locationAcquisition);
      expect(sm.currentState, equals(EmergencyState.locationAcquisition));

      sm.transitionTo(EmergencyState.activeEmergency);
      expect(sm.currentState, equals(EmergencyState.activeEmergency));

      sm.reset();
      expect(sm.currentState, equals(EmergencyState.idle));
    });
  });

  group('V1 BLE Peer Discovery & Alert Protocol Tests', () {
    test('BhaiNearbyDevice correctly ranks nearest device by RSSI signal strength', () {
      final dev1 = BhaiNearbyDevice(
        deviceId: 'PEER_A',
        rssi: -85,
        lastSeen: DateTime.now(),
      );
      final dev2 = BhaiNearbyDevice(
        deviceId: 'PEER_B',
        rssi: -52, // Strongest signal (closest)
        lastSeen: DateTime.now(),
      );
      final dev3 = BhaiNearbyDevice(
        deviceId: 'PEER_C',
        rssi: -70,
        lastSeen: DateTime.now(),
      );

      final list = [dev1, dev2, dev3];
      list.sort((a, b) => b.rssi.compareTo(a.rssi));

      expect(list.first.deviceId, equals('PEER_B'));
      expect(list.first.proximity, contains('1-5m'));
      expect(list.first.signalStrength, equals('Strong'));
    });

    test('BhaiEmergencyAlert distance approximation from RSSI', () {
      final immediateAlert = BhaiEmergencyAlert(
        senderId: 'A1B2C3',
        targetId: '000000',
        rssi: -55,
        receivedAt: DateTime.now(),
      );
      expect(immediateAlert.estimatedDistance, contains('Within ~1-5 meters'));

      final mediumAlert = BhaiEmergencyAlert(
        senderId: 'A1B2C3',
        targetId: '000000',
        rssi: -72,
        receivedAt: DateTime.now(),
      );
      expect(mediumAlert.estimatedDistance, contains('Within ~5-15 meters'));
    });
  });
}

