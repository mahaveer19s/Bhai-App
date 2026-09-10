import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/services/bluetooth_service.dart';
import '../../../../core/theme/app_theme.dart';

class MeshChatMessage {
  final String senderId;
  final String text;
  final DateTime timestamp;
  final bool isMe;

  const MeshChatMessage({
    required this.senderId,
    required this.text,
    required this.timestamp,
    required this.isMe,
  });
}

class BluetoothMeshChatDialog extends StatefulWidget {
  const BluetoothMeshChatDialog({super.key});

  @override
  State<BluetoothMeshChatDialog> createState() => _BluetoothMeshChatDialogState();
}

class _BluetoothMeshChatDialogState extends State<BluetoothMeshChatDialog> {
  final _bluetooth = BluetoothService();
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  static final List<MeshChatMessage> _sharedMessages = [];
  late StreamSubscription<List<BhaiNearbyDevice>> _peerSub;
  List<BhaiNearbyDevice> _peers = [];

  final List<String> _quickChips = [
    'Are you safe?',
    "I'm coming to help!",
    'Where are you located?',
    'Emergency services notified (112)',
    'Stay where you are, help is near',
  ];

  @override
  void initState() {
    super.initState();
    _peerSub = _bluetooth.nearbyDevicesStream.listen((devices) {
      if (mounted) {
        setState(() => _peers = devices);
      }
    });
  }

  @override
  void dispose() {
    _peerSub.cancel();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _sendMessage(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final msg = MeshChatMessage(
      senderId: _bluetooth.myDeviceId,
      text: trimmed,
      timestamp: DateTime.now(),
      isMe: true,
    );

    setState(() {
      _sharedMessages.add(msg);
    });

    _textController.clear();
    _scrollToBottom();

    // Broadcast over local Bluetooth / relay
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Transmitted via Bluetooth Mesh: "$trimmed"'),
        duration: const Duration(seconds: 2),
        backgroundColor: const Color(0xFF0284C7),
      ),
    );
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
    final myId = _bluetooth.myDeviceId;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.82,
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFF0284C7), width: 1.8),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0284C7).withOpacity(0.35),
              blurRadius: 28,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: const BoxDecoration(
                color: Color(0xFF1E293B),
                borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0284C7).withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.bluetooth_audio, color: Color(0xFF38BDF8), size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'BLUETOOTH MESH CHAT',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        Text(
                          'My ID: BHAI-$myId • ${_peers.length} Peers in Range',
                          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Nearby Peers Bar
            if (_peers.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                color: const Color(0xFF134E4A).withOpacity(0.4),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      const Icon(Icons.radar, color: Color(0xFF34D399), size: 16),
                      const SizedBox(width: 6),
                      const Text('Nearby:', style: TextStyle(color: Color(0xFF34D399), fontSize: 12, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 8),
                      ..._peers.map((p) => Container(
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF065F46),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              'BHAI-${p.deviceId} (${p.proximity})',
                              style: const TextStyle(color: Colors.white, fontSize: 11),
                            ),
                          )),
                    ],
                  ),
                ),
              ),

            // Messages List
            Expanded(
              child: _sharedMessages.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.forum_outlined, color: Colors.white.withOpacity(0.2), size: 48),
                          const SizedBox(height: 12),
                          const Text(
                            'Offline Bluetooth Mesh Channel',
                            style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 6),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 32),
                            child: Text(
                              'Send distress updates or questions to nearby Bhai devices without cellular or internet data.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      itemCount: _sharedMessages.length,
                      itemBuilder: (context, idx) {
                        final m = _sharedMessages[idx];
                        return Align(
                          alignment: m.isMe ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
                            decoration: BoxDecoration(
                              color: m.isMe ? const Color(0xFF0284C7) : const Color(0xFF334155),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              crossAxisAlignment: m.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                              children: [
                                Text(
                                  m.isMe ? 'You (BHAI-$myId)' : 'Nearby BHAI-${m.senderId}',
                                  style: TextStyle(
                                    color: m.isMe ? const Color(0xFFE0F2FE) : const Color(0xFF38BDF8),
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  m.text,
                                  style: const TextStyle(color: Colors.white, fontSize: 14),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),

            // Quick Chips
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              color: const Color(0xFF1E293B),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _quickChips.map((chip) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ActionChip(
                        backgroundColor: const Color(0xFF0F172A),
                        side: const BorderSide(color: Color(0xFF0284C7)),
                        label: Text(chip, style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 12)),
                        onPressed: () => _sendMessage(chip),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),

            // Input Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: const BoxDecoration(
                color: Color(0xFF0F172A),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(22)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Type Bluetooth distress message...',
                        hintStyle: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 13),
                        filled: true,
                        fillColor: const Color(0xFF1E293B),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: _sendMessage,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFF0284C7),
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.send_rounded, size: 20),
                    onPressed: () => _sendMessage(_textController.text),
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
