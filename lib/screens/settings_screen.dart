import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'sign_in_screen.dart';
import 'edit_profile_screen.dart'; // Import màn hình chỉnh sửa
import 'list_friends_screen.dart'; // THÊM MỚI: Import màn hình bạn bè

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Biến lưu trữ thông tin user
  final _currentUser = FirebaseAuth.instance.currentUser;

  // Cấu hình ImagePicker
  final _imagePicker = ImagePicker();

  // Hàm hiển thị Snackbar tập trung
  void _showSnackBar(String message, {Color color = Colors.red}) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
  }

  // Tên hàm rõ ràng hơn
  Future<void> _uploadAndSaveAvatar() async {
    if (_currentUser == null) return;

    try {
      final pickedFile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
      );

      if (pickedFile == null) return;

      final file = File(pickedFile.path);
      final ref = FirebaseStorage.instance.ref().child(
        'profile_pictures/${_currentUser.uid}/avatar.jpg',
      );

      await ref.putFile(file);
      final imageUrl = await ref.getDownloadURL();

      // Sử dụng Batch Write để cập nhật đồng thời
      final batch = FirebaseFirestore.instance.batch();
      final userDocRef = FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUser.uid);
      batch.update(userDocRef, {'photoURL': imageUrl});
      await batch.commit();

      await _currentUser.updatePhotoURL(imageUrl);
      await _currentUser.reload();

      _showSnackBar('Cập nhật avatar thành công!', color: Colors.green);
      // Cập nhật lại UI chính sau khi thay đổi
      setState(() {});
    } on FirebaseException catch (e) {
      _showSnackBar('Tải ảnh lên thất bại: ${e.message}');
    } catch (e) {
      _showSnackBar('Đã xảy ra lỗi không xác định: $e');
    }
  }

  // Hàm Đăng xuất
  Future<void> _handleSignOut() async {
    try {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const SignInScreen()),
        (Route<dynamic> route) => false,
      );
    } catch (e) {
      _showSnackBar('Đăng xuất thất bại: $e');
    }
  }

  // Hàm điều hướng đến màn hình chỉnh sửa
  Future<void> _navigateToEditProfile() async {
    final result = await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => const EditProfileScreen()));
    // Cập nhật lại màn hình khi trở về
    if (result == true) {
      await _currentUser?.reload();
      setState(() {});
    }
  }

  // Hàm hiển thị thông tin tài khoản
  void _showAccountInfo() {
    if (_currentUser == null) return;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter sheetSetState) {
            bool isUploading = false;
            // Dùng biến local để tránh gọi lại nhiều lần
            final user = FirebaseAuth.instance.currentUser;

            // Hàm con để xử lý logic upload ảnh và cập nhật UI cục bộ
            Future<void> handleAvatarTap() async {
              if (isUploading) return;
              sheetSetState(() => isUploading = true);
              await _uploadAndSaveAvatar();
              if (mounted) sheetSetState(() => isUploading = false);
            }

            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.5,
              minChildSize: 0.3,
              maxChildSize: 0.9,
              builder: (_, controller) => Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: ListView(
                  controller: controller,
                  children: [
                    // Handle trang trí
                    Align(
                      alignment: Alignment.center,
                      child: Container(
                        width: 40,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 15),
                    // Header của sheet
                    Row(
                      children: [
                        GestureDetector(
                          onTap: handleAvatarTap,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              CircleAvatar(
                                radius: 34,
                                backgroundColor: Colors.grey[200],
                                backgroundImage: user?.photoURL != null
                                    ? NetworkImage(user!.photoURL!)
                                    : null,
                                child: user?.photoURL == null
                                    ? const Icon(
                                        Icons.person,
                                        size: 34,
                                        color: Colors.grey,
                                      )
                                    : null,
                              ),
                              if (isUploading)
                                const CircularProgressIndicator(strokeWidth: 3),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                user?.displayName ?? 'No display name',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                user?.email ?? 'No email',
                                style: const TextStyle(color: Colors.grey),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: _handleSignOut,
                          icon: const Icon(Icons.logout, color: Colors.red),
                          tooltip: 'Sign Out',
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    // Các thông tin chi tiết
                    _buildAccountInfoCard(user),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1976D2),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        minimumSize: const Size.fromHeight(50),
                      ),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      // Cập nhật toàn bộ màn hình khi sheet đóng
      setState(() {});
    });
  }

  // Tách card thành một widget riêng để code clean hơn
  Widget _buildAccountInfoCard(User? user) {
    if (user == null) {
      return const SizedBox.shrink(); // Ẩn card nếu không có user
    }
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('Username'),
            subtitle: Text(user.displayName ?? '-'),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            leading: const Icon(Icons.email_outlined),
            title: const Text('Email'),
            subtitle: Text(user.email ?? '-'),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            leading: const Icon(Icons.fingerprint),
            title: const Text('UID'),
            subtitle: Text(user.uid, overflow: TextOverflow.ellipsis),
            onTap: () {
              Clipboard.setData(ClipboardData(text: user.uid));
              _showSnackBar('UID copied to clipboard');
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          children: <Widget>[
            _buildHeader(context),
            const SizedBox(height: 20),
            _buildSectionTitle('General'),
            _buildSettingItem(
              icon: Icons.person_outline,
              title: 'Account Information',
              onTap: _showAccountInfo, // Giữ nguyên chức năng cũ
            ),
            _buildSettingItem(
              icon: Icons.edit_outlined, // Icon mới
              title: 'Edit Profile', // Tên mới
              onTap: _navigateToEditProfile, // Thêm chức năng mới
            ),
            // === SỬA ĐỔI: THÊM MỤC DANH SÁCH BẠN BÈ ===
            _buildSettingItem(
              icon: Icons.people_outline, // Icon bạn bè
              title: 'Friend List', // Tên mục
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const ListFriendsScreen(),
                  ),
                );
              },
            ),
            const Divider(),
            _buildSectionTitle('Security'),
            _buildSettingItem(
              icon: Icons.lock_outline,
              title: 'Privacy & Security',
              onTap: () {},
            ),
            const Divider(),
            _buildSectionTitle('Support & Help'),
            _buildSettingItem(
              icon: Icons.help_outline,
              title: 'Help Center',
              onTap: () {},
            ),
            _buildSettingItem(
              icon: Icons.info_outline,
              title: 'About App',
              onTap: () {},
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  // Các widget con để xây dựng UI (không thay đổi)
  Widget _buildHeader(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 15, 20, 0),
        child: Row(
          children: [
            InkWell(
              onTap: () => Navigator.of(context).pop(),
              borderRadius: BorderRadius.circular(24),
              child: const Icon(
                Icons.arrow_back_ios,
                size: 24,
                color: Color.fromRGBO(7, 7, 112, 1),
              ),
            ),
            const SizedBox(width: 15),
            const Text(
              'Settings',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Color.fromRGBO(7, 7, 112, 1),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 25, 20, 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
      ),
    );
  }

  Widget _buildSettingItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFF1976D2)),
      title: Text(title, style: const TextStyle(fontSize: 16)),
      trailing: const Icon(
        Icons.arrow_forward_ios,
        size: 16,
        color: Colors.grey,
      ),
      onTap: onTap,
    );
  }
}
