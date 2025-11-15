import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'event_detail_screen.dart';
import '../utils/constants.dart';

// --- (THÊM MỚI) Import custom dropdown ---
import '../widgets/custom_dropdown_widget.dart';
// (Giả sử file của bạn nằm ở 'widgets/custom_dropdown_widget.dart')
// (Nếu không, hãy đổi đường dẫn này cho đúng)

class AllEventsScreen extends StatefulWidget {
  final List<DocumentSnapshot> events;
  const AllEventsScreen({Key? key, required this.events}) : super(key: key);

  @override
  State<AllEventsScreen> createState() => _AllEventsScreenState();
}

class _AllEventsScreenState extends State<AllEventsScreen> {
  String? _selectedSport;
  DateTime? _selectedDate;
  List<DocumentSnapshot> _filteredEvents = [];

  final List<String> _sportsOptions = [
    'Bóng đá',
    'Bóng chuyền',
    'Bóng rổ',
    'Bóng bàn',
    'Cầu lông',
    'Tennis',
  ];

  @override
  void initState() {
    super.initState();
    _filteredEvents = widget.events;
  }

  void _applyFilters() {
    List<DocumentSnapshot> tempEvents = widget.events;

    if (_selectedSport != null) {
      tempEvents = tempEvents.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return data['sport'] == _selectedSport;
      }).toList();
    }

    if (_selectedDate != null) {
      tempEvents = tempEvents.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        final eventTime = (data['eventTime'] as Timestamp?)?.toDate();
        if (eventTime == null) return false;

        return eventTime.year == _selectedDate!.year &&
            eventTime.month == _selectedDate!.month &&
            eventTime.day == _selectedDate!.day;
      }).toList();
    }

    setState(() {
      _filteredEvents = tempEvents;
    });
  }

  Future<void> _showFilterDialog() async {
    String? tempSport = _selectedSport;
    DateTime? tempDate = _selectedDate;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialogState) {
            return Container(
              padding: EdgeInsets.only(
                top: 20,
                left: 20,
                right: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Lọc sự kiện',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 20),

                  // --- (BẮT ĐẦU THAY THẾ) ---
                  // Bỏ DropdownButton cũ, dùng CustomDropdownWidget
                  CustomDropdownWidget(
                    title: "Môn thể thao", //
                    items: _sportsOptions, //
                    selectedItem: tempSport, //
                    onChanged: (value) {
                      setDialogState(() => tempSport = value); //
                    },
                  ),

                  // --- (KẾT THÚC THAY THẾ) ---
                  const SizedBox(height: 20),

                  // --- Lọc Thời gian ---
                  const Text(
                    "Thời gian",
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                  TextFormField(
                    readOnly: true,
                    decoration: InputDecoration(
                      hintText: tempDate == null
                          ? "Chọn ngày"
                          : DateFormat('dd/MM/yyyy').format(tempDate!),
                      suffixIcon: tempDate != null
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () =>
                                  setDialogState(() => tempDate = null),
                            )
                          : const Icon(Icons.calendar_today),
                    ),
                    onTap: () async {
                      final pickedDate = await showDatePicker(
                        context: context,
                        initialDate: tempDate ?? DateTime.now(),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (pickedDate != null) {
                        setDialogState(() => tempDate = pickedDate);
                      }
                    },
                  ),
                  const SizedBox(height: 30),

                  // --- Nút bấm ---
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        child: const Text("Xóa tất cả"),
                        onPressed: () {
                          setDialogState(() {
                            tempSport = null;
                            tempDate = null;
                          });
                          Navigator.pop(context);
                          setState(() {
                            _selectedSport = null;
                            _selectedDate = null;
                          });
                          _applyFilters();
                        },
                      ),
                      ElevatedButton(
                        child: const Text("Áp dụng"),
                        onPressed: () {
                          Navigator.pop(context);
                          setState(() {
                            _selectedSport = tempSport;
                            _selectedDate = tempDate;
                          });
                          _applyFilters();
                        },
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // --- (Các hàm helper giữ nguyên) ---
  String _formatEventTime(Timestamp? timestamp) {
    if (timestamp == null) return '';
    final dateTime = timestamp.toDate();
    final formatter = DateFormat('h:mm a - MMM d');
    return formatter.format(dateTime);
  }

  String _formatEventTimeRange(Timestamp? startTime, Timestamp? endTime) {
    if (startTime == null) return 'TBA';

    if (endTime != null) {
      final start = DateFormat('h:mm a').format(startTime.toDate());
      final end = DateFormat('h:mm a').format(endTime.toDate());
      final date = DateFormat('MMM d').format(startTime.toDate());
      return '$start - $end, $date';
    }

    return _formatEventTime(startTime);
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
    return Scaffold(
      backgroundColor: kWhiteColor,
      appBar: AppBar(
        backgroundColor: kWhiteColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: kPrimaryColor),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Nearby Events',
          style: TextStyle(color: kPrimaryColor, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list, color: kPrimaryColor),
            onPressed: _showFilterDialog,
          ),
        ],
      ),
      body: _filteredEvents.isEmpty
          ? const Center(
              child: Text(
                'Không tìm thấy sự kiện nào khớp với bộ lọc.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            )
          : ListView.builder(
              itemCount: _filteredEvents.length,
              itemBuilder: (context, index) {
                final eventDoc = _filteredEvents[index];
                final data = eventDoc.data() as Map<String, dynamic>;
                final skillLevel = data['skillLevel'] ?? 'N/A';
                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: kDefaultPadding,
                    vertical: 8,
                  ),
                  elevation: 2.0,
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: kDefaultBorderRadius,
                  ),
                  child: InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              EventDetailScreen(eventDoc: eventDoc),
                        ),
                      );
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CachedNetworkImage(
                          imageUrl: data['imageUrl'] ?? '',
                          height: 150,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                        ListTile(
                          leading: CircleAvatar(
                            backgroundColor: kAccentColor.withOpacity(0.2),
                            child: Text(_getSportVisual(data['sport'])),
                          ),
                          title: Text(
                            data['eventName'] ?? 'No Title',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            '${data['locationName'] ?? 'No Location'}\n${_formatEventTimeRange(data['eventTime'], data['eventEndTime'])}',
                          ),
                          isThreeLine: true,
                          trailing: Chip(
                            label: Text(
                              skillLevel,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.blue[800],
                                fontSize: 12,
                              ),
                            ),
                            backgroundColor: Colors.blue[50],
                            avatar: Icon(
                              Icons.leaderboard_outlined,
                              color: Colors.blue[800],
                              size: 16,
                            ),
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8.0,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
