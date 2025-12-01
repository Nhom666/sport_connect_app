import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../utils/constants.dart';
import '../widgets/rating_dialog.dart'; // Đảm bảo đường dẫn này đúng

enum JoinStatus {
  Loading,
  IsOwner,
  NotJoined,
  Pending,
  Joined,
  Declined,
  Cancelled,
}

class DetailsMatchScreen extends StatefulWidget {
  final DocumentSnapshot eventDoc;
  final String?
  viewingContextId; // ID của team/user đang xem sự kiện này (Context)

  const DetailsMatchScreen({
    Key? key,
    required this.eventDoc,
    this.viewingContextId, // Có thể null nếu xem từ discover (mặc định là User)
  }) : super(key: key);

  @override
  State<DetailsMatchScreen> createState() => _DetailsMatchScreenState();
}

class _DetailsMatchScreenState extends State<DetailsMatchScreen> {
  late Map<String, dynamic> _eventData;
  Future<Map<String, String>>? _organizerDetailsFuture;

  final _currentUser = FirebaseAuth.instance.currentUser;
  final _firestore = FirebaseFirestore.instance;
  JoinStatus _joinStatus = JoinStatus.Loading;

  // Set chứa các ID mà user hiện tại có quyền kiểm soát (UID cá nhân + ID các Team đã join/own)
  final Set<String> _myControlledIds = {};

  // Set chỉ chứa các ID Team mà user làm Owner (dùng để check quyền gửi request thay mặt team)
  final Set<String> _myOwnedTeamIds = {};

  Future<List<DocumentSnapshot>>? _ownedTeamsFuture;

  @override
  void initState() {
    super.initState();
    _eventData = widget.eventDoc.data() as Map<String, dynamic>;

    if (_currentUser != null) {
      _myControlledIds.add(_currentUser.uid);
    }

    // Lấy thông tin người tổ chức để hiển thị
    if (_eventData['organizerId'] != null) {
      final String organizerId = _eventData['organizerId'];
      final String creatorType = _eventData['creatorType'] ?? 'individual';

      if (creatorType == 'team') {
        _organizerDetailsFuture = _fetchOrganizerDetails(
          organizerId,
          'teams',
          'teamName',
        );
      } else {
        _organizerDetailsFuture = _fetchOrganizerDetails(
          organizerId,
          'users',
          'displayName',
        );
      }
    }

    _loadUserOwnedTeams();
    // Gọi check status lần đầu
    _checkJoinStatus();
  }

  // --- 1. HÀM TẢI THÔNG TIN TEAM CỦA USER ---
  void _loadUserOwnedTeams() async {
    if (_currentUser == null) return;

    // Giữ future để dùng cho dialog chọn team (chỉ load những team mình làm Owner)
    _ownedTeamsFuture = _firestore
        .collection('teams')
        .where('ownerId', isEqualTo: _currentUser.uid)
        .get()
        .then((snapshot) => snapshot.docs);

    try {
      // a. Lấy teams mà user là Owner
      final ownedSnapshot = await _firestore
          .collection('teams')
          .where('ownerId', isEqualTo: _currentUser.uid)
          .get();

      // b. Lấy teams mà user là Member (để biết mình thuộc về team nào, phục vụ logic hiển thị)
      final memberSnapshot = await _firestore
          .collection('teams')
          .where('memberIds', arrayContains: _currentUser.uid)
          .get();

      if (mounted) {
        setState(() {
          // Thêm owned teams
          for (var doc in ownedSnapshot.docs) {
            _myControlledIds.add(doc.id);
            _myOwnedTeamIds.add(doc.id);
          }

          // Thêm member teams vào controlledIds (nhưng không vào ownedIds)
          for (var doc in memberSnapshot.docs) {
            if (!_myControlledIds.contains(doc.id)) {
              _myControlledIds.add(doc.id);
            }
          }
        });
        // Gọi lại check status sau khi đã có đầy đủ danh sách ID
        _checkJoinStatus();
      }
    } catch (e) {
      print("Error loading teams: $e");
    }
  }

  // --- 2. HÀM KIỂM TRA TRẠNG THÁI THAM GIA ---
  Future<void> _checkJoinStatus() async {
    if (_currentUser == null) {
      setState(() => _joinStatus = JoinStatus.NotJoined);
      return;
    }

    // Xác định ID đang được dùng để xem màn hình này (User ID hoặc Team ID)
    final String currentContextId = widget.viewingContextId ?? _currentUser.uid;

    // A. Kiểm tra nếu context hiện tại là Owner của sự kiện
    if (_eventData['organizerId'] == currentContextId) {
      setState(() => _joinStatus = JoinStatus.IsOwner);
      return;
    }

    // B. Logic dự phòng: Nếu không có context cụ thể, kiểm tra xem user có sở hữu team tổ chức không
    if (widget.viewingContextId == null) {
      // Nếu user cá nhân là owner
      if (_eventData['organizerId'] == _currentUser.uid) {
        setState(() => _joinStatus = JoinStatus.IsOwner);
        return;
      }
      // Nếu một trong các team của user là owner
      if (_eventData['creatorType'] == 'team' &&
          _myOwnedTeamIds.contains(_eventData['organizerId'])) {
        setState(() => _joinStatus = JoinStatus.IsOwner);
        return;
      }
    }

    // C. Kiểm tra trạng thái Request (Pending/Joined/...)
    final List<String> idsToCheck = widget.viewingContextId != null
        ? [widget.viewingContextId!]
        : _myControlledIds.toList().take(10).toList();

    if (idsToCheck.isEmpty) {
      setState(() => _joinStatus = JoinStatus.NotJoined);
      return;
    }

    try {
      final existingRequest = await _firestore
          .collection('joinRequests')
          .where('eventId', isEqualTo: widget.eventDoc.id)
          .where('requesterId', whereIn: idsToCheck)
          .limit(1)
          .get();

      if (existingRequest.docs.isNotEmpty) {
        final doc = existingRequest.docs.first;
        final status = doc.data()['status'] as String?;

        switch (status) {
          case 'pending':
            setState(() => _joinStatus = JoinStatus.Pending);
            break;
          case 'accepted':
            setState(() => _joinStatus = JoinStatus.Joined);
            break;
          case 'regretted':
            setState(() => _joinStatus = JoinStatus.Declined);
            break;
          case 'cancelled':
            setState(() => _joinStatus = JoinStatus.Cancelled);
            break;
          default:
            setState(() => _joinStatus = JoinStatus.NotJoined);
        }
      } else {
        setState(() => _joinStatus = JoinStatus.NotJoined);
      }
    } catch (e) {
      print("Error checking join status: $e");
    }
  }

  // --- 3. LOGIC ĐÁNH GIÁ (RATING SYSTEM) ---

  bool _canReview(Timestamp? eventTime) {
    if (eventTime == null) return false;
    // Quy tắc: Chỉ được đánh giá sau khi sự kiện bắt đầu 1 tiếng
    final eventDateTime = eventTime.toDate();
    final reviewOpenTime = eventDateTime.add(const Duration(hours: 1));
    return DateTime.now().isAfter(reviewOpenTime);
  }

  // Widget hiển thị card đánh giá Host (Organizer)
  // --- ĐÃ SỬA: Thêm StreamBuilder để disable nút nếu đã đánh giá ---
  Widget _buildOrganizerRatingCard() {
    return FutureBuilder<Map<String, String>>(
      future: _organizerDetailsFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();

        final organizerName = snapshot.data!['name'] ?? 'Organizer';
        final organizerId = _eventData['organizerId'];

        final String creatorType = _eventData['creatorType'] ?? 'individual';
        final String targetTypeForDialog = (creatorType == 'team')
            ? 'team'
            : 'user';

        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          color: Colors.blue.shade50,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.blue.shade200),
          ),
          child: ListTile(
            leading: const CircleAvatar(
              backgroundColor: Colors.blue,
              child: Icon(Icons.star, color: Colors.white),
            ),
            title: Text(
              "Người tổ chức: $organizerName",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: const Text("Hãy đánh giá chủ sự kiện sau trận đấu."),
            trailing: StreamBuilder<QuerySnapshot>(
              // Kiểm tra xem đã có review nào từ mình cho organizer trong sự kiện này chưa
              stream: _firestore
                  .collection('reviews')
                  .where('eventId', isEqualTo: widget.eventDoc.id)
                  .where('reviewerId', isEqualTo: _currentUser!.uid)
                  .where('targetId', isEqualTo: organizerId)
                  .snapshots(),
              builder: (context, reviewSnapshot) {
                // Logic kiểm tra đã đánh giá chưa
                bool hasRated = false;
                if (reviewSnapshot.hasData &&
                    reviewSnapshot.data!.docs.isNotEmpty) {
                  hasRated = true;
                }

                if (reviewSnapshot.connectionState == ConnectionState.waiting) {
                  return const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  );
                }

                return ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    // Đổi màu xám nếu đã đánh giá
                    backgroundColor: hasRated ? Colors.grey : Colors.blue,
                    disabledBackgroundColor: Colors.grey,
                  ),
                  // Disable nút (null) nếu đã đánh giá
                  onPressed: hasRated
                      ? null
                      : () {
                          showDialog(
                            context: context,
                            builder: (context) => RatingDialog(
                              eventId: widget.eventDoc.id,
                              reviewerId: _currentUser!.uid,
                              targetId: organizerId,
                              targetName: organizerName,
                              targetType: targetTypeForDialog,
                            ),
                          );
                        },
                  child: Text(
                    hasRated ? "Đã đánh giá" : "Đánh giá",
                    style: const TextStyle(color: Colors.white),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  // Widget hiển thị danh sách người tham gia để đánh giá
  // --- ĐÃ SỬA: Thêm StreamBuilder cho từng item trong list ---
  Widget _buildReviewSection() {
    bool hasViewPermission =
        _joinStatus == JoinStatus.IsOwner || _joinStatus == JoinStatus.Joined;

    if (!hasViewPermission) {
      return const SizedBox.shrink();
    }

    bool canRate = true;
    if (widget.viewingContextId != null && _joinStatus != JoinStatus.IsOwner) {
      canRate = _myOwnedTeamIds.contains(widget.viewingContextId);
    }

    Timestamp? eventTime = _eventData['eventTime'];

    if (!canRate) {
      return Container(
        margin: const EdgeInsets.only(top: 20),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.blue.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.blue.shade200),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline, color: Colors.blue),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                "Bạn là thành viên của team tham gia. Chỉ Captain mới có quyền gửi đánh giá.",
                style: TextStyle(color: Colors.blue[800], fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    if (!_canReview(eventTime)) {
      return Container(
        margin: const EdgeInsets.only(top: 20),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.orange.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.orange.shade200),
        ),
        child: Row(
          children: [
            const Icon(Icons.lock_clock, color: Colors.orange),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                "Chức năng đánh giá uy tín sẽ mở sau 1 tiếng kể từ lúc sự kiện bắt đầu.",
                style: TextStyle(color: Colors.orange[800], fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 24, bottom: 8),
          child: Text(
            "Đánh giá uy tín",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),

        if (_joinStatus == JoinStatus.Joined &&
            _joinStatus != JoinStatus.IsOwner)
          _buildOrganizerRatingCard(),

        const Text(
          "Các bên tham gia khác:",
          style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey),
        ),
        const SizedBox(height: 8),

        StreamBuilder<QuerySnapshot>(
          stream: _firestore
              .collection('joinRequests')
              .where('eventId', isEqualTo: widget.eventDoc.id)
              .where('status', isEqualTo: 'accepted')
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text("Chưa có bên tham gia nào khác."),
              );
            }

            final docs = snapshot.data!.docs;

            // Lọc bỏ chính mình khỏi danh sách
            final otherParticipants = docs.where((doc) {
              final data = doc.data() as Map<String, dynamic>;
              final reqId = data['requesterId'];

              if (widget.viewingContextId != null) {
                return reqId != widget.viewingContextId;
              }
              return !_myControlledIds.contains(reqId);
            }).toList();

            if (otherParticipants.isEmpty) {
              return const Text(
                "Không có đối thủ/đồng đội nào khác để đánh giá.",
                style: TextStyle(
                  fontStyle: FontStyle.italic,
                  color: Colors.grey,
                ),
              );
            }

            return ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: otherParticipants.length,
              separatorBuilder: (ctx, i) => const Divider(),
              itemBuilder: (context, index) {
                final data =
                    otherParticipants[index].data() as Map<String, dynamic>;

                final requesterName = data['requesterName'] ?? 'Unknown';
                final requesterId = data['requesterId'];

                final String rawType = data['requesterType'] ?? 'individual';
                final String normalizedType = (rawType == 'team')
                    ? 'team'
                    : 'user';
                final bool isTeam = normalizedType == 'team';

                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: isTeam
                        ? Colors.blue.shade100
                        : Colors.green.shade100,
                    child: isTeam
                        ? const Icon(Icons.groups, color: Colors.blue)
                        : Text(
                            requesterName.isNotEmpty
                                ? requesterName[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                  title: Text(
                    requesterName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(isTeam ? "Team tham gia" : "Cá nhân tham gia"),
                  trailing: StreamBuilder<QuerySnapshot>(
                    // Check xem mình đã đánh giá đối tượng này chưa
                    stream: _firestore
                        .collection('reviews')
                        .where('eventId', isEqualTo: widget.eventDoc.id)
                        .where('reviewerId', isEqualTo: _currentUser!.uid)
                        .where('targetId', isEqualTo: requesterId)
                        .snapshots(),
                    builder: (context, reviewSnapshot) {
                      bool hasRated = false;
                      if (reviewSnapshot.hasData &&
                          reviewSnapshot.data!.docs.isNotEmpty) {
                        hasRated = true;
                      }

                      if (reviewSnapshot.connectionState ==
                          ConnectionState.waiting) {
                        return const SizedBox(
                          width: 50,
                          height: 30,
                          child: Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        );
                      }

                      return ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          // Màu xám nếu đã đánh giá, màu cam nếu chưa
                          backgroundColor: hasRated
                              ? Colors.grey
                              : Colors.orange,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.grey,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          elevation: 0,
                        ),
                        // Disable nút nếu đã đánh giá
                        onPressed: hasRated
                            ? null
                            : () {
                                showDialog(
                                  context: context,
                                  builder: (context) => RatingDialog(
                                    eventId: widget.eventDoc.id,
                                    reviewerId: _currentUser!.uid,
                                    targetId: requesterId,
                                    targetName: requesterName,
                                    targetType: normalizedType,
                                  ),
                                );
                              },
                        child: Text(hasRated ? "Đã đánh giá" : "Đánh giá"),
                      );
                    },
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }

  // --- 4. CÁC HÀM XỬ LÝ JOIN EVENT ---

  Future<void> _onJoinPressed() async {
    final creatorType = _eventData['creatorType'] ?? 'individual';
    final newEventTime = _eventData['eventTime'] as Timestamp?;

    if (newEventTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lỗi: Sự kiện này không có thời gian.')),
      );
      return;
    }

    setState(() => _joinStatus = JoinStatus.Loading);

    // Nếu sự kiện là Individual, User có thể join trực tiếp
    if (creatorType == 'individual') {
      bool hasConflict = await _checkScheduleConflict(
        _currentUser!.uid,
        newEventTime,
      );
      if (hasConflict) {
        _showConflictDialog();
        setState(() => _joinStatus = JoinStatus.NotJoined);
        return;
      }

      final userData = await _firestore
          .collection('users')
          .doc(_currentUser.uid)
          .get();
      _sendJoinRequest(
        requesterId: _currentUser.uid,
        requesterName: userData.data()?['displayName'] ?? 'Unknown User',
        requesterType: 'individual',
      );
    } else {
      // Nếu sự kiện là Team, bắt buộc phải chọn Team để join
      setState(() => _joinStatus = JoinStatus.NotJoined);
      _showTeamSelectionDialog(newEventTime);
    }
  }

  // Kiểm tra trùng lịch
  Future<bool> _checkScheduleConflict(
    String entityId,
    Timestamp newEventTime,
  ) async {
    final Timestamp? newEventEndTime = _eventData['eventEndTime'];
    if (newEventEndTime == null) {
      final newEnd = newEventTime.toDate().add(const Duration(hours: 2));
      return _checkScheduleConflictWithTimes(
        entityId,
        newEventTime.toDate(),
        newEnd,
      );
    }
    return _checkScheduleConflictWithTimes(
      entityId,
      newEventTime.toDate(),
      newEventEndTime.toDate(),
    );
  }

  Future<bool> _checkScheduleConflictWithTimes(
    String entityId,
    DateTime newStart,
    DateTime newEnd,
  ) async {
    try {
      final joinedRequests = await _firestore
          .collection('joinRequests')
          .where('requesterId', isEqualTo: entityId)
          .where('status', isEqualTo: 'accepted')
          .get();

      for (final doc in joinedRequests.docs) {
        final data = doc.data();
        final existingStartTime = (data['eventTime'] as Timestamp?)?.toDate();
        Timestamp? existingEndTimestamp = data['eventEndTime'] as Timestamp?;
        DateTime? existingEndTime;

        if (existingEndTimestamp != null) {
          existingEndTime = existingEndTimestamp.toDate();
        } else if (existingStartTime != null) {
          existingEndTime = existingStartTime.add(const Duration(hours: 2));
        }

        if (existingStartTime != null && existingEndTime != null) {
          if (_isTimeOverlapping(
            newStart,
            newEnd,
            existingStartTime,
            existingEndTime,
          )) {
            return true;
          }
        }
      }

      final organizedEvents = await _firestore
          .collection('events')
          .where('organizerId', isEqualTo: entityId)
          .get();

      for (final doc in organizedEvents.docs) {
        final data = doc.data();
        final existingStartTime = (data['eventTime'] as Timestamp?)?.toDate();
        final existingEndTime = (data['eventEndTime'] as Timestamp?)?.toDate();

        if (existingStartTime != null && existingEndTime != null) {
          if (_isTimeOverlapping(
            newStart,
            newEnd,
            existingStartTime,
            existingEndTime,
          )) {
            return true;
          }
        }
      }

      return false;
    } catch (e) {
      print("Lỗi kiểm tra trùng lịch: $e");
      return false;
    }
  }

  bool _isTimeOverlapping(
    DateTime start1,
    DateTime end1,
    DateTime start2,
    DateTime end2,
  ) {
    return !(end1.isBefore(start2) ||
        end1.isAtSameMomentAs(start2) ||
        end2.isBefore(start1) ||
        end2.isAtSameMomentAs(start1));
  }

  void _showConflictDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bị trùng lịch'),
        content: const Text(
          'Trùng lịch với một sự kiện khác bạn đã tham gia/tổ chức.',
        ),
        actions: [
          TextButton(
            child: const Text('OK'),
            onPressed: () => Navigator.of(ctx).pop(),
          ),
        ],
      ),
    );
  }

  void _showTeamSelectionDialog(Timestamp newEventTime) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return FutureBuilder<List<DocumentSnapshot>>(
          future: _ownedTeamsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                height: 200,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(24),
                child: const Text(
                  'Bạn cần là Captain (Owner) của một Team để tham gia sự kiện dành cho Team.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16),
                ),
              );
            }

            final teams = snapshot.data!;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text(
                    'Chọn Team để gửi yêu cầu',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                ListView.separated(
                  shrinkWrap: true,
                  itemCount: teams.length,
                  separatorBuilder: (ctx, index) => const Divider(),
                  itemBuilder: (context, index) {
                    final team = teams[index];
                    final teamName = team['teamName'] ?? 'Unnamed Team';
                    final teamSport = team['sport'] ?? '';
                    final eventSport = _eventData['sport'] ?? '';

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.blue.shade50,
                        child: const Icon(
                          Icons.groups,
                          color: Color(0xFF1976D2),
                        ),
                      ),
                      title: Text(
                        teamName,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text('Môn: $teamSport'),
                      onTap: () async {
                        // Check môn thể thao
                        if (teamSport != eventSport) {
                          Navigator.of(context).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Team "$teamName" chuyên môn $teamSport, không khớp với $eventSport.',
                              ),
                              backgroundColor: Colors.red,
                            ),
                          );
                          return;
                        }

                        Navigator.of(context).pop();
                        setState(() => _joinStatus = JoinStatus.Loading);

                        bool hasConflict = await _checkScheduleConflict(
                          team.id,
                          newEventTime,
                        );
                        if (hasConflict) {
                          _showConflictDialog();
                          setState(() => _joinStatus = JoinStatus.NotJoined);
                          return;
                        }

                        _sendJoinRequest(
                          requesterId: team.id,
                          requesterName: teamName,
                          requesterType: 'team',
                        );
                      },
                    );
                  },
                ),
                const SizedBox(height: 20),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _sendJoinRequest({
    required String requesterId,
    required String requesterName,
    required String requesterType,
  }) async {
    if (_currentUser == null) return;

    try {
      await _firestore.collection('joinRequests').add({
        'eventId': widget.eventDoc.id,
        'eventName': _eventData['eventName'] ?? 'No Title',
        'eventTime': _eventData['eventTime'],
        'eventEndTime': _eventData['eventEndTime'],
        'eventOwnerId': _eventData['organizerId'],
        'eventLocationName': _eventData['locationName'] ?? 'Unknown',
        'eventSport': _eventData['sport'] ?? 'Unknown',
        'requesterId': requesterId,
        'requesterName': requesterName,
        'requesterType': requesterType,
        'status': 'pending',
        'requestedAt': FieldValue.serverTimestamp(),
      });

      setState(() => _joinStatus = JoinStatus.Pending);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đã gửi yêu cầu tham gia!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      setState(() => _joinStatus = JoinStatus.NotJoined);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Gửi yêu cầu thất bại: $e')));
    }
  }

  Future<Map<String, String>> _fetchOrganizerDetails(
    String id,
    String collection,
    String nameField,
  ) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection(collection)
          .doc(id)
          .get();
      if (doc.exists) {
        final data = doc.data()!;
        final name = data[nameField] ?? 'Unknown';
        if (collection == 'users') {
          final email = data['email'] ?? 'No email';
          return {'name': name, 'detail': email};
        } else {
          return {'name': name, 'detail': 'Team'};
        }
      }
      return {'name': 'Unknown', 'detail': 'Unknown'};
    } catch (e) {
      return {'name': 'Error', 'detail': e.toString()};
    }
  }

  String _formatEventTime(Timestamp? timestamp) {
    if (timestamp == null) return '';
    final dateTime = timestamp.toDate();
    final formatter = DateFormat('h:mm a - EEEE, MMM d, yyyy');
    return formatter.format(dateTime);
  }

  String _getSportVisual(String? sportName) {
    switch (sportName) {
      case 'Bóng đá':
        return '⚽️';
      case 'Bóng chuyền':
        return '🏐';
      case 'Bóng rổ':
        return '🏀';
      case 'Bóng bàn':
        return '🏓';
      case 'Cầu lông':
        return '🏸';
      case 'Tennis':
        return '🎾';
      default:
        return '🏆';
    }
  }

  @override
  Widget build(BuildContext context) {
    String sport = _eventData['sport'] ?? 'Unknown';
    String sportEmoji = _getSportVisual(sport);
    String location = _eventData['locationName'] ?? 'No location';
    String title = _eventData['eventName'] ?? 'No Title';
    String imageUrl = _eventData['imageUrl'] ?? '';
    String creatorType = (_eventData['creatorType'] ?? 'individual')
        .toString()
        .capitalize();
    Timestamp? eventTime = _eventData['eventTime'];
    Timestamp? eventEndTime = _eventData['eventEndTime'];
    String skillLevel = _eventData['skillLevel'] ?? 'Không rõ';

    return Scaffold(
      backgroundColor: kWhiteColor,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 250.0,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                ),
              ),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.cover,
                    placeholder: (context, url) =>
                        Container(color: Colors.grey[200]),
                    errorWidget: (context, url, error) =>
                        const Icon(Icons.error),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.7),
                        ],
                        stops: const [0.5, 1.0],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildListDelegate([
              Padding(
                padding: const EdgeInsets.all(kDefaultPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildDetailTile(
                      Icons.sports_soccer,
                      'Môn thể thao',
                      sport,
                      emoji: sportEmoji,
                    ),
                    _buildDetailTile(
                      Icons.leaderboard_outlined,
                      'Trình độ',
                      skillLevel,
                    ),
                    _buildDetailTile(
                      Icons.access_time,
                      'Thời gian bắt đầu',
                      _formatEventTime(eventTime),
                    ),
                    if (eventEndTime != null)
                      _buildDetailTile(
                        Icons.access_time_filled,
                        'Thời gian kết thúc',
                        _formatEventTime(eventEndTime),
                      ),
                    _buildDetailTile(Icons.location_on, 'Địa điểm', location),
                    FutureBuilder<Map<String, String>>(
                      future: _organizerDetailsFuture,
                      builder: (context, snapshot) {
                        String organizerText = 'Loading...';
                        IconData icon = creatorType == 'Team'
                            ? Icons.groups
                            : Icons.person;

                        if (snapshot.hasData) {
                          final details = snapshot.data!;
                          final name = details['name']!;
                          final detail = details['detail']!;
                          organizerText = creatorType == 'Team'
                              ? '$name (Team)'
                              : '$name ($detail)';
                        } else if (snapshot.hasError) {
                          organizerText = 'Unknown ($creatorType)';
                        }

                        return _buildDetailTile(icon, 'Tạo bởi', organizerText);
                      },
                    ),
                    const SizedBox(height: 24),
                    _buildJoinButton(),

                    const SizedBox(height: 16),
                    const Divider(thickness: 1),
                    _buildReviewSection(),

                    const SizedBox(height: 50),
                  ],
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildJoinButton() {
    final buttonStyle = ElevatedButton.styleFrom(
      padding: const EdgeInsets.symmetric(vertical: 16),
      shape: RoundedRectangleBorder(borderRadius: kDefaultBorderRadius),
      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
    );

    switch (_joinStatus) {
      case JoinStatus.Loading:
        return const Center(child: CircularProgressIndicator());

      case JoinStatus.IsOwner:
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: kDefaultBorderRadius,
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.edit_calendar, color: Colors.grey),
              SizedBox(width: 8),
              Text(
                'Bạn là người tổ chức sự kiện này',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );

      case JoinStatus.Pending:
        return SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.hourglass_top),
            label: const Text('Đã gửi yêu cầu (Pending)'),
            style: buttonStyle.copyWith(
              backgroundColor: MaterialStateProperty.all(Colors.orange),
              foregroundColor: MaterialStateProperty.all(Colors.white),
            ),
            onPressed: null,
          ),
        );

      case JoinStatus.Joined:
        return SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.check_circle),
            label: const Text('Đã tham gia (Joined)'),
            style: buttonStyle.copyWith(
              backgroundColor: MaterialStateProperty.all(Colors.green),
              foregroundColor: MaterialStateProperty.all(Colors.white),
            ),
            onPressed: null,
          ),
        );

      case JoinStatus.Declined:
        return SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.cancel),
            label: const Text('Yêu cầu bị từ chối (Declined)'),
            style: buttonStyle.copyWith(
              backgroundColor: MaterialStateProperty.all(Colors.red),
              foregroundColor: MaterialStateProperty.all(Colors.white),
            ),
            onPressed: null,
          ),
        );
      case JoinStatus.Cancelled:
        return SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.block),
            label: const Text('Đã hủy (Cancelled)'),
            style: buttonStyle.copyWith(
              backgroundColor: MaterialStateProperty.all(Colors.grey),
              foregroundColor: MaterialStateProperty.all(Colors.white),
            ),
            onPressed: null,
          ),
        );

      case JoinStatus.NotJoined:
        return SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _onJoinPressed,
            style: buttonStyle.copyWith(
              backgroundColor: MaterialStateProperty.all(
                const Color(0xFF1976D2),
              ),
              foregroundColor: MaterialStateProperty.all(Colors.white),
            ),
            child: const Text('Gửi yêu cầu tham gia'),
          ),
        );
    }
  }

  Widget _buildDetailTile(
    IconData icon,
    String title,
    String subtitle, {
    String? emoji,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor: kAccentColor.withOpacity(0.1),
            radius: 24,
            child: (emoji != null)
                ? Text(emoji, style: const TextStyle(fontSize: 24))
                : Icon(icon, color: kAccentColor, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 17,
                    color: kBlackColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

extension StringExtension on String {
  String capitalize() {
    if (isEmpty) return this;
    return "${this[0].toUpperCase()}${substring(1).toLowerCase()}";
  }
}
