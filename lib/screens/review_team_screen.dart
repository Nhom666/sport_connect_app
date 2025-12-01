import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

const Color kPrimaryColor = Color.fromRGBO(7, 7, 112, 1);

class ReviewTeamScreen extends StatefulWidget {
  final String teamId;

  const ReviewTeamScreen({Key? key, required this.teamId}) : super(key: key);

  @override
  State<ReviewTeamScreen> createState() => _ReviewTeamScreenState();
}

class _ReviewTeamScreenState extends State<ReviewTeamScreen> {
  // Hàm lấy màu dựa trên điểm số
  Color _getScoreColor(int score) {
    if (score >= 90) return Colors.green;
    if (score >= 75) return Colors.blue;
    if (score >= 50) return Colors.orange;
    return Colors.red;
  }

  // Hàm hiển thị text lý do đánh giá
  String _getReasonText(String reason) {
    switch (reason) {
      case 'good':
        return 'Đúng hẹn';
      case 'late':
        return 'Đến muộn';
      case 'no_show':
        return 'Vắng mặt';
      default:
        return reason;
    }
  }

  // Hàm lấy màu cho lý do
  Color _getReasonColor(String reason) {
    switch (reason) {
      case 'good':
        return Colors.green;
      case 'late':
        return Colors.orange;
      case 'no_show':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text(
          "Reviews Of Team",
          style: TextStyle(color: kPrimaryColor, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: kPrimaryColor),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // PHẦN 1: THÔNG TIN TỔNG QUAN TEAM
            _buildTeamHeader(),

            const SizedBox(height: 16),

            // Tiêu đề danh sách
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "Lịch sử đánh giá",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ),

            // PHẦN 2: DANH SÁCH REVIEW
            _buildReviewsList(),
          ],
        ),
      ),
    );
  }

  Widget _buildTeamHeader() {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('teams')
          .doc(widget.teamId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox(
            height: 200,
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final data = snapshot.data!.data() as Map<String, dynamic>?;
        if (data == null)
          return const Center(child: Text("Không tìm thấy dữ liệu Team"));

        final int reputationScore = data['reputationScore'] ?? 100;
        final int goodCount = data['goodCount'] ?? 0;
        final int lateCount = data['lateCount'] ?? 0;
        final int noShowCount = data['noShowCount'] ?? 0;
        final String teamName = data['teamName'] ?? 'Unnamed Team';
        final String imageUrl = data['imageUrl'] ?? '';

        return Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                children: [
                  // Avatar Team
                  Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.grey.shade200),
                      image: imageUrl.isNotEmpty
                          ? DecorationImage(
                              image: NetworkImage(imageUrl),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: imageUrl.isEmpty
                        ? const Icon(Icons.groups, size: 40, color: Colors.grey)
                        : null,
                  ),
                  const SizedBox(width: 16),

                  // Tên Team & Score
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          teamName,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: _getScoreColor(
                              reputationScore,
                            ).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            "Điểm uy tín: $reputationScore",
                            style: TextStyle(
                              color: _getScoreColor(reputationScore),
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),

              // 3 Cột thống kê
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatItem("Đúng hẹn", goodCount, Colors.green),
                  _buildStatItem("Đến muộn", lateCount, Colors.orange),
                  _buildStatItem("Vắng mặt", noShowCount, Colors.red),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatItem(String label, int count, Color color) {
    return Column(
      children: [
        Text(
          count.toString(),
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildReviewsList() {
    return StreamBuilder<QuerySnapshot>(
      // Query collection 'reviews' lấy đúng targetId và targetType là 'team'
      stream: FirebaseFirestore.instance
          .collection('reviews')
          .where('targetId', isEqualTo: widget.teamId)
          .where(
            'targetType',
            isEqualTo: 'team',
          ) // Quan trọng: chỉ lấy review của team
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.only(top: 20),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(40),
            alignment: Alignment.center,
            child: Column(
              children: const [
                Icon(Icons.rate_review_outlined, size: 50, color: Colors.grey),
                SizedBox(height: 10),
                Text(
                  "Chưa có đánh giá nào.",
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          shrinkWrap: true,
          physics:
              const NeverScrollableScrollPhysics(), // Để scroll chung với parent
          padding: const EdgeInsets.all(16),
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            final doc = snapshot.data!.docs[index];
            final data = doc.data() as Map<String, dynamic>;

            return _buildReviewItem(data);
          },
        );
      },
    );
  }

  Widget _buildReviewItem(Map<String, dynamic> reviewData) {
    final String reason = reviewData['reason'] ?? 'good';
    final String comment = reviewData['comment'] ?? '';
    final String reviewerId = reviewData['reviewerId'] ?? '';
    final Timestamp? createdAt = reviewData['createdAt'];

    final String dateString = createdAt != null
        ? DateFormat('dd/MM/yyyy HH:mm').format(createdAt.toDate())
        : 'Unknown Date';

    // Cần fetch thông tin người review (Tên, Avatar) từ collection 'users'
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance
          .collection('users')
          .doc(reviewerId)
          .get(),
      builder: (context, userSnapshot) {
        String reviewerName = "Người dùng ẩn danh";
        String? reviewerImage;

        if (userSnapshot.hasData && userSnapshot.data!.exists) {
          final userData = userSnapshot.data!.data() as Map<String, dynamic>;
          reviewerName = userData['displayName'] ?? reviewerName;
          reviewerImage = userData['photoUrl']; // Hoặc tên field chứa ảnh
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundImage:
                        (reviewerImage != null && reviewerImage.isNotEmpty)
                        ? NetworkImage(reviewerImage)
                        : null,
                    backgroundColor: Colors.blue.shade100,
                    child: (reviewerImage == null || reviewerImage.isEmpty)
                        ? Text(
                            reviewerName.isNotEmpty
                                ? reviewerName[0].toUpperCase()
                                : '?',
                            style: const TextStyle(color: Colors.blue),
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          reviewerName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          dateString,
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Chip hiển thị lý do (Đến muộn/Đúng giờ...)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _getReasonColor(reason).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _getReasonColor(reason).withOpacity(0.3),
                      ),
                    ),
                    child: Text(
                      _getReasonText(reason),
                      style: TextStyle(
                        color: _getReasonColor(reason),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              if (comment.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    comment,
                    style: const TextStyle(fontSize: 14, color: Colors.black87),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
