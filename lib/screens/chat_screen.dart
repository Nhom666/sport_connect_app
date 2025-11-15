import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';

const Color kPrimaryColor = Color.fromRGBO(7, 7, 112, 1);
const Color kAccentColor = Colors.blue;

class ChatScreen extends StatefulWidget {
  final String teamId;
  final String teamName;

  const ChatScreen({super.key, required this.teamId, required this.teamName});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageController = TextEditingController();
  final _currentUser = FirebaseAuth.instance.currentUser;

  @override
  void initState() {
    super.initState();
    _markAsRead();
  }

  @override
  void dispose() {
    // CẬP NHẬT QUAN TRỌNG:
    // Gọi lại hàm _markAsRead() khi thoát màn hình để cập nhật lần đọc cuối cùng.
    _markAsRead();

    _messageController.dispose();
    super.dispose();
  }

  void _markAsRead() {
    if (_currentUser == null) return;
    FirebaseFirestore.instance
        .collection('users')
        .doc(_currentUser.uid)
        .collection('teamReadStatus')
        .doc(widget.teamId)
        .set({'lastReadTimestamp': FieldValue.serverTimestamp()});
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _currentUser == null) return;

    final timestamp = FieldValue.serverTimestamp();

    try {
      final batch = FirebaseFirestore.instance.batch();
      final messageRef = FirebaseFirestore.instance
          .collection('teams')
          .doc(widget.teamId)
          .collection('messages')
          .doc();
      batch.set(messageRef, {
        'text': text,
        'senderId': _currentUser.uid,
        'senderName': _currentUser.displayName ?? 'A Member',
        'senderAvatarUrl': _currentUser.photoURL ?? '',
        'timestamp': timestamp,
      });

      final teamRef = FirebaseFirestore.instance
          .collection('teams')
          .doc(widget.teamId);
      batch.update(teamRef, {'lastMessageTimestamp': timestamp});

      final userReadStatusRef = FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUser.uid)
          .collection('teamReadStatus')
          .doc(widget.teamId);
      batch.set(userReadStatusRef, {'lastReadTimestamp': timestamp});

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
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.teamName,
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
              stream: FirebaseFirestore.instance
                  .collection('teams')
                  .doc(widget.teamId)
                  .collection('messages')
                  .orderBy('timestamp', descending: false)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Text('No messages yet. Start the conversation!'),
                  );
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
