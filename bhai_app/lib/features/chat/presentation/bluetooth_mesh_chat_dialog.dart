import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/services/bluetooth_service.dart';
import '../../../../core/services/chat_service.dart';
import '../../../../core/services/chat_transport.dart';
import '../../../../core/storage/local_storage.dart';
import '../../../../core/theme/app_theme.dart';

class BluetoothMeshChatDialog extends StatefulWidget {
  final String? alertId;
  final String? helperId;
  final bool isAdminThread;

  const BluetoothMeshChatDialog({
    super.key,
    this.alertId,
    this.helperId,
    this.isAdminThread = false,
  });

  @override
  State<BluetoothMeshChatDialog> createState() => _BluetoothMeshChatDialogState();
}

class _BluetoothMeshChatDialogState extends State<BluetoothMeshChatDialog> {
  final _bluetooth = BluetoothService();
  final _chatService = ChatService();
  final _textController = TextEditingController();
  final _scrollController = ScrollController();

  String _conversationId = 'default-emergency-channel';
  StreamSubscription<List<ChatMessageModel>>? _msgSub;
  List<ChatMessageModel> _messages = [];
  bool _isInternet = true;
  Timer? _statusTimer;

  final List<String> _quickChips = [
    'Where are you?',
    "I'm coming! (~300m away)",
    'At the gate in blue shirt',
    'Emergency services notified (112)',
    'I have reached your location',
  ];

  @override
  void initState() {
    super.initState();
    _chatService.initialize();
    _initConversation();
    _checkTransportStatus();
    _statusTimer = Timer.periodic(const Duration(seconds: 4), (_) => _checkTransportStatus());
  }

  Future<void> _checkTransportStatus() async {
    final online = await _bluetooth.isInternetConnected();
    if (mounted && online != _isInternet) {
      setState(() => _isInternet = online);
    }
  }

  Future<void> _initConversation() async {
    final alertId = widget.alertId ?? LocalStorage().activeRemoteEmergencyId ?? 'BHAI-MAIN';
    final conv = await _chatService.getOrCreateConversation(
      alertId,
      helperUserId: widget.helperId,
      isAdminThread: widget.isAdminThread,
    );

    if (!mounted) return;
    setState(() {
      _conversationId = conv.id;
      _messages = _chatService.getMessages(conv.id);
    });

    _msgSub = _chatService.getMessagesStream(conv.id).listen((msgs) {
      if (mounted) {
        setState(() => _messages = msgs);
        _scrollToBottom();
      }
    });

    await _chatService.refreshMessages(conv.id);
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _msgSub?.cancel();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    _textController.clear();
    await _chatService.sendMessage(
      conversationId: _conversationId,
      message: trimmed,
      receiverId: widget.helperId,
    );
    _scrollToBottom();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final myId = LocalStorage().getOrGenerateBhaiDeviceId();

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: const Color(0xFF00BCD4).withOpacity(0.4),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.6),
              blurRadius: 30,
              offset: const Offset(0, 15),
            ),
          ],
        ),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Color(0xFF1E293B),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00BCD4).withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.chat_bubble_outline_rounded,
                      color: Color(0xFF00BCD4),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'BHAI EMERGENCY CHAT',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: _isInternet ? const Color(0xFF10B981) : const Color(0xFF3B82F6),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _isInternet ? '🌐 Internet Active' : '📡 Bluetooth Direct Radio',
                              style: TextStyle(
                                color: _isInternet ? const Color(0xFF10B981) : const Color(0xFF93C5FD),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Messages List
            Expanded(
              child: _messages.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _isInternet ? Icons.wifi_tethering_rounded : Icons.bluetooth_audio_rounded,
                              size: 40,
                              color: Colors.white24,
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Direct Encrypted Emergency Channel',
                              style: TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _isInternet
                                  ? 'Connected via Secure Realtime Cloud'
                                  : 'Connected via 2.4 GHz Bluetooth Mesh (Offline)',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white38, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final msg = _messages[index];
                        final isMe = msg.senderId.toUpperCase() == myId.toUpperCase() || msg.senderId == 'local';

                        return Align(
                          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: isMe ? const Color(0xFF00BCD4) : const Color(0xFF334155),
                              borderRadius: BorderRadius.circular(16).copyWith(
                                bottomRight: isMe ? const Radius.circular(2) : const Radius.circular(16),
                                bottomLeft: !isMe ? const Radius.circular(2) : const Radius.circular(16),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                              children: [
                                Text(
                                  msg.message,
                                  style: TextStyle(
                                    color: isMe ? const Color(0xFF070B14) : Colors.white,
                                    fontSize: 14,
                                    fontWeight: isMe ? FontWeight.w600 : FontWeight.normal,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '${msg.createdAt.hour.toString().padLeft(2, '0')}:${msg.createdAt.minute.toString().padLeft(2, '0')}',
                                      style: TextStyle(
                                        color: isMe ? Colors.black54 : Colors.white38,
                                        fontSize: 10,
                                      ),
                                    ),
                                    if (isMe) ...[
                                      const SizedBox(width: 4),
                                      Icon(
                                        msg.deliveryStatus == 'READ'
                                            ? Icons.done_all_rounded
                                            : msg.deliveryStatus == 'DELIVERED'
                                                ? Icons.done_all_rounded
                                                : Icons.done_rounded,
                                        size: 13,
                                        color: msg.deliveryStatus == 'READ' ? const Color(0xFF1E293B) : Colors.black45,
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),

            // Quick chips
            SizedBox(
              height: 42,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _quickChips.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (context, index) {
                  return ActionChip(
                    label: Text(_quickChips[index]),
                    labelStyle: const TextStyle(fontSize: 11, color: Color(0xFF00BCD4), fontWeight: FontWeight.bold),
                    backgroundColor: const Color(0xFF1E293B),
                    side: const BorderSide(color: Color(0xFF334155)),
                    onPressed: () => _sendMessage(_quickChips[index]),
                  );
                },
              ),
            ),

            const SizedBox(height: 8),

            // Input Bar
            Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                color: Color(0xFF1E293B),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Type emergency message...',
                        hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                        filled: true,
                        fillColor: const Color(0xFF0F172A),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(999),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                      onSubmitted: _sendMessage,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFF00BCD4),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.send_rounded, color: Color(0xFF070B14), size: 18),
                      onPressed: () => _sendMessage(_textController.text),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
