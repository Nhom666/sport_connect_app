import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../utils/constants.dart';
import '../utils/reputation_utils.dart';
// import 'user_profile_screen.dart'; // Giữ lại nếu cần dùng

enum JoinStatus {
  Loading,
  IsOwner,
  NotJoined,
  Pending,
  Joined,
  Declined,
  Cancelled,
}

class EventDetailScreen extends StatefulWidget {
  final DocumentSnapshot eventDoc;
  const EventDetailScreen({Key? key, required this.eventDoc}) : super(key: key);

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  late Map<String, dynamic> _eventData;
  Future<Map<String, String>>? _organizerDetailsFuture;

  final _currentUser = FirebaseAuth.instance.currentUser;
  final _firestore = FirebaseFirestore.instance;
  JoinStatus _joinStatus = JoinStatus.Loading;
  Future<List<DocumentSnapshot>>? _ownedTeamsFuture;

  @override
  void initState() {
    super.initState();
    _eventData = widget.eventDoc.data() as Map<String, dynamic>;

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
    _checkJoinStatus();
  }

  void _loadUserOwnedTeams() {
    if (_currentUser == null) return;
    _ownedTeamsFuture = _firestore
        .collection('teams')
        .where('ownerId', isEqualTo: _currentUser.uid)
        .get()
        .then((snapshot) => snapshot.docs);
  }

  Future<void> _checkJoinStatus() async {
    if (_currentUser == null) {
      setState(() => _joinStatus = JoinStatus.NotJoined);
      return;
    }
    if (_eventData['organizerId'] == _currentUser.uid) {
      setState(() => _joinStatus = JoinStatus.IsOwner);
      return;
    }
    if (_eventData['creatorType'] == 'team' &&
        _eventData['organizerId'] != null) {
      final teamDoc = await _firestore
          .collection('teams')
          .doc(_eventData['organizerId'])
          .get();
      if (teamDoc.data()?['ownerId'] == _currentUser.uid) {
        setState(() => _joinStatus = JoinStatus.IsOwner);
        return;
      }
    }

    List<String> myRequesterIds = [_currentUser.uid];
    final ownedTeams = await _ownedTeamsFuture;
    if (ownedTeams != null) {
      myRequesterIds.addAll(ownedTeams.map((doc) => doc.id));
    }

    final existingRequest = await _firestore
        .collection('joinRequests')
        .where('eventId', isEqualTo: widget.eventDoc.id)
        .where('requesterId', whereIn: myRequesterIds)
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
        case 'cancelled': // Xử lý trường hợp Cancelled
          setState(() => _joinStatus = JoinStatus.Cancelled);
          break;
        default:
          setState(() => _joinStatus = JoinStatus.NotJoined);
      }
    } else {
      setState(() => _joinStatus = JoinStatus.NotJoined);
    }
  }

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

    if (creatorType == 'individual') {
      // 1. Nếu sự kiện là CÁ NHÂN -> Gửi yêu cầu từ cá nhân
      bool isAllowed = await ReputationUtils.checkAndRecoverReputation(
        targetId: _currentUser!.uid,
        collection: 'users',
      );

      if (!isAllowed) {
        setState(() => _joinStatus = JoinStatus.NotJoined);
        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Điểm uy tín quá thấp!'),
              content: Text(
                '${_currentUser!.displayName} hiện có điểm uy tín dưới 50 nên bị cấm tham gia sự kiện.\n\n'
                'Hệ thống sẽ tự động hồi phục 10 điểm mỗi 24 giờ.\n'
                'Vui lòng quay lại sau.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Đã hiểu'),
                ),
              ],
            ),
          );
        }
        return;
      }
      // --- (BẮT ĐẦU KIỂM TRA XUNG ĐỘT) ---
      bool hasConflict = await _checkScheduleConflict(
        _currentUser!.uid,
        newEventTime,
      );
      if (hasConflict) {
        _showConflictDialog();
        setState(() => _joinStatus = JoinStatus.NotJoined);
        return;
      }
      // --- (KẾT THÚC KIỂM TRA) ---

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
      // 2. Nếu sự kiện là TEAM -> Hiển thị bảng chọn team
      setState(() => _joinStatus = JoinStatus.NotJoined); // Tắt loading
      _showTeamSelectionDialog(newEventTime);
    }
  }

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
          'Trùng lịch với một sự kiện khác bạn đã tham gia, hãy tôn trọng partner của mình.',
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

  // --- ĐÃ CẬP NHẬT: HÀM NÀY ĐỂ KIỂM TRA SPORT ---
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
                  'Bạn phải là chủ sở hữu (owner) của một đội để có thể gửi yêu cầu tham gia sự kiện của đội khác.',
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
                    'Chọn đội của bạn để gửi yêu cầu',
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
                    // Lấy sport của team
                    final teamSport = team['sport'] ?? '';
                    // Lấy sport của event
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
                      subtitle: Text(
                        'Môn: $teamSport',
                      ), // Hiển thị môn để user dễ thấy
                      onTap: () async {
                        // --- CHECK 1: Kiểm tra môn thể thao ---
                        if (teamSport != eventSport) {
                          Navigator.of(context).pop(); // Đóng dialog
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Team "$teamName" đang chơi môn $teamSport, không thể tham gia sự kiện $eventSport.',
                              ),
                              backgroundColor: Colors.red,
                              duration: const Duration(seconds: 3),
                            ),
                          );
                          return; // Dừng lại, không thực hiện tiếp
                        }

                        // Nếu môn thể thao khớp, tiếp tục các logic cũ
                        Navigator.of(context).pop(); // Đóng dialog
                        setState(
                          () => _joinStatus = JoinStatus.Loading,
                        ); // Bật loading

                        // --- [MỚI] CHECK 2: KIỂM TRA UY TÍN TEAM ---
                        bool isAllowed =
                            await ReputationUtils.checkAndRecoverReputation(
                              targetId: team.id,
                              collection: 'teams',
                            );

                        if (!isAllowed) {
                          setState(() => _joinStatus = JoinStatus.NotJoined);
                          if (mounted) {
                            showDialog(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Điểm uy tín quá thấp!'),
                                content: Text(
                                  '$teamName hiện có điểm uy tín dưới 50 nên bị cấm tham gia sự kiện.\n\n'
                                  'Hệ thống sẽ tự động hồi phục 10 điểm mỗi 24 giờ.\n'
                                  'Vui lòng quay lại sau.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.of(ctx).pop(),
                                    child: const Text('Đã hiểu'),
                                  ),
                                ],
                              ),
                            );
                          }
                          return;
                        }

                        // --- CHECK 3: Kiểm tra xung đột lịch ---
                        bool hasConflict = await _checkScheduleConflict(
                          team.id,
                          newEventTime,
                        );
                        if (hasConflict) {
                          _showConflictDialog();
                          setState(() => _joinStatus = JoinStatus.NotJoined);
                          return;
                        }

                        // Gửi yêu cầu
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
        'eventEndTime': _eventData['eventEndTime'], // Lưu thêm nếu cần
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
                            ? Icons.group
                            : Icons.person;

                        if (snapshot.hasData) {
                          final details = snapshot.data!;
                          final name = details['name']!;
                          final detail = details['detail']!;
                          if (creatorType == 'Team') {
                            organizerText = '$name (Team)';
                          } else {
                            organizerText = '$name ($detail)';
                          }
                        } else if (snapshot.hasError) {
                          organizerText = 'Unknown ($creatorType)';
                        }

                        return _buildDetailTile(icon, 'Tạo bởi', organizerText);
                      },
                    ),
                    const SizedBox(height: 24),
                    _buildJoinButton(),
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
    switch (_joinStatus) {
      case JoinStatus.Loading:
        return const Center(child: CircularProgressIndicator());

      case JoinStatus.IsOwner:
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: kDefaultBorderRadius,
          ),
          child: const Center(
            child: Text(
              'Bạn là người tổ chức sự kiện này',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ),
        );

      case JoinStatus.Pending:
        return SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.hourglass_top),
            label: const Text('Đã gửi yêu cầu (Pending)'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: kDefaultBorderRadius),
              textStyle: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
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
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: kDefaultBorderRadius),
              textStyle: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
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
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: kDefaultBorderRadius),
              textStyle: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
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
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.grey, // Hoặc Colors.red
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: kDefaultBorderRadius),
              textStyle: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            onPressed: null,
          ),
        );

      case JoinStatus.NotJoined:
        return SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _onJoinPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1976D2),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: kDefaultBorderRadius),
            ),
            child: const Text(
              'Gửi yêu cầu tham gia',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
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
