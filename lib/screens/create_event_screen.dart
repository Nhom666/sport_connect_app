import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart'; // Thêm để dùng CupertinoPicker
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geoflutterfire3/geoflutterfire3.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path/path.dart' as path;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../widgets/custom_dropdown_widget.dart';
import '../utils/constants.dart';
import '../utils/reputation_utils.dart';

class CreateEventScreen extends StatefulWidget {
  final DocumentSnapshot? eventToEdit;
  final String? preSelectedTeamId;
  final String? preSelectedTeamName;
  const CreateEventScreen({
    Key? key,
    this.eventToEdit,
    this.preSelectedTeamId,
    this.preSelectedTeamName,
  }) : super(key: key);

  @override
  State<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends State<CreateEventScreen> {
  final _formKey = GlobalKey<FormState>();
  final _eventNameController = TextEditingController();
  final _locationNameController = TextEditingController();

  DateTime? _eventDateTime;
  DateTime? _eventEndDateTime; // Thêm thời gian kết thúc
  bool _isLoading = false;
  File? _pickedImageFile;

  // Biến cho Môn thể thao
  String? _selectedSport;
  final List<String> _sports = [
    'Bóng đá',
    'Bóng chuyền',
    'Bóng rổ',
    'Bóng bàn',
    'Cầu lông',
    'Tennis',
  ];

  // --- (MỚI) Biến cho Trình độ ---
  String? _selectedSkillLevel;
  final List<String> _skillLevels = ['Sơ cấp', 'Trung cấp', 'Chuyên nghiệp'];
  // -----------------------------

  final _geo = GeoFlutterFire();
  final _firestore = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;
  final _auth = FirebaseAuth.instance;

  bool get _isEditing => widget.eventToEdit != null;
  Map<String, dynamic>? _eventData;
  String? _existingImageUrl;

  // Biến cho việc chọn Người tạo
  String _creatorType = 'individual'; // 'individual' hoặc 'team'
  String? _selectedTeamId;
  String? _selectedTeamName; // Lưu tên để hiển thị
  String? _selectedTeamSport; // Môn thể thao của team đã chọn
  Future<List<DocumentSnapshot>>? _teamsFuture; // Tải danh sách team

  @override
  void initState() {
    super.initState();
    // Tải danh sách các đội mà user này làm owner
    _loadUserOwnedTeams();

    if (_isEditing) {
      _eventData = widget.eventToEdit!.data() as Map<String, dynamic>;
      _eventNameController.text = _eventData!['eventName'] ?? '';
      _locationNameController.text = _eventData!['locationName'] ?? '';
      _existingImageUrl = _eventData!['imageUrl'];
      _selectedSport = _eventData!['sport'];

      // --- (MỚI) Tải trình độ khi edit ---
      _selectedSkillLevel = _eventData!['skillLevel'];
      // ----------------------------------

      Timestamp? eventTime = _eventData!['eventTime'];
      if (eventTime != null) {
        _eventDateTime = eventTime.toDate();
      }

      // Tải thời gian kết thúc khi edit
      Timestamp? endTime = _eventData!['eventEndTime'];
      if (endTime != null) {
        _eventEndDateTime = endTime.toDate();
      }

      // Load dữ liệu edit cho Creator
      _creatorType = _eventData!['creatorType'] ?? 'individual';
      if (_creatorType == 'team') {
        _selectedTeamId = _eventData!['organizerId'];
        // Tên team (_selectedTeamName) sẽ được tự động điền bởi FutureBuilder
        // Load môn thể thao của team khi edit
        _loadTeamSport(_selectedTeamId!);
      } else if (widget.preSelectedTeamId != null) {
        _creatorType = 'team'; // Tự động chuyển sang chế độ Team
        _selectedTeamId = widget.preSelectedTeamId;
        _selectedTeamName = widget.preSelectedTeamName;
        // Load môn thể thao của team
        _loadTeamSport(widget.preSelectedTeamId!);
      }
    }
  }

  // Hàm tải các đội mà user SỞ HỮU (owner)
  void _loadUserOwnedTeams() {
    final user = _auth.currentUser;
    if (user == null) return;

    final query = _firestore
        .collection('teams')
        .where('ownerId', isEqualTo: user.uid);

    setState(() {
      _teamsFuture = query.get().then((snapshot) => snapshot.docs);
    });
  }

  // Hàm tải môn thể thao của team từ Firestore
  Future<void> _loadTeamSport(String teamId) async {
    try {
      final teamDoc = await _firestore.collection('teams').doc(teamId).get();
      if (teamDoc.exists) {
        final teamData = teamDoc.data() as Map<String, dynamic>;
        setState(() {
          _selectedTeamSport = teamData['sport'];
          _selectedSport = _selectedTeamSport; // Auto-set sport
        });
      }
    } catch (e) {
      print('Error loading team sport: $e');
    }
  }

  @override
  void dispose() {
    _eventNameController.dispose();
    _locationNameController.dispose();
    super.dispose();
  }

  // ... (Hàm _pickImage, _pickDateTime giữ nguyên) ...
  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedImage = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 50,
    );
    if (pickedImage == null) {
      return;
    }
    setState(() {
      _pickedImageFile = File(pickedImage.path);
    });
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final DateTime? date = await showDatePicker(
      context: context,
      initialDate: _eventDateTime ?? now,
      firstDate: now, // Chỉ cho phép chọn từ hôm nay trở đi
      lastDate: now.add(const Duration(days: 365)),
      // 🎨 Custom theme cho đẹp hơn
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF070770), // Màu chính (header, selected)
              onPrimary: Colors.white, // Text trên màu chính
              surface: Colors.white, // Nền dialog
              onSurface: Colors.black87, // Text thường
            ),
            dialogBackgroundColor: Colors.white,
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF070770), // Màu nút Cancel/OK
                textStyle: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ),
          child: child!,
        );
      },
    );
    if (date == null) return;

    // 🎯 Dùng CupertinoTimePicker (kiểu cuộn iOS)
    DateTime initialTime = _eventDateTime ?? now;
    DateTime? selectedTime;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext builder) {
        return Container(
          height: 350,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF070770).withOpacity(0.1),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text(
                        'Hủy',
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Text(
                      'Chọn giờ',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF070770),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        // Chỉ pop 1 lần với giá trị selectedTime
                        Navigator.pop(context, selectedTime);
                      },
                      child: const Text(
                        'Xong',
                        style: TextStyle(
                          color: Color(0xFF070770),
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Time Picker
              Expanded(
                child: CupertinoTheme(
                  data: const CupertinoThemeData(
                    textTheme: CupertinoTextThemeData(
                      dateTimePickerTextStyle: TextStyle(
                        fontSize: 22,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  child: CupertinoDatePicker(
                    mode: CupertinoDatePickerMode.time,
                    use24hFormat: true, // Dùng định dạng 24h
                    initialDateTime: initialTime,
                    onDateTimeChanged: (DateTime newTime) {
                      selectedTime = newTime;
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    // selectedTime đã được cập nhật từ onDateTimeChanged
    if (selectedTime == null) return;

    final newDateTime = DateTime(
      date.year,
      date.month,
      date.day,
      selectedTime!.hour,
      selectedTime!.minute,
    );

    // --- (THÊM MỚI) Kiểm tra xem thời gian có trong quá khứ không ---
    if (newDateTime.isBefore(now)) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Thời gian không hợp lệ'),
            content: const Text(
              'Không thể tạo sự kiện trong quá khứ. '
              'Vui lòng chọn thời gian trong tương lai.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
      return;
    }
    // ----------------------------------------------------------

    // Kiểm tra trùng lịch trước khi set state
    final hasConflict = await _checkScheduleConflict(newDateTime);
    if (hasConflict && mounted) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Trùng lịch'),
          content: const Text(
            'Bạn đã có một sự kiện được chấp nhận vào thời gian này. '
            'Vui lòng chọn thời gian khác.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    setState(() {
      _eventDateTime = newDateTime;
    });
  }

  // Hàm chọn thời gian kết thúc
  Future<void> _pickEndDateTime() async {
    if (_eventDateTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng chọn thời gian bắt đầu trước')),
      );
      return;
    }

    final DateTime? date = await showDatePicker(
      context: context,
      initialDate: _eventEndDateTime ?? _eventDateTime!,
      firstDate: _eventDateTime!, // Phải sau hoặc bằng thời gian bắt đầu
      lastDate: _eventDateTime!.add(
        const Duration(days: 7),
      ), // Tối đa 7 ngày sau
      // 🎨 Custom theme
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF070770),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black87,
            ),
            dialogBackgroundColor: Colors.white,
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF070770),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ),
          child: child!,
        );
      },
    );
    if (date == null) return;

    // 🎯 Dùng CupertinoTimePicker cho thời gian kết thúc
    DateTime initialEndTime =
        _eventEndDateTime ?? _eventDateTime!.add(const Duration(hours: 2));
    DateTime? selectedEndTime;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext builder) {
        return Container(
          height: 350,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF070770).withOpacity(0.1),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text(
                        'Hủy',
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Text(
                      'Chọn giờ kết thúc',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF070770),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        // Chỉ pop 1 lần với giá trị selectedEndTime
                        Navigator.pop(context, selectedEndTime);
                      },
                      child: const Text(
                        'Xong',
                        style: TextStyle(
                          color: Color(0xFF070770),
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: CupertinoTheme(
                  data: const CupertinoThemeData(
                    textTheme: CupertinoTextThemeData(
                      dateTimePickerTextStyle: TextStyle(
                        fontSize: 22,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  child: CupertinoDatePicker(
                    mode: CupertinoDatePickerMode.time,
                    use24hFormat: true,
                    initialDateTime: initialEndTime,
                    onDateTimeChanged: (DateTime newTime) {
                      selectedEndTime = newTime;
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    // selectedEndTime đã được cập nhật từ onDateTimeChanged
    if (selectedEndTime == null) return;

    final newEndDateTime = DateTime(
      date.year,
      date.month,
      date.day,
      selectedEndTime!.hour,
      selectedEndTime!.minute,
    );

    // Kiểm tra thời gian kết thúc phải sau thời gian bắt đầu
    if (newEndDateTime.isBefore(_eventDateTime!) ||
        newEndDateTime.isAtSameMomentAs(_eventDateTime!)) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Thời gian không hợp lệ'),
            content: const Text(
              'Thời gian kết thúc phải sau thời gian bắt đầu.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
      return;
    }

    // Kiểm tra khoảng thời gian không quá 24 giờ
    final duration = newEndDateTime.difference(_eventDateTime!);
    if (duration.inHours > 24) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Thời gian không hợp lệ'),
            content: const Text('Sự kiện không thể kéo dài quá 24 giờ.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
      return;
    }

    setState(() {
      _eventEndDateTime = newEndDateTime;
    });
  }

  // Hàm xử lý khi thời gian event thay đổi - huỷ các request đã accept
  Future<void> _handleTimeChangeForAcceptedRequests(
    String eventId,
    String eventName,
  ) async {
    try {
      // Tìm tất cả các joinRequest đã được accept cho event này
      final acceptedRequests = await _firestore
          .collection('joinRequests')
          .where('eventId', isEqualTo: eventId)
          .where('status', isEqualTo: 'accepted')
          .get();

      if (acceptedRequests.docs.isEmpty) {
        print('ℹ️ Không có request nào đã accept');
        return;
      }

      print(
        '⚠️ Thời gian event thay đổi - Huỷ ${acceptedRequests.docs.length} request(s)',
      );

      // Huỷ tất cả các request đã accept
      final batch = _firestore.batch();
      final Set<String> affectedUserIds =
          {}; // Lưu tất cả user IDs bị ảnh hưởng

      for (final doc in acceptedRequests.docs) {
        final data = doc.data();
        final requesterId = data['requesterId'] as String?;
        final requesterType = data['requesterType'] as String?;

        batch.update(doc.reference, {
          'status': 'cancelled',
          'cancelReason': 'Event time changed by organizer',
          'cancelledAt': FieldValue.serverTimestamp(),
        });

        // Thu thập user IDs để gửi notification
        if (requesterId != null) {
          if (requesterType == 'team') {
            // Nếu là team, lấy tất cả members
            try {
              final teamDoc = await _firestore
                  .collection('teams')
                  .doc(requesterId)
                  .get();
              if (teamDoc.exists) {
                final teamData = teamDoc.data();
                final members = teamData?['members'] as List<dynamic>?;
                if (members != null) {
                  for (var member in members) {
                    String? memberId;
                    if (member is String) {
                      memberId = member;
                    } else if (member is Map) {
                      memberId = member['uid'] as String?;
                    }
                    if (memberId != null) {
                      affectedUserIds.add(memberId);
                    }
                  }
                }
              }
            } catch (e) {
              print('⚠️ Lỗi khi lấy team members: $e');
            }
          } else {
            // Nếu là individual user
            affectedUserIds.add(requesterId);
          }
        }
      }

      await batch.commit();

      // Gửi notification cho TẤT CẢ users bị ảnh hưởng
      if (affectedUserIds.isNotEmpty) {
        await _sendTimeChangeNotifications(affectedUserIds.toList(), eventName);
      }

      // Hiển thị thông báo cho owner
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Thời gian event đã thay đổi. '
              '${acceptedRequests.docs.length} lời mời đã chấp nhận bị huỷ.\n'
              'Đã gửi thông báo cho ${affectedUserIds.length} người.',
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 5),
          ),
        );
      }

      print(
        '✅ Đã huỷ request và gửi notification cho ${affectedUserIds.length} users',
      );
    } catch (e) {
      print('❌ Lỗi khi xử lý time change: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Cảnh báo: Không thể cập nhật trạng thái cho những người đã tham gia',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Hàm gửi notification cho users khi event time thay đổi
  Future<void> _sendTimeChangeNotifications(
    List<String> userIds,
    String eventName,
  ) async {
    try {
      // Tạo notification documents trong Firestore
      final batch = _firestore.batch();
      final now = Timestamp.now();

      for (String userId in userIds) {
        final notificationRef = _firestore
            .collection('users')
            .doc(userId)
            .collection('notifications')
            .doc();

        batch.set(notificationRef, {
          'title': '⚠️ Sự kiện bị thay đổi',
          'body':
              '"$eventName" đã thay đổi thời gian. Lời mời của bạn đã bị huỷ.',
          'type': 'event_time_changed',
          'eventName': eventName,
          'createdAt': now,
          'read': false,
        });
      }

      await batch.commit();
      print('📬 Đã tạo ${userIds.length} notification documents');

      // TODO: Nếu có FCM (Firebase Cloud Messaging) setup, có thể gửi push notification thật
      // Hiện tại notification được lưu trong Firestore, user sẽ thấy khi mở app
    } catch (e) {
      print('❌ Lỗi khi gửi notifications: $e');
    }
  }

  // Hàm kiểm tra xem người dùng có sự kiện nào được accept vào thời gian này không
  Future<bool> _checkScheduleConflict(DateTime selectedTime) async {
    final user = _auth.currentUser;
    if (user == null) return false;

    // Nếu đang edit sự kiện hiện tại, bỏ qua kiểm tra
    if (_isEditing) return false;

    // Cần có thời gian kết thúc để kiểm tra chồng lấn
    if (_eventEndDateTime == null) return false;

    try {
      // --- 1. Kiểm tra các sự kiện mà user đã THAM GIA (accepted) ---
      final acceptedRequests = await _firestore
          .collection('joinRequests')
          .where('requesterId', isEqualTo: user.uid)
          .where('status', isEqualTo: 'accepted')
          .get();

      for (final doc in acceptedRequests.docs) {
        final data = doc.data();
        final existingStartTime = (data['eventTime'] as Timestamp?)?.toDate();

        // Lấy thời gian kết thúc từ joinRequest hoặc từ event
        Timestamp? existingEndTimestamp = data['eventEndTime'] as Timestamp?;
        DateTime? existingEndTime;

        if (existingEndTimestamp != null) {
          existingEndTime = existingEndTimestamp.toDate();
        } else if (existingStartTime != null) {
          // Nếu không có eventEndTime, giả sử sự kiện kéo dài 2 giờ
          existingEndTime = existingStartTime.add(const Duration(hours: 2));
        }

        if (existingStartTime != null && existingEndTime != null) {
          // Kiểm tra chồng lấn: sự kiện mới có bị chồng với sự kiện đã có không?
          if (_isTimeOverlapping(
            selectedTime,
            _eventEndDateTime!,
            existingStartTime,
            existingEndTime,
          )) {
            return true; // Có trùng lịch với sự kiện đã tham gia
          }
        }
      }

      // --- 2. Kiểm tra các sự kiện mà user đã TẠO (organizer) ---
      final controlledIds = await _getControlledOrganizerIds(user.uid);

      final createdEvents = await _firestore
          .collection('events')
          .where('organizerId', whereIn: controlledIds)
          .get();

      for (final doc in createdEvents.docs) {
        final data = doc.data();
        final existingStartTime = (data['eventTime'] as Timestamp?)?.toDate();
        final existingEndTime = (data['eventEndTime'] as Timestamp?)?.toDate();

        if (existingStartTime != null && existingEndTime != null) {
          // Kiểm tra chồng lấn
          if (_isTimeOverlapping(
            selectedTime,
            _eventEndDateTime!,
            existingStartTime,
            existingEndTime,
          )) {
            return true; // Có trùng lịch với sự kiện đã tạo
          }
        }
      }

      return false; // Không trùng lịch
    } catch (e) {
      print('Error checking schedule conflict: $e');
      return false; // Nếu lỗi, cho phép tiếp tục
    }
  }

  // Helper: Kiểm tra 2 khoảng thời gian có chồng lấn không
  // Trả về true nếu [start1, end1] và [start2, end2] có phần nào giao nhau
  bool _isTimeOverlapping(
    DateTime start1,
    DateTime end1,
    DateTime start2,
    DateTime end2,
  ) {
    // Hai khoảng thời gian KHÔNG chồng lấn khi:
    // - Khoảng 1 kết thúc trước khi khoảng 2 bắt đầu: end1 <= start2
    // - Khoảng 2 kết thúc trước khi khoảng 1 bắt đầu: end2 <= start1
    //
    // Ngược lại = có chồng lấn
    return !(end1.isBefore(start2) ||
        end1.isAtSameMomentAs(start2) ||
        end2.isBefore(start1) ||
        end2.isAtSameMomentAs(start1));
  }

  // Hàm lấy tất cả các ID mà user kiểm soát (bản thân + teams)
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

  // --- (UPDATED) Sửa hàm _saveEvent ---
  Future<void> _saveEvent() async {
    // 1. Validation (cơ bản)
    if (!_formKey.currentState!.validate() ||
        _eventDateTime == null ||
        _eventEndDateTime == null || // Thêm validation cho thời gian kết thúc
        _selectedSport == null ||
        _selectedSkillLevel == null) {
      // <-- Thêm check trình độ
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            // <-- Sửa thông báo lỗi
            'Vui lòng điền tất cả các trường, chọn thời gian bắt đầu & kết thúc, môn thể thao và trình độ.',
          ),
        ),
      );
      return;
    }
    if (!_isEditing && _pickedImageFile == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please pick an image.')));
      return;
    }

    // Validation cho Team
    if (_creatorType == 'team' && _selectedTeamId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select a team.')));
      return;
    }

    //Xác định ID cần kiểm tra uy tín (User hoặc Team)
    final user = _auth.currentUser;
    if (user == null) return;

    String targetCheckId = user.uid;
    String targetCollection = 'users';
    String targetName = 'Bạn';

    if (_creatorType == 'team') {
      if (_selectedTeamId == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Vui lòng chọn Team.')));
        return;
      }
      targetCheckId = _selectedTeamId!;
      targetCollection = 'teams';
      targetName = 'Team này';
    }

    //KIỂM TRA ĐIỂM UY TÍN
    // Hiển thị loading trong lúc check
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    bool isAllowed = await ReputationUtils.checkAndRecoverReputation(
      targetId: targetCheckId,
      collection: targetCollection,
    );

    Navigator.of(context).pop(); // Tắt loading dialog

    if (!isAllowed) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Điểm uy tín quá thấp!'),
            content: Text(
              '$targetName hiện có điểm uy tín dưới 50 nên bị cấm tạo sự kiện.\n\n'
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

    // --- (THÊM MỚI) Kiểm tra thời gian trong quá khứ ---
    if (_eventDateTime != null && _eventDateTime!.isBefore(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Không thể tạo sự kiện trong quá khứ. '
            'Vui lòng chọn thời gian khác.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    // -----------------------------------------------

    // --- Kiểm tra trùng lịch trước khi lưu ---
    if (_eventDateTime != null) {
      final hasConflict = await _checkScheduleConflict(_eventDateTime!);
      if (hasConflict && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Bạn đã có một sự kiện vào thời gian này. '
              'Vui lòng chọn thời gian khác.',
            ),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }
    // -----------------------------------------------

    setState(() {
      _isLoading = true;
    });

    try {
      // ... (Logic lấy vị trí GPS, xử lý ảnh giữ nguyên) ...
      Position currentPos = await Geolocator.getCurrentPosition();
      GeoFirePoint eventLocation = _geo.point(
        latitude: currentPos.latitude,
        longitude: currentPos.longitude,
      );
      String downloadUrl;
      if (_pickedImageFile != null) {
        String fileExtension = path.extension(_pickedImageFile!.path);
        String fileName =
            '${DateTime.now().millisecondsSinceEpoch}$fileExtension';
        Reference storageRef = _storage
            .ref()
            .child('event_images')
            .child(fileName);
        if (_isEditing && _existingImageUrl != null) {
          try {
            await FirebaseStorage.instance
                .refFromURL(_existingImageUrl!)
                .delete();
          } catch (e) {
            print("Failed to delete old image, continuing: $e");
          }
        }
        UploadTask uploadTask = storageRef.putFile(_pickedImageFile!);
        TaskSnapshot snapshot = await uploadTask;
        downloadUrl = await snapshot.ref.getDownloadURL();
      } else {
        downloadUrl = _existingImageUrl!;
      }

      // --- 4. (UPDATED) Chuẩn bị dữ liệu ---
      final data = {
        'eventName': _eventNameController.text,
        'locationName': _locationNameController.text,
        'imageUrl': downloadUrl,
        'eventTime': Timestamp.fromDate(_eventDateTime!),
        'eventEndTime': Timestamp.fromDate(
          _eventEndDateTime!,
        ), // Thêm thời gian kết thúc
        'position': eventLocation.data,
        'sport': _selectedSport,

        // --- (MỚI) Thêm trình độ ---
        'skillLevel': _selectedSkillLevel,
        // --------------------------

        // Cập nhật logic organizerId và creatorType
        'creatorType': _creatorType,
        'organizerId': (_creatorType == 'team') ? _selectedTeamId : user.uid,

        if (!_isEditing) 'createdAt': FieldValue.serverTimestamp(),
      };
      // ------------------------------------

      // 5. Logic Save (Update hoặc Add)
      if (_isEditing) {
        // Kiểm tra xem có thay đổi thời gian không
        final oldEventTime = _eventData!['eventTime'] as Timestamp?;
        final oldEventEndTime = _eventData!['eventEndTime'] as Timestamp?;
        final newEventTime = Timestamp.fromDate(_eventDateTime!);
        final newEventEndTime = Timestamp.fromDate(_eventEndDateTime!);

        bool timeChanged = false;
        if (oldEventTime != null && oldEventEndTime != null) {
          timeChanged =
              oldEventTime != newEventTime ||
              oldEventEndTime != newEventEndTime;
        }

        // Cập nhật event
        await _firestore
            .collection('events')
            .doc(widget.eventToEdit!.id)
            .update(data);

        // Nếu thời gian thay đổi, huỷ các request đã accept và thông báo
        if (timeChanged) {
          await _handleTimeChangeForAcceptedRequests(
            widget.eventToEdit!.id,
            _eventNameController.text,
          );
        }
      } else {
        await _firestore.collection('events').add(data);
      }

      // 6. Quay lại màn hình trước
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Event ${_isEditing ? 'updated' : 'created'} successfully!',
            ),
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      // 7. Xử lý lỗi
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save event: $e')));
    }
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label,
    String hint,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          decoration: InputDecoration(
            hintText: hint,
            border: OutlineInputBorder(
              borderRadius: kDefaultBorderRadius, // <-- Dùng hằng số
              borderSide: BorderSide.none,
            ),
            filled: true,
            fillColor: Colors.grey[200],
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
          validator: (value) => value!.isEmpty ? 'Please enter a $label' : null,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kWhiteColor,
      appBar: AppBar(
        // ... (AppBar giữ nguyên) ...
        backgroundColor: kWhiteColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: kPrimaryColor),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          _isEditing ? 'Edit Event' : 'Create New Event',
          style: const TextStyle(
            color: kPrimaryColor,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(kDefaultPadding),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ... (Widget chọn ảnh giữ nguyên) ...
                  Container(
                    height: 200,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: kDefaultBorderRadius,
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: GestureDetector(
                      onTap: _pickImage,
                      child: ClipRRect(
                        borderRadius: kDefaultBorderRadius,
                        child: _pickedImageFile != null
                            ? Image.file(_pickedImageFile!, fit: BoxFit.cover)
                            : (_isEditing && _existingImageUrl != null)
                            ? CachedNetworkImage(
                                imageUrl: _existingImageUrl!,
                                fit: BoxFit.cover,
                                placeholder: (context, url) => const Center(
                                  child: CircularProgressIndicator(),
                                ),
                                errorWidget: (context, url, error) =>
                                    const Icon(Icons.error),
                              )
                            : Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.camera_alt_outlined,
                                      color: Colors.grey[600],
                                      size: 50,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Tap to add event image',
                                      style: TextStyle(color: Colors.grey[700]),
                                    ),
                                  ],
                                ),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // --- Lựa chọn Creator ---
                  const Text(
                    'Tạo với tư cách',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Chỉ cho phép Sửa/Chọn nếu đang tạo mới
                  if (!_isEditing)
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'individual',
                          label: Text('Cá nhân'),
                          icon: Icon(Icons.person),
                        ),
                        ButtonSegment(
                          value: 'team',
                          label: Text('Đội'),
                          icon: Icon(Icons.group),
                        ),
                      ],
                      selected: {_creatorType},
                      onSelectionChanged: (Set<String> newSelection) {
                        setState(() {
                          _creatorType = newSelection.first;
                          _selectedTeamId = null; // Reset team khi chuyển
                          _selectedTeamName = null;
                          _selectedTeamSport =
                              null; // Reset môn thể thao của team
                          // Không reset _selectedSport để user có thể giữ lại lựa chọn cũ
                        });
                      },
                      style: SegmentedButton.styleFrom(
                        backgroundColor: Colors.grey[200],
                        selectedBackgroundColor: const Color(0xFF1976D2),
                        selectedForegroundColor: Colors.white,
                      ),
                    )
                  else // Nếu đang edit, chỉ hiển thị dạng text
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: kDefaultBorderRadius,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _creatorType == 'team' ? Icons.group : Icons.person,
                            color: Colors.grey[700],
                          ),
                          const SizedBox(width: 12),
                          Text(
                            _creatorType == 'team'
                                ? 'Đang sửa với tư cách Đội'
                                : 'Đang sửa với tư cách Cá nhân',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 20),

                  // --- Dropdown chọn Team (có điều kiện) ---
                  // Chỉ hiển thị nếu chọn "Team" VÀ đang tạo mới
                  if (_creatorType == 'team' && !_isEditing)
                    FutureBuilder<List<DocumentSnapshot>>(
                      future: _teamsFuture,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        if (snapshot.hasError ||
                            !snapshot.hasData ||
                            snapshot.data!.isEmpty) {
                          return Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.red[50],
                              borderRadius: kDefaultBorderRadius,
                            ),
                            child: const Text(
                              'Bạn không phải là chủ sở hữu (owner) của bất kỳ đội nào.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.red),
                            ),
                          );
                        }

                        // Lấy danh sách tên team (dùng teamName từ screenshot)
                        final teamItems = snapshot.data!
                            .map(
                              (doc) =>
                                  (doc.data()
                                          as Map<String, dynamic>)['teamName']
                                      as String,
                            )
                            .toList();

                        return Column(
                          children: [
                            CustomDropdownWidget(
                              title: 'Chọn Đội của bạn',
                              items: teamItems,
                              selectedItem: _selectedTeamName,
                              onChanged: (value) {
                                setState(() {
                                  // Tìm team document dựa trên tên
                                  final selectedTeamDoc = snapshot.data!
                                      .firstWhere(
                                        (doc) => doc['teamName'] == value,
                                      );
                                  _selectedTeamName = value;
                                  _selectedTeamId = selectedTeamDoc.id;

                                  // Tự động set môn thể thao theo team
                                  final teamData =
                                      selectedTeamDoc.data()
                                          as Map<String, dynamic>;
                                  _selectedTeamSport = teamData['sport'];
                                  _selectedSport = _selectedTeamSport;
                                });
                              },
                            ),
                            const SizedBox(height: 20),
                          ],
                        );
                      },
                    ),

                  // ------------------------------------
                  _buildTextField(
                    _eventNameController,
                    'Tên sự kiện',
                    'VD: Giao lưu bóng đá Chủ Nhật',
                  ),
                  const SizedBox(height: 20),
                  _buildTextField(
                    _locationNameController,
                    'Tên địa điểm',
                    'VD: Sân vận động Anfield',
                  ),
                  const SizedBox(height: 20),
                  // Hiển thị môn thể thao (disable nếu đang ở chế độ team)
                  _creatorType == 'team' && _selectedTeamSport != null
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Môn thể thao',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                              decoration: BoxDecoration(
                                color: Colors
                                    .grey[300], // Màu xám để thể hiện disabled
                                borderRadius: kDefaultBorderRadius,
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    _selectedTeamSport!,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      color: Colors.black54,
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.lock_outline,
                                        color: Colors.grey[600],
                                        size: 18,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '(Theo đội)',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        )
                      : CustomDropdownWidget(
                          title: 'Môn thể thao',
                          items: _sports,
                          selectedItem: _selectedSport,
                          onChanged: (value) {
                            setState(() {
                              _selectedSport = value;
                            });
                          },
                        ),
                  const SizedBox(height: 20),

                  // --- (MỚI) Thêm Dropdown Trình độ ---
                  CustomDropdownWidget(
                    title: 'Trình độ',
                    items: _skillLevels,
                    selectedItem: _selectedSkillLevel,
                    onChanged: (value) {
                      setState(() {
                        _selectedSkillLevel = value;
                      });
                    },
                  ),
                  const SizedBox(height: 20),
                  // ---------------------------------

                  // --- DatePicker cho thời gian bắt đầu ---
                  const Text(
                    'Thời gian bắt đầu',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: _pickDateTime,
                    borderRadius: kDefaultBorderRadius,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: kDefaultBorderRadius,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _eventDateTime == null
                                ? 'Chọn ngày và giờ bắt đầu'
                                : DateFormat(
                                    'dd/MM/yyyy, hh:mm a',
                                  ).format(_eventDateTime!),
                            style: TextStyle(
                              fontSize: 16,
                              color: _eventDateTime == null
                                  ? Colors.grey[700]
                                  : Colors.black,
                            ),
                          ),
                          Icon(
                            Icons.calendar_today_outlined,
                            color: Colors.grey[700],
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // --- DatePicker cho thời gian kết thúc ---
                  const Text(
                    'Thời gian kết thúc',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: _pickEndDateTime,
                    borderRadius: kDefaultBorderRadius,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: kDefaultBorderRadius,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _eventEndDateTime == null
                                ? 'Chọn ngày và giờ kết thúc'
                                : DateFormat(
                                    'dd/MM/yyyy, hh:mm a',
                                  ).format(_eventEndDateTime!),
                            style: TextStyle(
                              fontSize: 16,
                              color: _eventEndDateTime == null
                                  ? Colors.grey[700]
                                  : Colors.black,
                            ),
                          ),
                          Icon(
                            Icons.calendar_today_outlined,
                            color: Colors.grey[700],
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),
                  // ... (Nút Save giữ nguyên) ...
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _saveEvent,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1976D2),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: kDefaultBorderRadius,
                        ),
                      ),
                      child: Text(
                        _isEditing ? 'Lưu thay đổi' : 'Tạo sự kiện',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.5),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}
