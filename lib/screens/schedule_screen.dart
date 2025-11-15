import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'user_profile_screen.dart';
import '../utils/constants.dart';

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  Future<List<String>>? _controlledIdsFuture;

  // --- Biến cho bộ lọc (Filter) ---
  String _selectedSport = 'All';
  final List<String> _supportedSports = [
    'All',
    'Bóng đá',
    'Bóng rổ',
    'Bóng chuyền',
    'Cầu lông',
    'Tennis',
    'Bóng bàn',
  ];

  // --- Biến cho TableCalendar ---
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay; // Chọn ngày hôm nay làm mặc định
    if (_auth.currentUser != null) {
      _controlledIdsFuture = _getControlledOrganizerIds(_auth.currentUser!.uid);
    }
  }

  // --- (THÊM MỚI) Hàm để tải lại dữ liệu ---
  Future<void> _refreshData() async {
    if (_auth.currentUser != null) {
      // 1. Tạo một Future MỚI
      final newIdsFuture = _getControlledOrganizerIds(_auth.currentUser!.uid);

      // 2. Cập nhật state để FutureBuilder nhận diện và tải lại
      setState(() {
        _controlledIdsFuture = newIdsFuture;
      });

      // 3. Đợi Future mới hoàn thành để vòng xoay (indicator) biến mất
      await newIdsFuture;
    }
    // Nếu không đăng nhập, chỉ cần hoàn thành
    return;
  }
  // ------------------------------------------

  Future<List<String>> _getControlledOrganizerIds(String uid) async {
    List<String> controlledIds = [uid];
    final teamsQuery = await _firestore
        .collection('teams')
        .where('ownerId', isEqualTo: uid)
        .get();
    for (final teamDoc in teamsQuery.docs) {
      controlledIds.add(teamDoc.id);
    }
    return controlledIds;
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
    return DateFormat('EEEE MMM d').format(timestamp.toDate());
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
          // ... (AppBar giữ nguyên) ...
          automaticallyImplyLeading: false,
          title: const Text(
            'Schedule',
            style: TextStyle(
              color: Color.fromRGBO(7, 7, 112, 1),
              fontWeight: FontWeight.bold,
              fontSize: 32,
            ),
          ),
          actions: [
            IconButton(icon: const Icon(Icons.search), onPressed: () {}),
            IconButton(icon: const Icon(Icons.more_horiz), onPressed: () {}),
          ],
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

  // --- (CẬP NHẬT) _buildTimelineView với RefreshIndicator ---
  Widget _buildTimelineView() {
    if (_auth.currentUser == null) {
      return const Center(child: Text('Vui lòng đăng nhập.'));
    }

    return FutureBuilder<List<String>>(
      future: _controlledIdsFuture,
      builder: (context, idSnapshot) {
        if (!idSnapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (idSnapshot.hasError) {
          return Center(child: Text('Lỗi tải teams: ${idSnapshot.error}'));
        }

        final controlledIds = idSnapshot.data!;

        final incomingStream = _firestore
            .collection('joinRequests')
            .where('eventOwnerId', whereIn: controlledIds)
            .orderBy('eventTime', descending: false)
            .snapshots();

        final outgoingStream = _firestore
            .collection('joinRequests')
            .where('requesterId', isEqualTo: _auth.currentUser!.uid)
            .orderBy('eventTime', descending: false)
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

                final incomingDocs = incomingSnapshot.data?.docs ?? [];
                final outgoingDocs = outgoingSnapshot.data?.docs ?? [];
                final allRequests = <DocumentSnapshot>[
                  ...incomingDocs,
                  ...outgoingDocs,
                ];

                final filteredRequests = (_selectedSport == 'All')
                    ? allRequests
                    : allRequests.where((doc) {
                        return (doc.data()
                                as Map<String, dynamic>)['eventSport'] ==
                            _selectedSport;
                      }).toList();

                // Sắp xếp
                filteredRequests.sort((a, b) {
                  Timestamp? aTime =
                      (a.data() as Map<String, dynamic>)['eventTime'];
                  Timestamp? bTime =
                      (b.data() as Map<String, dynamic>)['eventTime'];
                  if (aTime == null || bTime == null) return 0;
                  return bTime.compareTo(aTime);
                });

                // --- (BẮT ĐẦU THAY ĐỔI) ---
                return Column(
                  children: [
                    _buildSportFilterChips(),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _refreshData,
                        child: (filteredRequests.isEmpty)
                            // Nếu rỗng, hiển thị 1 ListView có thể cuộn
                            // để RefreshIndicator hoạt động
                            ? Stack(
                                children: [
                                  ListView(
                                    physics:
                                        const AlwaysScrollableScrollPhysics(),
                                  ),
                                  const Center(
                                    child: Text(
                                      'Không có yêu cầu tham gia nào.',
                                    ),
                                  ),
                                ],
                              )
                            // Nếu không rỗng, hiển thị danh sách
                            : _buildGroupedListView(
                                filteredRequests,
                                controlledIds,
                              ),
                      ),
                    ),
                  ],
                );
                // --- (KẾT THÚC THAY ĐỔI) ---
              },
            );
          },
        );
      },
    );
  }

  // --- (Hàm _buildSportFilterChips giữ nguyên) ---
  Widget _buildSportFilterChips() {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(
        vertical: 10,
        horizontal: kDefaultPadding,
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _supportedSports.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final sportName = _supportedSports[index];
          final bool selected = _selectedSport == sportName;

          if (sportName == 'All') {
            return FilterChip(
              label: Text(sportName),
              selected: selected,
              onSelected: (bool newSelection) {
                if (newSelection) {
                  setState(() => _selectedSport = sportName);
                }
              },
              selectedColor: kAccentColor,
              backgroundColor: Colors.grey[200],
              checkmarkColor: Colors.white,
              labelStyle: TextStyle(
                color: selected ? Colors.white : Colors.black87,
                fontWeight: FontWeight.w600,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: selected ? kAccentColor : Colors.grey.shade300,
                ),
              ),
              showCheckmark: false,
            );
          }

          return FilterChip(
            label: Text(sportName),
            avatar: Text(
              _getSportVisual(sportName),
              style: const TextStyle(fontSize: 14),
            ),
            selected: selected,
            onSelected: (bool newSelection) {
              if (newSelection) {
                setState(() => _selectedSport = sportName);
              }
            },
            selectedColor: kAccentColor,
            backgroundColor: Colors.grey[200],
            checkmarkColor: Colors.white,
            labelStyle: TextStyle(
              color: selected ? Colors.white : Colors.black87,
              fontWeight: FontWeight.w600,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(
                color: selected ? kAccentColor : Colors.grey.shade300,
              ),
            ),
            showCheckmark: false,
          );
        },
      ),
    );
  }

  // --- (CẬP NHẬT) _buildGroupedListView với physics ---
  Widget _buildGroupedListView(
    List<DocumentSnapshot> requests,
    List<String> controlledIds,
  ) {
    String? lastDateHeader;

    return ListView.builder(
      // --- (THÊM MỚI) ---
      // Đảm bảo ListView luôn cuộn được để kích hoạt RefreshIndicator
      physics: const AlwaysScrollableScrollPhysics(),
      // -----------------
      padding: const EdgeInsets.all(kDefaultPadding),
      itemCount: requests.length,
      itemBuilder: (context, index) {
        final doc = requests[index];
        final data = doc.data() as Map<String, dynamic>;

        Widget headerWidget = const SizedBox.shrink();
        final eventTime = data['eventTime'] as Timestamp?;
        final currentDateHeader = _formatEventDateHeader(eventTime);

        if (currentDateHeader != lastDateHeader) {
          headerWidget = _buildDateHeader(currentDateHeader);
          lastDateHeader = currentDateHeader;
        }

        final bool isIncoming = controlledIds.contains(data['eventOwnerId']);

        return Column(
          children: [
            headerWidget,
            _ScheduleItemCard(
              joinRequestDoc: doc,
              isIncoming: isIncoming,
              getSportVisual: _getSportVisual,
            ),
          ],
        );
      },
    );
  }

  // --- (Hàm _buildDateHeader giữ nguyên) ---
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
        ),
      ),
    );
  }

  // --- (CẬP NHẬT) Widget cho "Calendar View" với RefreshIndicator ---
  Widget _buildCalendarView() {
    if (_auth.currentUser == null) {
      return const Center(child: Text('Vui lòng đăng nhập.'));
    }

    return FutureBuilder<List<String>>(
      future: _controlledIdsFuture,
      builder: (context, idSnapshot) {
        if (!idSnapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final controlledIds = idSnapshot.data!;

        // 1. Stream Yêu cầu đến (accepted hoặc pending)
        final incomingStream = _firestore
            .collection('joinRequests')
            .where('eventOwnerId', whereIn: controlledIds)
            //.where('status', whereIn: ['pending', 'accepted'])
            .snapshots();

        // 2. Stream Yêu cầu đi (accepted hoặc pending)
        final outgoingStream = _firestore
            .collection('joinRequests')
            .where('requesterId', isEqualTo: _auth.currentUser!.uid)
            //.where('status', whereIn: ['pending', 'accepted'])
            .snapshots();

        // 3. Lồng 2 StreamBuilder
        return StreamBuilder<QuerySnapshot>(
          stream: incomingStream,
          builder: (context, incomingSnapshot) {
            return StreamBuilder<QuerySnapshot>(
              stream: outgoingStream,
              builder: (context, outgoingSnapshot) {
                if (!incomingSnapshot.hasData || !outgoingSnapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final incomingDocs = incomingSnapshot.data?.docs ?? [];
                final outgoingDocs = outgoingSnapshot.data?.docs ?? [];
                final allRequests = <DocumentSnapshot>[
                  ...incomingDocs,
                  ...outgoingDocs,
                ];

                // 4. Xử lý dữ liệu cho Calendar
                final eventsByDay = <DateTime, List<DocumentSnapshot>>{};
                for (final doc in allRequests) {
                  final data = doc.data() as Map<String, dynamic>;
                  final eventTime = data['eventTime'] as Timestamp?;
                  if (eventTime != null) {
                    final day = _normalizeDate(eventTime.toDate());
                    if (eventsByDay[day] == null) {
                      eventsByDay[day] = [];
                    }
                    eventsByDay[day]!.add(doc);
                  }
                }

                // 5. Lấy danh sách sự kiện cho ngày đã chọn
                final selectedDayEvents =
                    eventsByDay[_normalizeDate(_selectedDay!)] ?? [];

                // 6. Build UI: Lịch + Danh sách
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () {
                            final now = DateTime.now();
                            // Cập nhật lại ngày được chọn và ngày focus
                            setState(() {
                              _selectedDay = now;
                              _focusedDay = now;
                            });
                          },
                          child: const Text(
                            'Go to Today',
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
                      selectedDayPredicate: (day) {
                        return isSameDay(_selectedDay, day);
                      },
                      onDaySelected: (selectedDay, focusedDay) {
                        setState(() {
                          _selectedDay = selectedDay;
                          _focusedDay = focusedDay;
                        });
                      },
                      onFormatChanged: (format) {
                        setState(() {
                          _calendarFormat = format;
                        });
                      },
                      // Dùng eventLoader để cung cấp dữ liệu
                      eventLoader: (day) {
                        return eventsByDay[_normalizeDate(day)] ?? [];
                      },
                      // Build UI cho các marker (emoji)
                      calendarBuilders: CalendarBuilders(
                        markerBuilder: (context, day, events) {
                          if (events.isEmpty) return null;

                          // Lấy các môn thể thao (không trùng lặp)
                          final sports = (events as List<DocumentSnapshot>)
                              .map((doc) => (doc.data() as Map)['eventSport'])
                              .toSet();

                          return Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: sports.take(4).map((sport) {
                              // Giới hạn 4 icon
                              return Text(
                                _getSportVisual(sport as String?),
                                style: const TextStyle(fontSize: 10),
                              );
                            }).toList(),
                          );
                        },
                      ),
                    ),
                    const Divider(height: 1),
                    // --- (BẮT ĐẦU THAY ĐỔI) ---
                    // Danh sách sự kiện của ngày đã chọn
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _refreshData,
                        child: (selectedDayEvents.isEmpty)
                            // Nếu rỗng, hiển thị ListView có thể cuộn
                            ? Stack(
                                children: [
                                  ListView(
                                    physics:
                                        const AlwaysScrollableScrollPhysics(),
                                  ),
                                  const Center(
                                    child: Text(
                                      'Không có sự kiện nào cho ngày này.',
                                    ),
                                  ),
                                ],
                              )
                            // Nếu không rỗng, hiển thị danh sách
                            : ListView.builder(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.all(kDefaultPadding),
                                itemCount: selectedDayEvents.length,
                                itemBuilder: (context, index) {
                                  final doc = selectedDayEvents[index];
                                  final data =
                                      doc.data() as Map<String, dynamic>;
                                  final bool isIncoming = controlledIds
                                      .contains(data['eventOwnerId']);

                                  return _ScheduleItemCard(
                                    joinRequestDoc: doc,
                                    isIncoming: isIncoming,
                                    getSportVisual: _getSportVisual,
                                  );
                                },
                              ),
                      ),
                    ),
                    // --- (KẾT THÚC THAY ĐỔI) ---
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}
// ---------------------------------------------------

// --- (Class _ScheduleItemCard giữ nguyên) ---
class _ScheduleItemCard extends StatelessWidget {
  final DocumentSnapshot joinRequestDoc;
  final bool isIncoming;
  final String Function(String?) getSportVisual;

  const _ScheduleItemCard({
    required this.joinRequestDoc,
    required this.isIncoming,
    required this.getSportVisual,
  });

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sẽ mở trang chi tiết Team (ID: $requesterId)')),
      );
    }
  }

  Future<void> _updateRequestStatus(String status) async {
    await joinRequestDoc.reference.update({'status': status});
  }

  Widget _buildStatusChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontWeight: FontWeight.bold),
      ),
    );
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
    final String location = data['eventLocationName'] ?? 'Unknown Location';
    final String sport = data['eventSport'] ?? 'Unknown';
    final Timestamp? eventTime = data['eventTime'];
    final String status = data['status'] ?? 'pending';

    final String timeString = (eventTime != null)
        ? DateFormat('h:mm a').format(eventTime.toDate())
        : 'No time';
    final String sportVisual = getSportVisual(sport);

    Widget statusButton;
    if (isIncoming) {
      switch (status) {
        case 'pending':
          statusButton = InkWell(
            onTap: () {
              _showActionSheet(context, data);
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Text(
                    'Action',
                    style: TextStyle(
                      color: Colors.blue,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(width: 4),
                  Icon(Icons.keyboard_arrow_down, color: Colors.blue, size: 16),
                ],
              ),
            ),
          );
          break;
        case 'accepted':
          statusButton = _buildStatusChip('Accepted', Colors.green);
          break;
        case 'regretted':
          statusButton = _buildStatusChip('Regretted', Colors.red);
          break;
        case 'cancelled': // <-- THÊM MỚI
          statusButton = _buildStatusChip('Cancelled', Colors.red);
          break;
        default:
          statusButton = const SizedBox.shrink();
      }
    } else {
      switch (status) {
        case 'pending':
          statusButton = _buildStatusChip('Awaiting', Colors.grey);
          break;
        case 'accepted':
          statusButton = _buildStatusChip('Joined', Colors.green);
          break;
        case 'cancelled':
          statusButton = _buildStatusChip('Cancelled', Colors.red);
          break;
        case 'regretted':
          statusButton = _buildStatusChip('Declined', Colors.red);
          break;
        default:
          statusButton = const SizedBox.shrink();
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12.0),
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(color: Colors.grey.shade300, width: 1),
      ),
      child: Row(
        children: [
          Text(sportVisual, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  eventName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.access_time, color: Colors.grey[600], size: 14),
                    const SizedBox(width: 4),
                    Text(timeString, style: TextStyle(color: Colors.grey[600])),
                    const SizedBox(width: 12),
                    Icon(Icons.location_on, color: Colors.grey[600], size: 14),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        location,
                        style: TextStyle(color: Colors.grey[600]),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          statusButton,
        ],
      ),
    );
  }
}
