// lib/screens/widgets/join_requests_section.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class JoinRequestsSection extends StatelessWidget {
  const JoinRequestsSection({super.key});

  // --- LOGIC XỬ LÝ ---

  void _acceptRequest(
    BuildContext context,
    String requestId,
    String teamId,
    String requesterId,
  ) async {
    try {
      final batch = FirebaseFirestore.instance.batch();

      // Thêm thành viên vào đội
      final teamRef = FirebaseFirestore.instance
          .collection('teams')
          .doc(teamId);
      batch.update(teamRef, {
        'members': FieldValue.arrayUnion([requesterId]),
      });

      // Cập nhật trạng thái của yêu cầu
      final requestRef = FirebaseFirestore.instance
          .collection('joinRequests')
          .doc(requestId);
      batch.update(requestRef, {'status': 'accepted'});

      await batch.commit();

      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Đã chấp nhận thành viên.')));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Lỗi khi chấp nhận: $e')));
    }
  }

  void _rejectRequest(BuildContext context, String requestId) async {
    try {
      await FirebaseFirestore.instance
          .collection('joinRequests')
          .doc(requestId)
          .update({'status': 'rejected'});

      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Đã từ chối thành viên.')));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Lỗi khi từ chối: $e')));
    }
  }

  // --- GIAO DIỆN ---

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('joinRequests')
          .where('ownerId', isEqualTo: currentUser.uid)
          .where('status', isEqualTo: 'pending')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink(); // Không hiển thị gì khi đang tải
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink(); // Không có thông báo
        }

        final requests = snapshot.data!.docs;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Notifications',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: requests.length,
                itemBuilder: (ctx, index) {
                  final request = requests[index];
                  final data = request.data() as Map<String, dynamic>;

                  // **PHẦN UI HOÀN CHỈNH BẮT ĐẦU TỪ ĐÂY**
                  return Card(
                    elevation: 2,
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          RichText(
                            text: TextSpan(
                              style: DefaultTextStyle.of(
                                ctx,
                              ).style.copyWith(fontSize: 15),
                              children: <TextSpan>[
                                TextSpan(
                                  text: data['requesterName'] ?? 'Một người',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const TextSpan(text: ' muốn tham gia vào đội '),
                                TextSpan(
                                  text: '"${data['teamName'] ?? 'của bạn'}"',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: () =>
                                    _rejectRequest(ctx, request.id),
                                child: const Text(
                                  'Từ chối',
                                  style: TextStyle(color: Colors.red),
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                onPressed: () => _acceptRequest(
                                  ctx,
                                  request.id,
                                  data['teamId'],
                                  data['requesterId'],
                                ),
                                child: const Text('Chấp nhận'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 18),
            ],
          ),
        );
      },
    );
  }
}
