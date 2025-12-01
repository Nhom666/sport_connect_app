import 'package:cloud_firestore/cloud_firestore.dart';

class ReputationUtils {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Hàm kiểm tra và tự động hồi phục điểm uy tín
  /// Trả về: true nếu ĐỦ ĐIỀU KIỆN (>= 50), false nếu BỊ CẤM (< 50)
  static Future<bool> checkAndRecoverReputation({
    required String targetId, // ID của Team hoặc User
    required String collection, // 'teams' hoặc 'users'
  }) async {
    final docRef = _firestore.collection(collection).doc(targetId);
    final snapshot = await docRef.get();

    if (!snapshot.exists) return true; // Không có dữ liệu coi như uy tín

    final data = snapshot.data() as Map<String, dynamic>;
    int currentScore = data['reputationScore'] ?? 100;

    // Nếu điểm >= 50 thì không cần làm gì cả, trả về true
    if (currentScore >= 50) return true;

    // --- LOGIC HỒI PHỤC ĐIỂM ---
    Timestamp? lastRecovery = data['lastRecoveryTime'];
    final now = DateTime.now();

    // Nếu chưa có mốc thời gian hồi phục, set mốc là bây giờ và vẫn chặn
    if (lastRecovery == null) {
      await docRef.update({'lastRecoveryTime': FieldValue.serverTimestamp()});
      return false;
    }

    final lastDate = lastRecovery.toDate();
    final difference = now.difference(lastDate);

    // Nếu đã qua 24 giờ
    if (difference.inHours >= 24) {
      // Tính số lần hồi phục (ví dụ user bỏ 48h thì hồi 2 lần)
      int cycles = difference.inHours ~/ 24;
      int pointsToRecover = 10 * cycles;

      int newScore = currentScore + pointsToRecover;

      // Giới hạn: Không hồi phục quá 100 (hoặc mức mặc định bạn muốn)
      if (newScore > 100) newScore = 100;

      // Cập nhật vào Firestore
      await docRef.update({
        'reputationScore': newScore,
        'lastRecoveryTime': FieldValue.serverTimestamp(), // Reset mốc thời gian
      });

      // Kiểm tra lại điểm mới sau khi hồi phục
      return newScore >= 50;
    }

    // Chưa đủ 24h và điểm vẫn thấp
    return false;
  }
}
