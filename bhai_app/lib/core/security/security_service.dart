import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecurityService {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  enc.Key? _encryptionKey;

  // Singleton instance setup
  static final SecurityService _instance = SecurityService._internal();
  factory SecurityService() => _instance;
  SecurityService._internal();

  /// Initializes the encryption key from secure storage, generating one if not present.
  Future<void> init() async {
    if (_encryptionKey != null) return;

    String? keyBase64 = await _secureStorage.read(key: 'bhai_aes_key');
    if (keyBase64 == null) {
      // Generate a new 256-bit (32 bytes) cryptographically secure key
      final newKey = enc.Key.fromSecureRandom(32);
      keyBase64 = newKey.base64;
      await _secureStorage.write(key: 'bhai_aes_key', value: keyBase64);
      _encryptionKey = newKey;
    } else {
      _encryptionKey = enc.Key.fromBase64(keyBase64);
    }
  }

  /// Encrypts a string using AES-256-GCM with a fresh IV for every payload.
  /// The IV is stored alongside the ciphertext; it is not a secret.
  String encrypt(String plainText) {
    if (_encryptionKey == null) {
      throw StateError('SecurityService is not initialized. Call init() first.');
    }
    if (plainText.isEmpty) return '';

    final iv = enc.IV.fromSecureRandom(12);
    final encrypter = enc.Encrypter(enc.AES(_encryptionKey!, mode: enc.AESMode.gcm));
    final encrypted = encrypter.encrypt(plainText, iv: iv);
    return '${iv.base64}:${encrypted.base64}';
  }

  /// Decrypts a base64 encoded cipher text using AES-256 CBC mode.
  String decrypt(String cipherTextBase64) {
    if (_encryptionKey == null) {
      throw StateError('SecurityService is not initialized. Call init() first.');
    }
    if (cipherTextBase64.isEmpty) return '';

    try {
      final parts = cipherTextBase64.split(':');
      if (parts.length != 2) {
        throw const FormatException('Encrypted payload is malformed');
      }
      final encrypter = enc.Encrypter(enc.AES(_encryptionKey!, mode: enc.AESMode.gcm));
      final decrypted = encrypter.decrypt64(parts[1], iv: enc.IV.fromBase64(parts[0]));
      return decrypted;
    } catch (e) {
      // Fallback or decrytion failure handles gracefully
      return '[Decryption Error: Invalid Key or Corrupted Data]';
    }
  }

  /// Hashes data (e.g. for offline comparisons or integrity validation)
  String hashSha256(String data) {
    final bytes = utf8.encode(data);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
}
