import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'user_profile_screen.dart';
import '../utils/constants.dart';
import 'details_match_screen.dart';
import 'review_team_screen.dart';
import '../service/notification_service.dart';
import '../service/alarm_notification_service.dart';

class ScheduleTeamScreen extends StatefulWidget {
  final String teamId;
  final String teamName;
  final bool isUserOwner;

  const ScheduleTeamScreen({
    super.key,
    required this.teamId,
    this.teamName = 'Team Schedule',
    required this.isUserOwner,
  });

  @override
  State<ScheduleTeamScreen> createState() => _ScheduleTeamScreenState();
}

class _ScheduleTeamScreenState extends State<ScheduleTeamScreen> {
  final _firestore = FirebaseFirestore.instance;

  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    // Khởi tạo notification service
    _initNotifications();
  }

  Future<void> _initNotifications() async {
    final notificationService = NotificationService();
    await notificationService.init();
    await notificationService.requestPermissions();

    // Khởi tạo AlarmNotificationService
    final alarmService = AlarmNotificationService();
    await alarmService.init();

    // Lắng nghe các request của team này được accept
    _listenForAcceptedRequests();
  }

  void _listenForAcceptedRequests() {
    // Lắng nghe joinRequests mà team này là requester và được accept
    _firestore
        .collection('joinRequests')
        .where('requesterId', isEqualTo: widget.teamId)
        .where('status', isEqualTo: 'accepted')
        .snapshots()
        .listen((snapshot) {
          for (var change in snapshot.docChanges) {
            if (change.type == DocumentChangeType.modified ||
                change.type == DocumentChangeType.added) {
              final data = change.doc.data();
              if (data != null) {
                final eventId = data['eventId'] as String?;
                final eventName = data['eventName'] as String? ?? 'Sự kiện';
                final eventTime = data['eventTime'] as Timestamp?;
                final requesterId = data['requesterId'] as String?;
                final eventOwnerId = data['eventOwnerId'] as String?;

                if (eventId != null && eventTime != null) {
                  // Lên lịch thông báo cho TẤT CẢ members của 2 team
                  _scheduleNotificationsForBothTeams(
                    eventId: eventId,
                    eventName: eventName,
                    eventTime: eventTime.toDate(),
                    requesterTeamId: requesterId,
                    ownerTeamId: eventOwnerId,
                  );
                }
              }
            }
          }
        });
  }

  // Hàm lên lịch thông báo cho tất cả members của 2 team
  Future<void> _scheduleNotificationsForBothTeams({
    required String eventId,
    required String eventName,
    required DateTime eventTime,
    String? requesterTeamId,
    String? ownerTeamId,
  }) async {
    final alarmService = AlarmNotificationService();
    final teamsToNotify = <String>[];

    if (requesterTeamId != null) teamsToNotify.add(requesterTeamId);
    if (ownerTeamId != null) teamsToNotify.add(ownerTeamId);

    print(
      '🔔 [Team] Gửi thông báo cho ${teamsToNotify.length} team(s): $eventName',
    );

    for (String teamId in teamsToNotify) {
      try {
        // Lấy danh sách members của team
        final teamDoc = await _firestore.collection('teams').doc(teamId).get();
        if (teamDoc.exists) {
          final teamData = teamDoc.data();
          final members = teamData?['members'] as List<dynamic>?;

          if (members != null && members.isNotEmpty) {
            // Gửi thông báo cho từng member
            for (var member in members) {
              final memberId = member['uid'] as String?;
              if (memberId != null) {
                await alarmService.scheduleEventReminders(
                  eventId: '${eventId}_${memberId}',
                  eventName: eventName,
                  eventTime: eventTime,
                );
              }
            }
            print(
              '✅ Đã lên lịch alarm cho ${members.length} members của team $teamId',
            );
          }
        }
      } catch (e) {
        print('❌ Lỗi khi lên lịch cho team $teamId: $e');
      }
    }
  }

  Future<void> _refreshData() async {
    setState(() {});
    return;
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

  String _formatEventDateHeader(Timestamp? timestamp) {
    if (timestamp == null) return 'Unknown Date';
    return DateFormat('EEEE, dd/MM/yyyy').format(timestamp.toDate());
  }

  DateTime _normalizeDate(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(
              Icons.arrow_back_ios,
              size: 20,
              color: Color.fromRGBO(7, 7, 112, 1),
            ),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text(
            'Schedule: ${widget.teamName}',
            style: const TextStyle(
              color: Color.fromRGBO(7, 7, 112, 1),
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          bottom: const TabBar(
            labelColor: Colors.black,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Colors.blue,
            labelStyle: TextStyle(fontWeight: FontWeight.bold),
            tabs: [
              Tab(text: 'Timeline View'),
              Tab(text: 'Calendar View'),
            ],
          ),
          backgroundColor: Colors.white,
          elevation: 1,
        ),
        body: TabBarView(
          children: [_buildTimelineView(), _buildCalendarView()],
        ),
      ),
    );
  }

  Widget _buildTimelineView() {
    final incomingStream = _firestore
        .collection('joinRequests')
        .where('eventOwnerId', isEqualTo: widget.teamId)
        .snapshots();

    final outgoingStream = _firestore
        .collection('joinRequests')
        .where('requesterId', isEqualTo: widget.teamId)
        .snapshots();

    return StreamBuilder<QuerySnapshot>(
      stream: incomingStream,
      builder: (context, incomingSnapshot) {
        return StreamBuilder<QuerySnapshot>(
          stream: outgoingStream,
          builder: (context, outgoingSnapshot) {
            if (!incomingSnapshot.hasData || !outgoingSnapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final allRequests = <DocumentSnapshot>[
              ...incomingSnapshot.data!.docs,
              ...outgoingSnapshot.data!.docs,
            ];

            final filteredRequests = allRequests.where((doc) {
              final data = doc.data() as Map<String, dynamic>;
              // Chỉ hiện request liên quan đến team
              final bool matchType = data['requesterType'] == 'team';
              return matchType;
            }).toList();

            filteredRequests.sort((a, b) {
              Timestamp? aTime = (a.data() as Map)['eventTime'];
              Timestamp? bTime = (b.data() as Map)['eventTime'];
              if (aTime == null || bTime == null) return 0;
              return bTime.compareTo(aTime);
            });

            return Column(
              children: [
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _refreshData,
                    child: (filteredRequests.isEmpty)
                        ? ListView(
                            children: const [
                              Center(
                                child: Padding(
                                  padding: EdgeInsets.all(40),
                                  child: Text(
                                    'Team này chưa có lịch thi đấu nào.',
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                ),
                              ),
                            ],
                          )
                        : _buildGroupedListView(filteredRequests),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildGroupedListView(List<DocumentSnapshot> requests) {
    String? lastDateHeader;
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(kDefaultPadding),
      itemCount: requests.length,
      itemBuilder: (context, index) {
        final doc = requests[index];
        final data = doc.data() as Map<String, dynamic>;
        Widget headerWidget = const SizedBox.shrink();
        final currentDateHeader = _formatEventDateHeader(data['eventTime']);

        if (currentDateHeader != lastDateHeader) {
          headerWidget = _buildDateHeader(currentDateHeader);
          lastDateHeader = currentDateHeader;
        }

        final bool isIncoming = data['eventOwnerId'] == widget.teamId;

        return Column(
          children: [
            headerWidget,
            _ScheduleItemCard(
              joinRequestDoc: doc,
              isIncoming: isIncoming,
              getSportVisual: _getSportVisual,
              isMyTeamOwner: widget.isUserOwner,
            ),
          ],
        );
      },
    );
  }

  Widget _buildDateHeader(String dateText) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      margin: const EdgeInsets.only(top: 16, bottom: 16),
      decoration: BoxDecoration(
        color: kAccentColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        dateText,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
      ),
    );
  }

  Widget _buildCalendarView() {
    final incomingStream = _firestore
        .collection('joinRequests')
        .where('eventOwnerId', isEqualTo: widget.teamId)
        .snapshots();
    final outgoingStream = _firestore
        .collection('joinRequests')
        .where('requesterId', isEqualTo: widget.teamId)
        .snapshots();

    return StreamBuilder<QuerySnapshot>(
      stream: incomingStream,
      builder: (context, incomingSnapshot) {
        return StreamBuilder<QuerySnapshot>(
          stream: outgoingStream,
          builder: (context, outgoingSnapshot) {
            if (!incomingSnapshot.hasData || !outgoingSnapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final allRequests = <DocumentSnapshot>[
              ...incomingSnapshot.data!.docs,
              ...outgoingSnapshot.data!.docs,
            ];

            final filteredAllRequests = allRequests.where((doc) {
              final data = doc.data() as Map<String, dynamic>;
              return data['requesterType'] == 'team';
            }).toList();

            final eventsByDay = <DateTime, List<DocumentSnapshot>>{};
            for (final doc in filteredAllRequests) {
              final data = doc.data() as Map<String, dynamic>;
              final eventTime = data['eventTime'] as Timestamp?;
              if (eventTime != null) {
                final day = _normalizeDate(eventTime.toDate());
                if (eventsByDay[day] == null) eventsByDay[day] = [];
                eventsByDay[day]!.add(doc);
              }
            }

            final selectedDayEvents =
                eventsByDay[_normalizeDate(_selectedDay!)] ?? [];

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () {
                        setState(() {
                          final now = DateTime.now();
                          _selectedDay = now;
                          _focusedDay = now;
                        });
                      },
                      child: const Text(
                        'Go to Today', // Đồng bộ text với ScheduleScreen
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                    ),
                  ),
                ),
                TableCalendar(
                  firstDay: DateTime.utc(2020, 1, 1),
                  lastDay: DateTime.utc(2030, 12, 31),
                  focusedDay: _focusedDay,
                  calendarFormat: _calendarFormat,
                  selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                  onDaySelected: (selectedDay, focusedDay) {
                    setState(() {
                      _selectedDay = selectedDay;
                      _focusedDay = focusedDay;
                    });
                  },
                  onFormatChanged: (format) =>
                      setState(() => _calendarFormat = format),
                  eventLoader: (day) => eventsByDay[_normalizeDate(day)] ?? [],
                  calendarBuilders: CalendarBuilders(
                    markerBuilder: (context, day, events) {
                      if (events.isEmpty) return null;
                      return Positioned(
                        bottom: 1,
                        child: Container(
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: kAccentColor,
                          ),
                          width: 6,
                          height: 6,
                        ),
                      );
                    },
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _refreshData,
                    child: (selectedDayEvents.isEmpty)
                        ? ListView(
                            children: const [
                              Center(
                                child: Padding(
                                  padding: EdgeInsets.all(20),
                                  child: Text('Không có lịch vào ngày này.'),
                                ),
                              ),
                            ],
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(kDefaultPadding),
                            itemCount: selectedDayEvents.length,
                            itemBuilder: (context, index) {
                              final doc = selectedDayEvents[index];
                              final data = doc.data() as Map<String, dynamic>;
                              final bool isIncoming =
                                  data['eventOwnerId'] == widget.teamId;
                              return _ScheduleItemCard(
                                joinRequestDoc: doc,
                                isIncoming: isIncoming,
                                getSportVisual: _getSportVisual,
                                isMyTeamOwner: widget.isUserOwner,
                              );
                            },
                          ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

// --- ITEM CARD: ĐÃ CẬP NHẬT GIAO DIỆN GIỐNG SCHEDULE_SCREEN ---
class _ScheduleItemCard extends StatelessWidget {
  final DocumentSnapshot joinRequestDoc;
  final bool isIncoming;
  final String Function(String?) getSportVisual;
  final bool isMyTeamOwner;

  const _ScheduleItemCard({
    required this.joinRequestDoc,
    required this.isIncoming,
    required this.getSportVisual,
    required this.isMyTeamOwner,
  });

  void _navigateToEventDetails(
    BuildContext context,
    String eventId,
    String? contextId,
  ) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const Center(child: CircularProgressIndicator()),
      );
      final eventDoc = await FirebaseFirestore.instance
          .collection('events')
          .doc(eventId)
          .get();
      if (!context.mounted) return;
      Navigator.of(context).pop();

      if (eventDoc.exists) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => DetailsMatchScreen(
              eventDoc: eventDoc,
              viewingContextId: contextId,
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Sự kiện không tồn tại.')));
      }
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context).pop();
      print(e);
    }
  }

  Future<void> _updateRequestStatus(String status) async {
    await joinRequestDoc.reference.update({'status': status});

    // Lên lịch thông báo khi accept - gửi cho TẤT CẢ members của 2 team
    if (status == 'accepted') {
      final data = joinRequestDoc.data() as Map<String, dynamic>;
      final eventId = data['eventId'] as String?;
      final eventName = data['eventName'] as String? ?? 'Sự kiện';
      final eventTime = data['eventTime'] as Timestamp?;
      final requesterId = data['requesterId'] as String?;
      final eventOwnerId = data['eventOwnerId'] as String?;

      if (eventId != null && eventTime != null) {
        final alarmService = AlarmNotificationService();
        final firestore = FirebaseFirestore.instance;
        final teamsToNotify = <String>[];

        if (requesterId != null) teamsToNotify.add(requesterId);
        if (eventOwnerId != null) teamsToNotify.add(eventOwnerId);

        print(
          '🔔 [Accept] Gửi thông báo cho ${teamsToNotify.length} team(s): $eventName',
        );

        for (String teamId in teamsToNotify) {
          try {
            // Lấy danh sách members của team
            final teamDoc = await firestore
                .collection('teams')
                .doc(teamId)
                .get();
            if (teamDoc.exists) {
              final teamData = teamDoc.data();
              final members = teamData?['members'] as List<dynamic>?;

              if (members != null && members.isNotEmpty) {
                // Gửi thông báo cho từng member
                for (var member in members) {
                  final memberId = member['uid'] as String?;
                  if (memberId != null) {
                    await alarmService.scheduleEventReminders(
                      eventId: '${eventId}_${memberId}',
                      eventName: eventName,
                      eventTime: eventTime.toDate(),
                    );
                  }
                }
                print(
                  '✅ Đã lên lịch alarm cho ${members.length} members của team $teamId',
                );
              }
            }
          } catch (e) {
            print('❌ Lỗi khi lên lịch cho team $teamId: $e');
          }
        }
      }
    }
  }

  // --- HÀM TẠO NÚT TRẠNG THÁI FLAT (Đồng bộ với Schedule Screen) ---
  Widget _buildStatusChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
      ),
    );
  }

  void _viewRequesterInfo(
    BuildContext context,
    String requesterId,
    String requesterType,
  ) {
    if (requesterType == 'individual') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => UserProfileScreen(userId: requesterId),
        ),
      );
    } else {
      // Đã sửa: Chuyển hướng sang ReviewTeamScreen khi requesterType là team
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ReviewTeamScreen(teamId: requesterId),
        ),
      );
    }
  }

  void _showActionSheet(BuildContext context, Map<String, dynamic> data) {
    final String requesterName = data['requesterName'] ?? 'Unknown';

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      backgroundColor: Colors.white,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Yêu cầu từ $requesterName',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Chấp nhận hoặc từ chối yêu cầu tham gia sự kiện.',
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  textAlign: TextAlign.center,
                ),
                const Divider(height: 32),
                ListTile(
                  leading: const Icon(Icons.check_circle, color: Colors.green),
                  title: const Text(
                    'Chấp nhận (Accept)',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                  onTap: () {
                    _updateRequestStatus('accepted');
                    Navigator.of(ctx).pop();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.cancel, color: Colors.red),
                  title: const Text(
                    'Từ chối (Regret)',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                  onTap: () {
                    _updateRequestStatus('regretted');
                    Navigator.of(ctx).pop();
                  },
                ),
                ListTile(
                  leading: Icon(Icons.info, color: Colors.blue[700]),
                  title: Text(
                    'Xem thông tin $requesterName',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue[700],
                    ),
                  ),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _viewRequesterInfo(
                      context,
                      data['requesterId'],
                      data['requesterType'],
                    );
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = joinRequestDoc.data() as Map<String, dynamic>;

    final String eventName = data['eventName'] ?? 'No Title';
    final String location = data['eventLocationName'] ?? 'Chưa cập nhật vị trí';
    final String sport = data['eventSport'] ?? 'Other';
    final Timestamp? eventTime = data['eventTime'];
    final String status = data['status'] ?? 'pending';
    final String? eventId = data['eventId'];

    final String timeString = (eventTime != null)
        ? DateFormat('HH:mm').format(eventTime.toDate())
        : '--:--';
    final String sportVisual = getSportVisual(sport);

    Widget statusButton;

    // --- LOGIC HIỂN THỊ NÚT (Đã cập nhật style) ---
    if (status == 'accepted') {
      statusButton = _buildStatusChip('MATCHED', Colors.green);
    } else if (status == 'pending') {
      if (isIncoming) {
        if (isMyTeamOwner) {
          // Nút Duyệt cho Captain: Style Action xanh nhạt giống Schedule Screen
          statusButton = InkWell(
            onTap: () => _showActionSheet(context, data),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Action',
                    style: TextStyle(
                      color: Colors.blue,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  SizedBox(width: 4),
                  Icon(Icons.keyboard_arrow_down, color: Colors.blue, size: 16),
                ],
              ),
            ),
          );
        } else {
          statusButton = _buildStatusChip('Pending', Colors.orange);
        }
      } else {
        statusButton = _buildStatusChip('Waiting', Colors.grey);
      }
    } else if (status == 'cancelled' || status == 'regretted') {
      statusButton = _buildStatusChip('Cancelled', Colors.red);
    } else {
      statusButton = const SizedBox.shrink();
    }

    return InkWell(
      onTap: () {
        if (eventId != null) {
          final String? contextId = isIncoming
              ? data['eventOwnerId']
              : data['requesterId'];
          _navigateToEventDetails(context, eventId, contextId);
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12.0), // Margin giống main screen
        padding: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12.0), // Bo góc 12
          border: Border.all(
            color: Colors.grey.shade300,
            width: 1,
          ), // Viền thay vì Shadow
        ),
        child: Row(
          children: [
            // Icon môn thể thao: Không còn box background
            Text(sportVisual, style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    eventName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Color.fromRGBO(7, 7, 112, 1),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.access_time_filled,
                        color: Colors.grey[600],
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        timeString,
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Icon(
                        Icons.location_on,
                        color: Colors.grey[600],
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          location,
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            statusButton,
          ],
        ),
      ),
    );
  }
}
