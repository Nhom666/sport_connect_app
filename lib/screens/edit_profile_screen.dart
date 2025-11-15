// edit_profile_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/custom_dropdown_widget.dart'; // Import widget mới

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  final _usernameController = TextEditingController();
  String? _selectedLevel;
  String? _selectedSport;
  List<String> _selectedSchedules = [];

  final List<String> _levels = ['Sơ cấp', 'Trung cấp', 'Chuyên nghiệp'];
  final List<String> _sports = [
    'Bóng đá',
    'Bóng chuyền',
    'Bóng rổ',
    'Bóng bàn',
    'Cầu lông',
    'Tennis',
  ];
  final List<String> _schedules = [
    'Sáng (T2-T6)',
    'Chiều (T2-T6)',
    'Tối (T2-T6)',
    'Cuối tuần',
  ];

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final user = _auth.currentUser;
    if (user != null) {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (doc.exists) {
        final data = doc.data()!;
        _usernameController.text = user.displayName ?? '';
        setState(() {
          _selectedLevel = data['level'];
          _selectedSport = data['favoriteSport'];
          _selectedSchedules = List<String>.from(data['freeSchedules'] ?? []);
        });
      }
    }
  }

  Future<void> _updateProfile() async {
    setState(() {
      _isLoading = true;
    });

    final user = _auth.currentUser;
    if (user == null) {
      _showSnackBar('Không tìm thấy người dùng.', Colors.red);
      setState(() {
        _isLoading = false;
      });
      return;
    }

    try {
      await user.updateDisplayName(_usernameController.text);

      await _firestore.collection('users').doc(user.uid).update({
        'displayName': _usernameController.text,
        'level': _selectedLevel,
        'favoriteSport': _selectedSport,
        'freeSchedules': _selectedSchedules,
      });

      await user.reload();

      _showSnackBar('Cập nhật thông tin thành công!', Colors.green);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on FirebaseException catch (e) {
      _showSnackBar('Cập nhật thất bại: ${e.message}', Colors.red);
    } catch (e) {
      _showSnackBar('Đã xảy ra lỗi: $e', Colors.red);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context),
            _isLoading
                ? const Center(child: CircularProgressIndicator())
                : Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Tên người dùng',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _usernameController,
                          decoration: InputDecoration(
                            hintText: 'Nhập tên của bạn',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                            fillColor: Colors.grey[200],
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        // Sử dụng widget tùy chỉnh mới
                        CustomDropdownWidget(
                          title: 'Môn thể thao yêu thích',
                          items: _sports,
                          selectedItem: _selectedSport,
                          onChanged: (value) {
                            setState(() {
                              _selectedSport = value;
                            });
                          },
                        ),
                        const SizedBox(height: 20),
                        CustomDropdownWidget(
                          title: 'Trình độ',
                          items: _levels,
                          selectedItem: _selectedLevel,
                          onChanged: (value) {
                            setState(() {
                              _selectedLevel = value;
                            });
                          },
                        ),
                        const SizedBox(height: 20),
                        _buildCheckboxSection(
                          'Lịch trình rảnh rỗi',
                          _schedules,
                        ),
                        const SizedBox(height: 30),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _updateProfile,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1976D2),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: const Text(
                              'Lưu thay đổi',
                              style: TextStyle(fontSize: 18),
                            ),
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

  // Các widget con khác (như _buildHeader và _buildCheckboxSection) giữ nguyên
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
              'Chỉnh sửa hồ sơ',
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

  Widget _buildCheckboxSection(String title, List<String> options) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 5,
          children: options.map((option) {
            final isSelected = _selectedSchedules.contains(option);
            return ChoiceChip(
              label: Text(option),
              selected: isSelected,
              onSelected: (selected) {
                setState(() {
                  if (selected) {
                    _selectedSchedules.add(option);
                  } else {
                    _selectedSchedules.remove(option);
                  }
                });
              },
              selectedColor: const Color(0xFF1976D2),
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : Colors.black87,
              ),
              backgroundColor: Colors.grey[200],
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: isSelected
                      ? const Color(0xFF1976D2)
                      : Colors.grey.shade400,
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
