import 'package:cloud_firestore/cloud_firestore.dart';

class ReputationUtils {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Hàm kiểm tra và tự động hồi phục điểm uy tín (LAZY UPDATE)
  ///
  /// Hoạt động song song với Cloud Function:
  /// - Nếu Server đã cộng điểm -> App thấy điểm mới -> Không làm gì
  /// - Nếu Server chưa chạy -> App kiểm tra đủ 24h -> App tự cộng điểm ngay lập tức
  ///
  /// Trả về: true nếu ĐỦ ĐIỀU KIỆN (>= 50), false nếu BỊ CẤM (< 50)
  static Future<bool> checkAndRecoverReputation({
    required String targetId, // ID của Team hoặc User
    required String collection, // 'teams' hoặc 'users'
  }) async {
    final docRef = _firestore.collection(collection).doc(targetId);
    final snapshot = await docRef.get();

    if (!snapshot.exists) return true; // Không có dữ liệu coi như đủ điều kiện

    final data = snapshot.data() as Map<String, dynamic>;
    int currentScore = data['reputationScore'] ?? 100;

    // Nếu điểm >= 50 thì đủ điều kiện, không cần làm gì
    if (currentScore >= 50) return true;

    // --- LOGIC HỒI PHỤC ĐIỂM (LAZY UPDATE) ---
    Timestamp? lastRecovery = data['lastRecoveryTime'];
    final now = DateTime.now();

    // Nếu chưa có mốc thời gian hồi phục, set mốc là bây giờ và vẫn chặn
    if (lastRecovery == null) {
      await docRef.update({'lastRecoveryTime': FieldValue.serverTimestamp()});
      return false;
    }

    final lastDate = lastRecovery.toDate();
    final difference = now.difference(lastDate);

    // Nếu đã qua 24 giờ -> Cộng điểm ngay (không đợi Server)
    if (difference.inHours >= 24) {
      // Tính số chu kỳ 24h đã qua (ví dụ: 48h = 2 chu kỳ)
      int cycles = difference.inHours ~/ 24;
      int pointsToRecover = 10 * cycles; // 10 điểm mỗi chu kỳ

      int newScore = currentScore + pointsToRecover;

      // Giới hạn tối đa 100 điểm
      if (newScore > 100) newScore = 100;

      // Cập nhật vào Firestore ngay lập tức (Lazy Update)
      await docRef.update({
        'reputationScore': newScore,
        'lastRecoveryTime': FieldValue.serverTimestamp(), // Reset mốc thời gian
      });

      // Kiểm tra lại điểm mới sau khi hồi phục
      return newScore >= 50;
    }

    // Chưa đủ 24h và điểm vẫn < 50 -> Vẫn bị cấm
    return false;
  }
}
