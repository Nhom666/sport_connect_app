// import 'package:flutter/material.dart';
// import 'package:cloud_firestore/cloud_firestore.dart';

// class RatingDialog extends StatefulWidget {
//   final String eventId;
//   final String reviewerId; // Người đánh giá (thường là Host)
//   final String targetUserId; // Người bị đánh giá (User tham gia)
//   final String targetUserName;

//   const RatingDialog({
//     Key? key,
//     required this.eventId,
//     required this.reviewerId,
//     required this.targetUserId,
//     required this.targetUserName,
//   }) : super(key: key);

//   @override
//   State<RatingDialog> createState() => _RatingDialogState();
// }

// class _RatingDialogState extends State<RatingDialog> {
//   String _selectedReason = 'no_show'; // Mặc định chọn cái đầu tiên
//   final TextEditingController _commentController = TextEditingController();
//   bool _isLoading = false;

//   Future<void> _submitRating() async {
//     setState(() => _isLoading = true);
//     final firestore = FirebaseFirestore.instance;

//     try {
//       // 1. Tạo Review trong collection 'reviews'
//       await firestore.collection('reviews').add({
//         'eventId': widget.eventId,
//         'reviewerId': widget.reviewerId,
//         'targetUserId': widget.targetUserId,
//         'reason': _selectedReason, // 'no_show', 'late', 'good'
//         'comment': _commentController.text.trim(),
//         'createdAt': FieldValue.serverTimestamp(),
//       });

//       // 2. Tính toán điểm thay đổi
//       // - Bùng kèo: -20
//       // - Đi muộn: -5
//       // - Đúng hẹn: +5 (Hồi phục)
//       int scoreChange = 0;
//       if (_selectedReason == 'no_show') {
//         scoreChange = -20;
//       } else if (_selectedReason == 'late') {
//         scoreChange = -5;
//       } else if (_selectedReason == 'good') {
//         scoreChange = 5; // CỘNG ĐIỂM
//       }

//       // Cập nhật User
//       final userRef = firestore.collection('users').doc(widget.targetUserId);

//       // Dùng transaction để đảm bảo tính toàn vẹn dữ liệu (tránh xung đột khi nhiều người đánh giá cùng lúc)
//       await firestore.runTransaction((transaction) async {
//         final snapshot = await transaction.get(userRef);
//         if (!snapshot.exists) return;

//         // Lấy dữ liệu hiện tại (nếu chưa có thì set mặc định)
//         final currentScore = snapshot.data()?['reputationScore'] ?? 100;
//         final currentNoShow = snapshot.data()?['noShowCount'] ?? 0;
//         final currentLate = snapshot.data()?['lateCount'] ?? 0;
//         final currentGood = snapshot.data()?['goodCount'] ?? 0;

//         // Tính điểm mới
//         int newScore = currentScore + scoreChange;

//         // --- LOGIC QUAN TRỌNG: GIỚI HẠN ĐIỂM (0 - 100) ---
//         if (newScore > 100) newScore = 100; // Không được vượt quá 100
//         if (newScore < 0) newScore = 0; // Không được thấp hơn 0

//         transaction.update(userRef, {
//           'reputationScore': newScore,
//           'noShowCount': _selectedReason == 'no_show'
//               ? currentNoShow + 1
//               : currentNoShow,
//           'lateCount': _selectedReason == 'late'
//               ? currentLate + 1
//               : currentLate,
//           'goodCount': _selectedReason == 'good'
//               ? currentGood + 1
//               : currentGood, // Tăng biến đếm uy tín
//         });
//       });

//       if (mounted) {
//         Navigator.of(context).pop(); // Đóng dialog
//         ScaffoldMessenger.of(context).showSnackBar(
//           const SnackBar(content: Text('Đã gửi đánh giá thành công!')),
//         );
//       }
//     } catch (e) {
//       ScaffoldMessenger.of(
//         context,
//       ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
//     } finally {
//       if (mounted) setState(() => _isLoading = false);
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     return AlertDialog(
//       title: Text('Đánh giá: ${widget.targetUserName}'),
//       content: SingleChildScrollView(
//         child: Column(
//           mainAxisSize: MainAxisSize.min,
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             const Text('Người này đã tham gia sự kiện như thế nào?'),
//             const SizedBox(height: 10),

//             // Radio: Bùng kèo
//             RadioListTile<String>(
//               title: const Text('Vắng mặt (No-show)'),
//               subtitle: const Text('Trừ 20 điểm uy tín'),
//               value: 'no_show',
//               groupValue: _selectedReason,
//               activeColor: Colors.red,
//               onChanged: (val) => setState(() => _selectedReason = val!),
//             ),

//             // Radio: Đi muộn
//             RadioListTile<String>(
//               title: const Text('Đến muộn (Late)'),
//               subtitle: const Text('Trừ 5 điểm uy tín'),
//               value: 'late',
//               groupValue: _selectedReason,
//               onChanged: (val) => setState(() => _selectedReason = val!),
//             ),

//             // Radio: Uy tín (ĐÃ CẬP NHẬT UI)
//             RadioListTile<String>(
//               title: const Text('Tham gia đúng hẹn'),
//               subtitle: const Text('Cộng 5 điểm uy tín (Hồi phục)'),
//               value: 'good',
//               groupValue: _selectedReason,
//               activeColor: Colors.green,
//               onChanged: (val) => setState(() => _selectedReason = val!),
//             ),

//             const SizedBox(height: 10),
//             TextField(
//               controller: _commentController,
//               decoration: const InputDecoration(
//                 labelText: 'Nhận xét thêm (tuỳ chọn)',
//                 border: OutlineInputBorder(),
//               ),
//               maxLines: 2,
//             ),
//           ],
//         ),
//       ),
//       actions: [
//         TextButton(
//           onPressed: () => Navigator.of(context).pop(),
//           child: const Text('Hủy'),
//         ),
//         ElevatedButton(
//           onPressed: _isLoading ? null : _submitRating,
//           style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
//           child: _isLoading
//               ? const SizedBox(
//                   width: 20,
//                   height: 20,
//                   child: CircularProgressIndicator(
//                     color: Colors.white,
//                     strokeWidth: 2,
//                   ),
//                 )
//               : const Text(
//                   'Gửi đánh giá',
//                   style: TextStyle(color: Colors.white),
//                 ),
//         ),
//       ],
//     );
//   }
// }

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class RatingDialog extends StatefulWidget {
  final String eventId;
  final String reviewerId;
  final String targetId; // Đổi tên từ targetUserId -> targetId cho tổng quát
  final String targetName; // Đổi tên từ targetUserName -> targetName
  final String targetType; // THÊM MỚI: 'user' hoặc 'team'

  const RatingDialog({
    Key? key,
    required this.eventId,
    required this.reviewerId,
    required this.targetId,
    required this.targetName,
    required this.targetType, // Bắt buộc truyền loại đối tượng
  }) : super(key: key);

  @override
  State<RatingDialog> createState() => _RatingDialogState();
}

class _RatingDialogState extends State<RatingDialog> {
  String _selectedReason = 'no_show';
  final TextEditingController _commentController = TextEditingController();
  bool _isLoading = false;

  Future<void> _submitRating() async {
    setState(() => _isLoading = true);
    final firestore = FirebaseFirestore.instance;

    try {
      // 1. Tạo Review trong collection 'reviews'
      // Lưu thêm targetType để biết review này dành cho team hay user
      await firestore.collection('reviews').add({
        'eventId': widget.eventId,
        'reviewerId': widget.reviewerId,
        'targetId': widget.targetId,
        'targetType': widget.targetType, // Lưu loại đối tượng
        'reason': _selectedReason,
        'comment': _commentController.text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      // 2. Tính toán điểm thay đổi
      int scoreChange = 0;
      if (_selectedReason == 'no_show') {
        scoreChange = -20;
      } else if (_selectedReason == 'late') {
        scoreChange = -5;
      } else if (_selectedReason == 'good') {
        scoreChange = 5;
      }

      // --- LOGIC MỚI: XÁC ĐỊNH COLLECTION DỰA VÀO TARGET TYPE ---
      final String collectionPath = widget.targetType == 'team'
          ? 'teams'
          : 'users';
      final docRef = firestore.collection(collectionPath).doc(widget.targetId);

      // Dùng transaction để cập nhật điểm
      await firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(docRef);
        if (!snapshot.exists) return; // Nếu team/user không tồn tại thì bỏ qua

        // Lấy dữ liệu hiện tại (nếu chưa có thì set mặc định 100)
        final currentScore = snapshot.data()?['reputationScore'] ?? 100;
        final currentNoShow = snapshot.data()?['noShowCount'] ?? 0;
        final currentLate = snapshot.data()?['lateCount'] ?? 0;
        final currentGood = snapshot.data()?['goodCount'] ?? 0;

        // Tính điểm mới
        int newScore = currentScore + scoreChange;

        // Giới hạn điểm (0 - 100)
        if (newScore > 100) newScore = 100;
        if (newScore < 0) newScore = 0;

        transaction.update(docRef, {
          'reputationScore': newScore,
          'noShowCount': _selectedReason == 'no_show'
              ? currentNoShow + 1
              : currentNoShow,
          'lateCount': _selectedReason == 'late'
              ? currentLate + 1
              : currentLate,
          'goodCount': _selectedReason == 'good'
              ? currentGood + 1
              : currentGood,
        });
      });

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Đã gửi đánh giá cho ${widget.targetType == 'team' ? 'Team' : 'User'} thành công!',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Đánh giá: ${widget.targetName}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hiển thị rõ đang đánh giá Team hay User
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: widget.targetType == 'team'
                    ? Colors.blue[100]
                    : Colors.green[100],
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                widget.targetType == 'team'
                    ? 'Đánh giá Team'
                    : 'Đánh giá Cá nhân',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: widget.targetType == 'team'
                      ? Colors.blue[800]
                      : Colors.green[800],
                ),
              ),
            ),
            const SizedBox(height: 10),
            const Text('Đối tượng này đã tham gia sự kiện như thế nào?'),
            const SizedBox(height: 10),

            RadioListTile<String>(
              title: const Text('Vắng mặt (No-show)'),
              subtitle: const Text('Trừ 20 điểm uy tín'),
              value: 'no_show',
              groupValue: _selectedReason,
              activeColor: Colors.red,
              onChanged: (val) => setState(() => _selectedReason = val!),
            ),

            RadioListTile<String>(
              title: const Text('Đến muộn (Late)'),
              subtitle: const Text('Trừ 5 điểm uy tín'),
              value: 'late',
              groupValue: _selectedReason,
              onChanged: (val) => setState(() => _selectedReason = val!),
            ),

            RadioListTile<String>(
              title: const Text('Tham gia đúng hẹn'),
              subtitle: const Text('Cộng 5 điểm uy tín (Hồi phục)'),
              value: 'good',
              groupValue: _selectedReason,
              activeColor: Colors.green,
              onChanged: (val) => setState(() => _selectedReason = val!),
            ),

            const SizedBox(height: 10),
            TextField(
              controller: _commentController,
              decoration: const InputDecoration(
                labelText: 'Nhận xét thêm (tuỳ chọn)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _submitRating,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : const Text(
                  'Gửi đánh giá',
                  style: TextStyle(color: Colors.white),
                ),
        ),
      ],
    );
  }
}
