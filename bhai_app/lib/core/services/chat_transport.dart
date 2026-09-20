import 'dart:async';

import '../storage/local_storage.dart';
import 'api_client.dart';
import 'bluetooth_service.dart';

enum TransportType {
  internet,
  bluetoothDirect,
}

class ChatMessageModel {
  final String id;
  final String conversationId;
  final String clientMessageId;
  final String senderId;
  final String? receiverId;
  final String message;
  final String transport; // 'INTERNET' or 'BLUETOOTH'
  final String deliveryStatus; // 'SENDING', 'SENT', 'DELIVERED', 'READ', 'FAILED'
  final DateTime createdAt;
  final DateTime? deliveredAt;
  final DateTime? readAt;

  const ChatMessageModel({
    required this.id,
    required this.conversationId,
    required this.clientMessageId,
    required this.senderId,
    this.receiverId,
    required this.message,
    required this.transport,
    required this.deliveryStatus,
    required this.createdAt,
    this.deliveredAt,
    this.readAt,
  });

  factory ChatMessageModel.fromJson(Map<String, dynamic> json) {
    return ChatMessageModel(
      id: json['id']?.toString() ?? '',
      conversationId: json['conversation_id']?.toString() ?? '',
      clientMessageId: json['client_message_id']?.toString() ?? '',
      senderId: json['sender_id']?.toString() ?? '',
      receiverId: json['receiver_id']?.toString(),
      message: json['message']?.toString() ?? '',
      transport: json['transport']?.toString() ?? 'INTERNET',
      deliveryStatus: json['delivery_status']?.toString() ?? 'SENT',
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now() : DateTime.now(),
      deliveredAt: json['delivered_at'] != null ? DateTime.tryParse(json['delivered_at'].toString()) : null,
      readAt: json['read_at'] != null ? DateTime.tryParse(json['read_at'].toString()) : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'conversation_id': conversationId,
    'client_message_id': clientMessageId,
    'sender_id': senderId,
    'receiver_id': receiverId,
    'message': message,
    'transport': transport,
    'delivery_status': deliveryStatus,
    'created_at': createdAt.toIso8601String(),
    'delivered_at': deliveredAt?.toIso8601String(),
    'read_at': readAt?.toIso8601String(),
  };

  ChatMessageModel copyWith({
    String? deliveryStatus,
    DateTime? deliveredAt,
    DateTime? readAt,
  }) {
    return ChatMessageModel(
      id: id,
      conversationId: conversationId,
      clientMessageId: clientMessageId,
      senderId: senderId,
      receiverId: receiverId,
      message: message,
      transport: transport,
      deliveryStatus: deliveryStatus ?? this.deliveryStatus,
      createdAt: createdAt,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      readAt: readAt ?? this.readAt,
    );
  }
}

/// Abstract transport contract for emergency communication.
abstract class MessageTransport {
  TransportType get type;
  Future<bool> isAvailable();
  Future<ChatMessageModel> sendMessage(String conversationId, String message, String clientMessageId, {String? receiverId});
}

/// Internet / Cloud HTTP & WebSocket Realtime Transport
class InternetTransport implements MessageTransport {
  @override
  TransportType get type => TransportType.internet;

  @override
  Future<bool> isAvailable() async {
    return await BluetoothService().isInternetConnected();
  }

  @override
  Future<ChatMessageModel> sendMessage(
    String conversationId,
    String message,
    String clientMessageId, {
    String? receiverId,
  }) async {
    final response = await ApiClient().post(
      '/chat/conversations/$conversationId/messages',
      {
        'client_message_id': clientMessageId,
        'message': message,
        'transport': 'INTERNET',
        if (receiverId != null) 'receiver_id': receiverId,
      },
    );
    return ChatMessageModel.fromJson(response);
  }
}

/// Offline 2.4 GHz Bluetooth Low Energy Direct Mesh Transport
class BluetoothTransport implements MessageTransport {
  @override
  TransportType get type => TransportType.bluetoothDirect;

  @override
  Future<bool> isAvailable() async {
    return await BluetoothService().isBluetoothEnabled();
  }

  @override
  Future<ChatMessageModel> sendMessage(
    String conversationId,
    String message,
    String clientMessageId, {
    String? receiverId,
  }) async {
    final senderId = LocalStorage().getOrGenerateBhaiDeviceId();
    
    // Broadcast message via BLE Mesh radio packet
    await BluetoothService().broadcastChatMessage(
      text: message,
      targetId: receiverId ?? 'FFFFFFFF',
    );

    return ChatMessageModel(
      id: clientMessageId,
      conversationId: conversationId,
      clientMessageId: clientMessageId,
      senderId: senderId,
      receiverId: receiverId,
      message: message,
      transport: 'BLUETOOTH',
      deliveryStatus: 'DELIVERED',
      createdAt: DateTime.now(),
      deliveredAt: DateTime.now(),
    );
  }
}
