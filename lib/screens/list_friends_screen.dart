import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'user_profile_screen.dart'; // Import màn hình hồ sơ

class ListFriendsScreen extends StatefulWidget {
  const ListFriendsScreen({super.key});

  @override
  State<ListFriendsScreen> createState() => _ListFriendsScreenState();
}

class _ListFriendsScreenState extends State<ListFriendsScreen> {
  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Danh sách bạn bè'),
        backgroundColor: Colors.white,
        elevation: 1,
        foregroundColor: Colors.black,
      ),
      body: currentUser == null
          ? const Center(child: Text('Vui lòng đăng nhập.'))
          : _buildFriendsList(currentUser),
    );
  }

  Widget _buildFriendsList(User currentUser) {
    return StreamBuilder<DocumentSnapshot>(
      // 1. Lắng nghe tài liệu của user hiện tại
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return const Center(child: Text('Đã xảy ra lỗi.'));
        }
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const Center(
            child: Text('Không tìm thấy dữ liệu người dùng.'),
          );
        }

        // 2. Lấy danh sách UID bạn bè từ trường 'friends'
        final data = snapshot.data!.data() as Map<String, dynamic>? ?? {};
        final List<String> friendUids = List<String>.from(
          data['friends'] ?? [],
        );

        // 3. Nếu danh sách rỗng, hiển thị thông báo
        if (friendUids.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.people_outline, size: 80, color: Colors.grey),
                SizedBox(height: 16),
                Text(
                  'Bạn chưa có bạn bè',
                  style: TextStyle(fontSize: 18, color: Colors.grey),
                ),
                Text(
                  'Hãy tìm và kết bạn để cùng chơi!',
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          );
        }

        // 4. Nếu có bạn bè, hiển thị ListView
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: friendUids.length,
          itemBuilder: (context, index) {
            final friendId = friendUids[index];
            // 5. Sử dụng một widget riêng để lấy thông tin của từng người bạn
            return _FriendTile(friendId: friendId);
          },
        );
      },
    );
  }
}

// --- WIDGET ĐỂ HIỂN THỊ THÔNG TIN MỘT NGƯỜI BẠN ---
class _FriendTile extends StatelessWidget {
  final String friendId;

  const _FriendTile({required this.friendId});

  @override
  Widget build(BuildContext context) {
    // Dùng FutureBuilder để lấy thông tin (tên, ảnh) của người bạn
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance
          .collection('users')
          .doc(friendId)
          .get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          // Hiển thị khung loading (skeleton)
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              leading: const CircleAvatar(backgroundColor: Colors.grey),
              title: Container(height: 16, color: Colors.grey.shade200),
              subtitle: Container(height: 12, color: Colors.grey.shade200),
            ),
          );
        }

        if (!snapshot.hasData || !snapshot.data!.exists) {
          // Xử lý trường hợp user đã bị xóa
          return const SizedBox.shrink();
        }

        // Lấy dữ liệu người bạn
        final data = snapshot.data!.data() as Map<String, dynamic>? ?? {};
        final displayName = data['displayName'] ?? 'Người dùng';
        final email = data['email'] ?? 'Không có email';
        final photoUrl = data['photoURL'] as String?;

        return Card(
          elevation: 2,
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: CircleAvatar(
              radius: 25,
              backgroundImage: (photoUrl != null)
                  ? NetworkImage(photoUrl)
                  : null,
              child: (photoUrl == null) ? const Icon(Icons.person) : null,
            ),
            title: Text(
              displayName,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(email),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              // Điều hướng đến trang hồ sơ khi bấm vào
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => UserProfileScreen(userId: friendId),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
