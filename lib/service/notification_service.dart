import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    tz_data.initializeTimeZones(); // Khởi tạo timezone

    // Cấu hình cho Android
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings(
          '@mipmap/ic_launcher',
        ); // Đảm bảo icon này tồn tại

    // Cấu hình cho iOS
    const DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings(
          requestSoundPermission: true,
          requestBadgePermission: true,
          requestAlertPermission: true,
        );

    final InitializationSettings initializationSettings =
        InitializationSettings(
          android: initializationSettingsAndroid,
          iOS: initializationSettingsDarwin,
        );

    await flutterLocalNotificationsPlugin.initialize(initializationSettings);
  }

  // Hàm xin quyền (cần thiết cho Android 13+)
  Future<void> requestPermissions() async {
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
  }

  // Hàm lên lịch thông báo
  Future<void> scheduleEventReminders({
    required String eventId,
    required String eventName,
    required DateTime eventTime,
  }) async {
    // ID cơ sở cho event này (dùng hashcode để tạo số nguyên duy nhất từ String ID)
    int baseId = eventId.hashCode;

    // Danh sách các mốc thời gian nhắc nhở (phút)
    final reminders = [60, 30, 15];

    for (int minutes in reminders) {
      final scheduledTime = eventTime.subtract(Duration(minutes: minutes));

      // Chỉ lên lịch nếu thời gian nhắc nhở nằm trong tương lai
      if (scheduledTime.isAfter(DateTime.now())) {
        await flutterLocalNotificationsPlugin.zonedSchedule(
          baseId + minutes, // ID duy nhất cho mỗi mốc giờ của sự kiện
          'Sắp diễn ra: $eventName',
          'Sự kiện bắt đầu trong $minutes phút nữa!',
          tz.TZDateTime.from(scheduledTime, tz.local),
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'event_reminders_channel', // Id channel
              'Event Reminders', // Tên channel
              channelDescription: 'Nhắc nhở lịch thi đấu sắp tới',
              importance: Importance.max,
              priority: Priority.high,
            ),
            iOS: DarwinNotificationDetails(),
          ),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        );
      }
    }
  }

  // Hàm hủy thông báo (dùng khi hủy kèo hoặc cập nhật lại)
  Future<void> cancelNotificationsForEvent(String eventId) async {
    int baseId = eventId.hashCode;
    await flutterLocalNotificationsPlugin.cancel(baseId + 60);
    await flutterLocalNotificationsPlugin.cancel(baseId + 30);
    await flutterLocalNotificationsPlugin.cancel(baseId + 15);
  }
}
