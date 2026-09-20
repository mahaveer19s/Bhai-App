import 'dart:async';
import 'package:flutter/foundation.dart';

import '../storage/local_storage.dart';
import 'api_client.dart';
import 'bluetooth_service.dart';
import 'chat_transport.dart';

class ConversationModel {
  final String id;
  final String alertId;
  final String victimUserId;
  final String? helperUserId;
  final bool isAdminThread;
  final String status;
  final DateTime createdAt;

  const ConversationModel({
    required this.id,
    required this.alertId,
    required this.victimUserId,
    this.helperUserId,
    required this.isAdminThread,
    required this.status,
    required this.createdAt,
  });

  factory ConversationModel.fromJson(Map<String, dynamic> json) {
    return ConversationModel(
      id: json['id']?.toString() ?? '',
      alertId: json['alert_id']?.toString() ?? '',
      victimUserId: json['victim_user_id']?.toString() ?? '',
      helperUserId: json['helper_user_id']?.toString(),
      isAdminThread: json['is_admin_thread'] == true,
      status: json['status']?.toString() ?? 'ACTIVE',
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now() : DateTime.now(),
    );
  }
}

class ChatService {
  ChatService._();
  static final ChatService _instance = ChatService._();
  factory ChatService() => _instance;

  final InternetTransport _internetTransport = InternetTransport();
  final BluetoothTransport _bluetoothTransport = BluetoothTransport();

  final Map<String, List<ChatMessageModel>> _messagesByConversation = {};
  final Map<String, StreamController<List<ChatMessageModel>>> _controllers = {};
  final List<ChatMessageModel> _offlineQueue = [];
  Timer? _queueProcessorTimer;
  StreamSubscription? _bleChatSubscription;

  void initialize() {
    _startQueueProcessor();
    _bleChatSubscription?.cancel();
    _bleChatSubscription = BluetoothService().incomingBleChatStream.listen((data) {
      final senderId = data['senderId']?.toString() ?? 'UNKNOWN';
      final text = data['message']?.toString() ?? '';
      final msgKey = data['messageId']?.toString() ?? '';
      final convId = 'ble-peer-$senderId';

      final msg = ChatMessageModel(
        id: msgKey.isNotEmpty ? msgKey : 'ble-$senderId-${DateTime.now().millisecondsSinceEpoch}',
        conversationId: convId,
        clientMessageId: msgKey,
        senderId: senderId,
        receiverId: LocalStorage().getOrGenerateBhaiDeviceId(),
        message: text,
        transport: 'BLUETOOTH',
        deliveryStatus: 'DELIVERED',
        createdAt: (data['receivedAt'] as DateTime?) ?? DateTime.now(),
      );

      ingestIncomingMessage(convId, msg);
    });
  }


  /// Get or create a stream for a specific conversation.
  Stream<List<ChatMessageModel>> getMessagesStream(String conversationId) {
    if (!_controllers.containsKey(conversationId)) {
      _controllers[conversationId] = StreamController<List<ChatMessageModel>>.broadcast();
    }
    return _controllers[conversationId]!.stream;
  }

  /// Get existing cached messages for conversation.
  List<ChatMessageModel> getMessages(String conversationId) {
    return _messagesByConversation[conversationId] ?? [];
  }

  /// Create or retrieve conversation from backend or local storage.
  Future<ConversationModel> getOrCreateConversation(
    String alertId, {
    String? helperUserId,
    bool isAdminThread = false,
  }) async {
    try {
      final isOnline = await _internetTransport.isAvailable();
      if (isOnline) {
        final response = await ApiClient().post(
          '/chat/conversations',
          {
            'alert_id': alertId,
            if (helperUserId != null) 'helper_user_id': helperUserId,
            'is_admin_thread': isAdminThread,
          },
        );
        return ConversationModel.fromJson(response);
      }
    } catch (_) {}

    // Offline local conversation model
    final convId = 'local-conv-$alertId-${helperUserId ?? "admin"}';
    return ConversationModel(
      id: convId,
      alertId: alertId,
      victimUserId: LocalStorage().getOrGenerateBhaiDeviceId(),
      helperUserId: helperUserId,
      isAdminThread: isAdminThread,
      status: 'ACTIVE',
      createdAt: DateTime.now(),
    );
  }

  /// Fetch remote messages if online.
  Future<void> refreshMessages(String conversationId) async {
    try {
      final isOnline = await _internetTransport.isAvailable();
      if (isOnline) {
        final List<dynamic> data = await ApiClient().get('/chat/conversations/$conversationId/messages');
        final fetched = data.map((json) => ChatMessageModel.fromJson(json as Map<String, dynamic>)).toList();
        _messagesByConversation[conversationId] = fetched;
        _emitMessages(conversationId);
      }
    } catch (_) {}
  }

  /// Send message with automatic transport selection (Internet if available, else Bluetooth Direct).
  Future<ChatMessageModel> sendMessage({
    required String conversationId,
    required String message,
    String? receiverId,
  }) async {
    final clientMsgId = 'msg-${DateTime.now().millisecondsSinceEpoch}-${LocalStorage().getOrGenerateBhaiDeviceId().substring(0, 4)}';
    final senderId = LocalStorage().getOrGenerateBhaiDeviceId();

    // Determine best available transport
    final isInternet = await _internetTransport.isAvailable();
    final MessageTransport transport = isInternet ? _internetTransport : _bluetoothTransport;

    final pendingMsg = ChatMessageModel(
      id: clientMsgId,
      conversationId: conversationId,
      clientMessageId: clientMsgId,
      senderId: senderId,
      receiverId: receiverId,
      message: message,
      transport: isInternet ? 'INTERNET' : 'BLUETOOTH',
      deliveryStatus: 'SENDING',
      createdAt: DateTime.now(),
    );

    _appendMessage(conversationId, pendingMsg);

    try {
      final sent = await transport.sendMessage(conversationId, message, clientMsgId, receiverId: receiverId);
      _updateMessage(conversationId, clientMsgId, sent);
      return sent;
    } catch (e) {
      debugPrint('[ChatService] Send failed, queuing offline: $e');
      final failed = pendingMsg.copyWith(deliveryStatus: 'WAITING FOR CONNECTION');
      _updateMessage(conversationId, clientMsgId, failed);
      _offlineQueue.add(failed);
      return failed;
    }
  }

  /// Ingest message received via BLE scan or WebSocket.
  void ingestIncomingMessage(String conversationId, ChatMessageModel msg) {
    _appendMessage(conversationId, msg);
  }

  void _appendMessage(String conversationId, ChatMessageModel msg) {
    _messagesByConversation.putIfAbsent(conversationId, () => []);
    // Prevent duplicate entries
    final index = _messagesByConversation[conversationId]!.indexWhere(
      (m) => m.clientMessageId == msg.clientMessageId || (m.id.isNotEmpty && m.id == msg.id),
    );
    if (index == -1) {
      _messagesByConversation[conversationId]!.add(msg);
    } else {
      _messagesByConversation[conversationId]![index] = msg;
    }
    _emitMessages(conversationId);
  }

  void _updateMessage(String conversationId, String clientMsgId, ChatMessageModel updated) {
    if (!_messagesByConversation.containsKey(conversationId)) return;
    final index = _messagesByConversation[conversationId]!.indexWhere((m) => m.clientMessageId == clientMsgId);
    if (index != -1) {
      _messagesByConversation[conversationId]![index] = updated;
      _emitMessages(conversationId);
    }
  }

  void _emitMessages(String conversationId) {
    if (_controllers.containsKey(conversationId)) {
      _controllers[conversationId]!.add(List.unmodifiable(_messagesByConversation[conversationId] ?? []));
    }
  }

  void _startQueueProcessor() {
    _queueProcessorTimer?.cancel();
    _queueProcessorTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      if (_offlineQueue.isEmpty) return;
      final isOnline = await _internetTransport.isAvailable();
      if (!isOnline) return;

      final toProcess = List<ChatMessageModel>.from(_offlineQueue);
      for (final msg in toProcess) {
        try {
          final sent = await _internetTransport.sendMessage(
            msg.conversationId,
            msg.message,
            msg.clientMessageId,
            receiverId: msg.receiverId,
          );
          _offlineQueue.remove(msg);
          _updateMessage(msg.conversationId, msg.clientMessageId, sent);
        } catch (_) {
          // Keep in queue for next cycle
        }
      }
    });
  }
}
