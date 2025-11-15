// lib/screens/personal_chat_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../utils/constants.dart';

class PersonalChatScreen extends StatefulWidget {
  final String friendId;
  final String friendName;

  const PersonalChatScreen({
    super.key,
    required this.friendId,
    required this.friendName,
  });

  @override
  State<PersonalChatScreen> createState() => _PersonalChatScreenState();
}

class _PersonalChatScreenState extends State<PersonalChatScreen> {
  final _messageController = TextEditingController();
  final _currentUser = FirebaseAuth.instance.currentUser;
  String? _chatRoomId;

  // --- NEW: Lưu trữ dữ liệu người dùng ---
  Map<String, dynamic>? _friendData;
  Map<String, dynamic>? _currentUserData;

  @override
  void initState() {
    super.initState();
    // Chạy hàm setup bất đồng bộ
    _setupChat();
  }

  // --- NEW: Hàm setup bất đồng bộ ---
  Future<void> _setupChat() async {
    if (_currentUser == null) return;

    // 1. Tải dữ liệu 2 người dùng (để lưu vào metadata)
    await _loadUserData();

    // 2. Tạo ID phòng chat
    _generateChatRoomId();

    // 3. Đánh dấu là đã đọc
    if (_chatRoomId != null) {
      _markAsRead();
    }

    // Build lại UI khi đã có _chatRoomId
    if (mounted) {
      setState(() {});
    }
  }

  // --- NEW: Tải data 2 user ---
  Future<void> _loadUserData() async {
    if (_currentUser == null) return;
    try {
      final friendDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.friendId)
          .get();
      _friendData = friendDoc.data();

      final currentUserDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUser.uid)
          .get();
      _currentUserData = currentUserDoc.data();
    } catch (e) {
      print("Lỗi tải user data: $e");
    }
  }

  void _generateChatRoomId() {
    if (_currentUser == null) return;
    final currentUserId = _currentUser.uid;

    if (currentUserId.compareTo(widget.friendId) > 0) {
      _chatRoomId = '${currentUserId}_${widget.friendId}';
    } else {
      _chatRoomId = '${widget.friendId}_${currentUserId}';
    }
  }

  // --- NEW: Logic đánh dấu đã đọc ---
  void _markAsRead() {
    if (_currentUser == null || _chatRoomId == null) return;
    FirebaseFirestore.instance.collection('chats').doc(_chatRoomId).set(
      {
        'readStatus': {_currentUser.uid: true},
      },
      SetOptions(merge: true),
    ); // Merge để không ghi đè trạng thái của user kia
  }

  @override
  void dispose() {
    _markAsRead(); // Đánh dấu đã đọc khi thoát
    _messageController.dispose();
    super.dispose();
  }

  // --- UPDATED: Hàm _sendMessage (Rất quan trọng) ---
  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty ||
        _currentUser == null ||
        _chatRoomId == null ||
        _friendData == null ||
        _currentUserData == null)
      return;

    final timestamp = FieldValue.serverTimestamp();
    final currentUserId = _currentUser.uid;

    try {
      final batch = FirebaseFirestore.instance.batch();

      // 1. Tham chiếu đến phòng chat
      final chatRoomRef = FirebaseFirestore.instance
          .collection('chats')
          .doc(_chatRoomId);

      // 2. Tham chiếu đến tin nhắn mới
      final messageRef = chatRoomRef.collection('messages').doc();

      // 3. Set tin nhắn mới
      batch.set(messageRef, {
        'text': text,
        'senderId': currentUserId,
        'senderName': _currentUserData!['displayName'] ?? 'A Member',
        'senderAvatarUrl': _currentUserData!['photoURL'] ?? '',
        'timestamp': timestamp,
      });

      // 4. Cập nhật metadata của phòng chat (để hiển thị ở inbox)
      batch.set(chatRoomRef, {
        'participants': [currentUserId, widget.friendId],
        'participantNames': {
          currentUserId: _currentUserData!['displayName'] ?? 'A Member',
          widget.friendId: _friendData!['displayName'] ?? 'A Member',
        },
        'participantAvatars': {
          currentUserId: _currentUserData!['photoURL'] ?? '',
          widget.friendId: _friendData!['photoURL'] ?? '',
        },
        'lastMessage': text,
        'lastMessageTimestamp': timestamp,
        'lastMessageSenderId': currentUserId,
        'readStatus': {
          currentUserId: true, // Người gửi đã đọc
          widget.friendId: false, // Người nhận chưa đọc
        },
      }, SetOptions(merge: true)); // Dùng merge để tạo mới hoặc cập nhật

      await batch.commit();
      _messageController.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to send message: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Phải chờ _chatRoomId được tạo
    if (_chatRoomId == null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.friendName)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.friendName,
          style: const TextStyle(
            color: kPrimaryColor,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.white,
        foregroundColor: kPrimaryColor,
        elevation: 1,
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              // Stream này vẫn giữ nguyên
              stream: FirebaseFirestore.instance
                  .collection('chats')
                  .doc(_chatRoomId)
                  .collection('messages')
                  .orderBy('timestamp', descending: false)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text('No messages yet. Say hi!'));
                }
                final messages = snapshot.data!.docs;

                return ListView.builder(
                  padding: const EdgeInsets.all(10.0),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final currentMessageData =
                        messages[index].data() as Map<String, dynamic>;
                    final isMe =
                        currentMessageData['senderId'] == _currentUser?.uid;

                    bool showHeader = false;

                    if (index == 0) {
                      showHeader = true;
                    } else {
                      final previousMessageData =
                          messages[index - 1].data() as Map<String, dynamic>?;
                      if (previousMessageData?['senderId'] !=
                          currentMessageData['senderId']) {
                        showHeader = true;
                      }
                    }

                    return _MessageBubble(
                      data: currentMessageData,
                      isMe: isMe,
                      showHeader: showHeader,
                    );
                  },
                );
              },
            ),
          ),
          _buildMessageComposer(),
        ],
      ),
    );
  }

  Widget _buildMessageComposer() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 10.0),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            spreadRadius: 2,
            blurRadius: 5,
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _messageController,
                decoration: const InputDecoration.collapsed(
                  hintText: 'Send a message...',
                ),
                textCapitalization: TextCapitalization.sentences,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.send, color: kAccentColor),
              onPressed: _sendMessage,
            ),
          ],
        ),
      ),
    );
  }
}

// --- (Class _MessageBubble được copy y hệt từ chat_screen.dart) ---
class _MessageBubble extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool isMe;
  final bool showHeader;

  const _MessageBubble({
    required this.data,
    required this.isMe,
    required this.showHeader,
  });

  @override
  Widget build(BuildContext context) {
    final alignment = isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final color = isMe ? kAccentColor : Colors.grey[200];
    final textColor = isMe ? Colors.white : Colors.black87;

    final String senderName = data['senderName'] ?? 'Unknown';
    final String avatarUrl = data['senderAvatarUrl'] ?? '';
    final String text = data['text'] ?? '';
    final topMargin = showHeader ? 10.0 : 2.0;
    final bool shouldShowHeader = !isMe && showHeader;

    return Container(
      margin: EdgeInsets.only(top: topMargin),
      child: Row(
        mainAxisAlignment: isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (shouldShowHeader) ...[
            CircleAvatar(
              backgroundImage: avatarUrl.isNotEmpty
                  ? CachedNetworkImageProvider(avatarUrl)
                  : null,
              child: avatarUrl.isEmpty ? const Icon(Icons.person) : null,
            ),
            const SizedBox(width: 8),
          ] else if (!isMe) ...[
            const SizedBox(width: 48),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: alignment,
              children: [
                if (shouldShowHeader)
                  Padding(
                    padding: const EdgeInsets.only(left: 8.0, bottom: 2.0),
                    child: Text(
                      senderName,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14.0,
                    vertical: 10.0,
                  ),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(16.0),
                  ),
                  child: Text(text, style: TextStyle(color: textColor)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
