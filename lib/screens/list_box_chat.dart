import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'personal_chat_screen.dart';
import '../utils/constants.dart';

class ListBoxChatScreen extends StatefulWidget {
  const ListBoxChatScreen({Key? key}) : super(key: key);

  @override
  State<ListBoxChatScreen> createState() => _ListBoxChatScreenState();
}

class _ListBoxChatScreenState extends State<ListBoxChatScreen> {
  final _currentUser = FirebaseAuth.instance.currentUser;

  // --- (Biến cho chức năng tìm kiếm) ---
  final _searchController = TextEditingController();
  String searchQuery = '';
  bool _isSearching = false;
  Future<void>? _initFuture; // Để tải danh sách bạn bè

  // --- UPDATED: Lưu danh sách bạn bè đầy đủ ---
  List<DocumentSnapshot> _allFriends = [];
  List<DocumentSnapshot> _searchResults = [];
  // ------------------------------------

  @override
  void initState() {
    super.initState();
    // 1. Tải danh sách bạn bè MỘT LẦN
    _initFuture = _loadFriendData(); // <-- Sửa tên hàm

    // 2. Lắng nghe thanh tìm kiếm
    _searchController.addListener(() {
      final query = _searchController.text.trim();
      if (query.isEmpty) {
        if (_isSearching) {
          // Nếu vừa xóa hết chữ, ngừng tìm kiếm
          setState(() {
            _isSearching = false;
            _searchResults = [];
          });
        }
      } else {
        if (!_isSearching) {
          // Bắt đầu tìm kiếm
          setState(() {
            _isSearching = true;
          });
        }
        _performSearch(query); // Gọi hàm lọc
      }
    });
  }

  // --- UPDATED: Hàm tải TOÀN BỘ dữ liệu bạn bè ---
  Future<void> _loadFriendData() async {
    if (_currentUser == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUser.uid)
          .get();

      final friendIds = List<String>.from(doc.data()?['friends'] ?? []);

      if (friendIds.isEmpty) {
        _allFriends = [];
        return;
      }

      // Xử lý giới hạn 30 ID của Firestore 'whereIn'
      List<DocumentSnapshot> tempFriends = [];
      List<List<String>> chunks = [];
      for (var i = 0; i < friendIds.length; i += 30) {
        chunks.add(
          friendIds.sublist(
            i,
            i + 30 > friendIds.length ? friendIds.length : i + 30,
          ),
        );
      }

      for (final chunk in chunks) {
        final querySnapshot = await FirebaseFirestore.instance
            .collection('users')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        tempFriends.addAll(querySnapshot.docs);
      }

      _allFriends = tempFriends; // Lưu kết quả
    } catch (e) {
      print("Lỗi tải danh sách bạn bè: $e");
      _allFriends = [];
    }
  }
  // --------------------------------------------

  // --- NEW: Hàm lọc danh sách bạn bè bằng Dart ---
  void _performSearch(String query) {
    final lowerQuery = query.toLowerCase();

    final results = _allFriends.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final email = (data['email'] ?? '').toLowerCase();
      // Dùng .contains() để tìm kiếm linh hoạt hơn
      return email.contains(lowerQuery);
    }).toList();

    setState(() {
      _searchResults = results; // Cập nhật danh sách kết quả
    });
  }
  // --------------------------------------------

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ... (Hàm _formatChatTimestamp giữ nguyên) ...
  String _formatChatTimestamp(Timestamp? timestamp) {
    if (timestamp == null) return '';
    final now = DateTime.now();
    final messageTime = timestamp.toDate();
    if (now.day == messageTime.day &&
        now.month == messageTime.month &&
        now.year == messageTime.year) {
      return DateFormat('h:mm a').format(messageTime);
    } else if (now.year == messageTime.year &&
        now.difference(messageTime).inDays < 7) {
      return DateFormat('E').format(messageTime);
    } else {
      return DateFormat('dd/MM/yy').format(messageTime);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_currentUser == null) {
      // ... (Widget đăng nhập giữ nguyên) ...
      return Scaffold(
        appBar: AppBar(title: const Text('Tin nhắn')),
        body: const Center(child: Text('Vui lòng đăng nhập để xem tin nhắn.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Chats',
          style: TextStyle(
            color: kPrimaryColor,
            fontWeight: FontWeight.bold,
            fontSize: 24,
          ),
        ),
        backgroundColor: kWhiteColor,
        elevation: 1,
      ),
      backgroundColor: kWhiteColor,
      // Dùng FutureBuilder để đảm bảo danh sách bạn bè đã được tải
      body: FutureBuilder(
        future: _initFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          return Column(
            children: [
              _buildSearchField(), // <-- Thanh tìm kiếm
              Expanded(
                child: _isSearching
                    ? _buildSearchResults() // <-- Kết quả tìm kiếm
                    : _buildChatList(), // <-- Danh sách chat
              ),
            ],
          );
        },
      ),
    );
  }

  // --- Widget thanh tìm kiếm (Giữ nguyên) ---
  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.all(kDefaultPadding),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Tìm kiếm bạn bè theo email...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _isSearching
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                  },
                )
              : null,
          filled: true,
          fillColor: Colors.grey[200],
          border: OutlineInputBorder(
            borderRadius: kDefaultBorderRadius,
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }

  // --- UPDATED: Widget kết quả tìm kiếm (Không còn StreamBuilder) ---
  Widget _buildSearchResults() {
    if (_allFriends.isEmpty) {
      return const Center(child: Text('Bạn chưa có người bạn nào.'));
    }

    if (_searchResults.isEmpty) {
      return const Center(child: Text('Không tìm thấy người bạn nào khớp.'));
    }

    // Hiển thị danh sách từ biến _searchResults
    return ListView.builder(
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final userDoc = _searchResults[index];
        final data = userDoc.data() as Map<String, dynamic>;
        final friendName = data['displayName'] ?? 'Unknown';
        final friendAvatar = data['photoURL'] ?? '';
        final friendEmail = data['email'] ?? '';

        return ListTile(
          leading: CircleAvatar(
            radius: 28,
            backgroundImage: friendAvatar.isNotEmpty
                ? CachedNetworkImageProvider(friendAvatar)
                : null,
            child: friendAvatar.isEmpty
                ? const Icon(Icons.person, size: 28)
                : null,
          ),
          title: Text(friendName),
          subtitle: Text(friendEmail),
          onTap: () {
            // Mở màn hình chat (ngay cả khi chưa chat bao giờ)
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => PersonalChatScreen(
                  friendId: userDoc.id,
                  friendName: friendName,
                ),
              ),
            );
          },
        );
      },
    );
  }
  // ---------------------------------

  // --- Widget danh sách chat (Giữ nguyên) ---
  Widget _buildChatList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('chats')
          .where('participants', arrayContains: _currentUser!.uid)
          .orderBy('lastMessageTimestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Lỗi: ${snapshot.error}'));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text('Chưa có cuộc trò chuyện nào.'));
        }

        final chatDocs = snapshot.data!.docs;

        return ListView.builder(
          itemCount: chatDocs.length,
          itemBuilder: (context, index) {
            final chatDoc = chatDocs[index];
            final data = chatDoc.data() as Map<String, dynamic>;

            String friendId = (data['participants'] as List).firstWhere(
              (id) => id != _currentUser.uid,
              orElse: () => '',
            );
            String friendName =
                data['participantNames']?[friendId] ?? 'Unknown';
            String friendAvatar = data['participantAvatars']?[friendId] ?? '';
            String lastMessage = data['lastMessage'] ?? '';
            Timestamp? lastMessageTimestamp = data['lastMessageTimestamp'];
            bool isUnread = !(data['readStatus']?[_currentUser.uid] ?? true);
            final String? lastMessageSenderId = data['lastMessageSenderId'];
            final bool sentByMe = (lastMessageSenderId == _currentUser.uid);
            final String displayMessage = sentByMe
                ? 'Bạn: $lastMessage'
                : lastMessage;

            return ListTile(
              leading: CircleAvatar(
                radius: 28,
                backgroundImage: friendAvatar.isNotEmpty
                    ? CachedNetworkImageProvider(friendAvatar)
                    : null,
                child: friendAvatar.isEmpty
                    ? const Icon(Icons.person, size: 28)
                    : null,
              ),
              title: Text(
                friendName,
                style: TextStyle(
                  fontWeight: isUnread ? FontWeight.bold : FontWeight.w500,
                  color: kBlackColor,
                ),
              ),
              subtitle: Text(
                displayMessage,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: isUnread ? FontWeight.bold : FontWeight.normal,
                  color: isUnread ? kBlackColor : Colors.grey[600],
                ),
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _formatChatTimestamp(lastMessageTimestamp),
                    style: TextStyle(
                      fontSize: 12,
                      color: isUnread ? kAccentColor : Colors.grey[600],
                      fontWeight: isUnread
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                  if (isUnread) ...[
                    const SizedBox(height: 4),
                    Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: kAccentColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ],
              ),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => PersonalChatScreen(
                      friendId: friendId,
                      friendName: friendName,
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
