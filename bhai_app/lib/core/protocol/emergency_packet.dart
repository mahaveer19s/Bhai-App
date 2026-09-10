import 'dart:convert';
import 'package:crypto/crypto.dart';

class EmergencyPacket {
  const EmergencyPacket({
    required this.protocolVersion,
    required this.messageId,
    required this.emergencyId,
    required this.type,
    required this.createdAt,
    required this.expiresAt,
    required this.senderEphemeralId,
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.locationSource,
    required this.locationTimestamp,
    required this.severity,
    required this.hopCount,
    required this.maxHops,
    required this.requiresRelay,
    required this.isTest,
    required this.signature,
  });

  final int protocolVersion;
  final String messageId;
  final String emergencyId;
  final String type;
  final String createdAt;
  final String expiresAt;
  final String senderEphemeralId;
  final double latitude;
  final double longitude;
  final double accuracy;
  final String locationSource;
  final String locationTimestamp;
  final String severity;
  final int hopCount;
  final int maxHops;
  final bool requiresRelay;
  final bool isTest;
  final String signature;

  bool get isExpired {
    try {
      final expiry = DateTime.parse(expiresAt);
      return DateTime.now().toUtc().isAfter(expiry);
    } catch (_) {
      return false;
    }
  }

  bool get canRelay => hopCount < maxHops && !isExpired && requiresRelay;

  EmergencyPacket incrementHop() {
    return EmergencyPacket(
      protocolVersion: protocolVersion,
      messageId: messageId,
      emergencyId: emergencyId,
      type: type,
      createdAt: createdAt,
      expiresAt: expiresAt,
      senderEphemeralId: senderEphemeralId,
      latitude: latitude,
      longitude: longitude,
      accuracy: accuracy,
      locationSource: locationSource,
      locationTimestamp: locationTimestamp,
      severity: severity,
      hopCount: hopCount + 1,
      maxHops: maxHops,
      requiresRelay: requiresRelay,
      isTest: isTest,
      signature: signature,
    );
  }

  Map<String, dynamic> toJson() => {
        'protocolVersion': protocolVersion,
        'messageId': messageId,
        'emergencyId': emergencyId,
        'type': type,
        'createdAt': createdAt,
        'expiresAt': expiresAt,
        'senderEphemeralId': senderEphemeralId,
        'latitude': latitude,
        'longitude': longitude,
        'accuracy': accuracy,
        'locationSource': locationSource,
        'locationTimestamp': locationTimestamp,
        'severity': severity,
        'hopCount': hopCount,
        'maxHops': maxHops,
        'requiresRelay': requiresRelay,
        'isTest': isTest,
        'signature': signature,
      };

  factory EmergencyPacket.fromJson(Map<String, dynamic> json) => EmergencyPacket(
        protocolVersion: json['protocolVersion'] as int? ?? 1,
        messageId: json['messageId'] as String,
        emergencyId: json['emergencyId'] as String,
        type: json['type'] as String? ?? 'EMERGENCY',
        createdAt: json['createdAt'] as String,
        expiresAt: json['expiresAt'] as String,
        senderEphemeralId: json['senderEphemeralId'] as String,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        accuracy: (json['accuracy'] as num? ?? 0.0).toDouble(),
        locationSource: json['locationSource'] as String? ?? 'GPS',
        locationTimestamp: json['locationTimestamp'] as String,
        severity: json['severity'] as String? ?? 'HIGH',
        hopCount: json['hopCount'] as int? ?? 0,
        maxHops: json['maxHops'] as int? ?? 3,
        requiresRelay: json['requiresRelay'] as bool? ?? true,
        isTest: json['isTest'] as bool? ?? false,
        signature: json['signature'] as String? ?? '',
      );

  static String generateSignature(String rawData, String secretKey) {
    final keyBytes = utf8.encode(secretKey);
    final dataBytes = utf8.encode(rawData);
    final hmac = Hmac(sha256, keyBytes);
    return hmac.convert(dataBytes).toString();
  }
}
