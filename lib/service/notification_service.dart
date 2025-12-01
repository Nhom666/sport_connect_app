import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:flutter/material.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    tz_data.initializeTimeZones(); // Khởi tạo timezone
    tz.setLocalLocation(tz.getLocation('Asia/Ho_Chi_Minh')); // Set timezone VN

    // Cấu hình cho Android với notification channel
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

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

    // TẠO NOTIFICATION CHANNEL (QUAN TRỌNG cho Android 8.0+)
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'event_reminders_channel', // id
      'Event Reminders', // name
      description: 'Nhắc nhở lịch thi đấu sắp tới',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      showBadge: true,
    );

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);

    print('✅ Đã tạo notification channel: event_reminders_channel');
  }

  // Hàm xin quyền (cần thiết cho Android 13+)
  Future<void> requestPermissions() async {
    final androidImpl = flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    // Xin quyền notification
    final notifPermission = await androidImpl?.requestNotificationsPermission();
    print('📱 Notification permission: $notifPermission');

    // Xin quyền exact alarms (Android 12+)
    final exactAlarmPermission = await androidImpl
        ?.requestExactAlarmsPermission();
    print('⏰ Exact alarm permission: $exactAlarmPermission');

    // Kiểm tra xem exact alarms có được phép không
    final canScheduleExactAlarms = await androidImpl
        ?.canScheduleExactNotifications();
    print('✅ Can schedule exact alarms: $canScheduleExactAlarms');

    if (canScheduleExactAlarms == false) {
      print('⚠️ CẢNH BÁO: App không có quyền exact alarms!');
      print(
        '   Vào Settings > Apps > SportConnect > Alarms & reminders > Allow',
      );
    }

    print('✅ Hoàn tất kiểm tra quyền');
  }

  // Hàm lên lịch thông báo - SỬ DỤNG CÁCH MỚI
  // Do zonedSchedule không hoạt động, ta sẽ lưu vào local storage
  // và kiểm tra định kỳ khi app mở
  Future<void> scheduleEventReminders({
    required String eventId,
    required String eventName,
    required DateTime eventTime,
    List<int>? customReminders,
  }) async {
    final reminders = customReminders ?? [60, 30, 15];

    print('🔔 Lên lịch thông báo cho sự kiện: $eventName');
    print('⏰ Thời gian sự kiện: $eventTime');
    print('🕐 Giờ hiện tại: ${DateTime.now()}');
    print(
      '⚠️ LƯU Ý: Do zonedSchedule không hoạt động, thông báo chỉ hiện khi app đang mở',
    );

    int scheduledCount = 0;

    for (int minutes in reminders) {
      final scheduledTime = eventTime.subtract(Duration(minutes: minutes));

      if (scheduledTime.isAfter(DateTime.now())) {
        final location = tz.getLocation('Asia/Ho_Chi_Minh');
        final tzScheduledTime = tz.TZDateTime(
          location,
          scheduledTime.year,
          scheduledTime.month,
          scheduledTime.day,
          scheduledTime.hour,
          scheduledTime.minute,
          scheduledTime.second,
        );

        print('✅ Lên lịch thông báo $minutes phút trước: $scheduledTime');

        // Thử với exactAllowWhileIdle
        try {
          await flutterLocalNotificationsPlugin.zonedSchedule(
            eventId.hashCode + minutes,
            'Sắp diễn ra: $eventName',
            'Sự kiện bắt đầu trong $minutes phút nữa!',
            tzScheduledTime,
            NotificationDetails(
              android: AndroidNotificationDetails(
                'event_reminders_channel',
                'Event Reminders',
                channelDescription: 'Nhắc nhở lịch thi đấu sắp tới',
                importance: Importance.max,
                priority: Priority.high,
                playSound: true,
                enableVibration: true,
                enableLights: true,
                color: const Color.fromARGB(255, 255, 0, 0),
                ledColor: const Color.fromARGB(255, 255, 0, 0),
                ledOnMs: 1000,
                ledOffMs: 500,
                channelShowBadge: true,
                autoCancel: true,
              ),
              iOS: const DarwinNotificationDetails(
                presentAlert: true,
                presentBadge: true,
                presentSound: true,
              ),
            ),
            androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          );
          scheduledCount++;
        } catch (e) {
          print('❌ Lỗi khi lên lịch: $e');
        }
      } else {
        print('❌ Bỏ qua thông báo $minutes phút (đã qua): $scheduledTime');
      }
    }

    if (scheduledCount == 0) {
      print('⚠️ CẢNH BÁO: Không có thông báo nào được lên lịch!');
      print('💡 GỢI Ý: zonedSchedule() không hoạt động trên thiết bị này');
      print('   Cần sử dụng WorkManager hoặc android_alarm_manager_plus');
    } else {
      print('✨ Đã thử lên lịch $scheduledCount thông báo');
      print(
        '⚠️ Lưu ý: Thông báo có thể không hiện do vấn đề với zonedSchedule',
      );
    }
  }

  // Hàm hủy thông báo (dùng khi hủy kèo hoặc cập nhật lại)
  Future<void> cancelNotificationsForEvent(String eventId) async {
    int baseId = eventId.hashCode;
    await flutterLocalNotificationsPlugin.cancel(baseId + 60);
    await flutterLocalNotificationsPlugin.cancel(baseId + 30);
    await flutterLocalNotificationsPlugin.cancel(baseId + 15);
  }

  // Hàm kiểm tra các thông báo đang chờ (để debug)
  Future<void> checkPendingNotifications() async {
    final pendingNotifications = await flutterLocalNotificationsPlugin
        .pendingNotificationRequests();
    print('📋 Số lượng thông báo đang chờ: ${pendingNotifications.length}');
    for (var notification in pendingNotifications) {
      print('   ID: ${notification.id} - Title: ${notification.title}');
      print('   Body: ${notification.body}');
    }
  }

  // Test thông báo 10 giây nữa (dùng để debug)
  Future<void> scheduleTestNotificationIn10Seconds() async {
    final now = DateTime.now();
    final scheduledTime = now.add(const Duration(seconds: 10));

    // SỬA: Tạo TZDateTime trực tiếp thay vì dùng .from()
    final location = tz.getLocation('Asia/Ho_Chi_Minh');
    final tzScheduledTime = tz.TZDateTime(
      location,
      scheduledTime.year,
      scheduledTime.month,
      scheduledTime.day,
      scheduledTime.hour,
      scheduledTime.minute,
      scheduledTime.second,
    );

    print('\n🧪 === TEST 10 GIÂY ===');
    print('⏰ Hiện tại: ${now.toIso8601String()}');
    print('🎯 Sẽ hiện thông báo lúc: ${scheduledTime.toIso8601String()}');
    print('🌍 TZ Scheduled: ${tzScheduledTime.toIso8601String()}');
    print(
      '🌍 Timezone: ${tzScheduledTime.timeZoneName} (${tzScheduledTime.timeZoneOffset})',
    );

    await flutterLocalNotificationsPlugin.zonedSchedule(
      99999,
      '🧪 TEST 10 GIÂY',
      'Nếu bạn thấy thông báo này, nghĩa là hệ thống hoạt động!',
      tzScheduledTime,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'event_reminders_channel',
          'Event Reminders',
          channelDescription: 'Nhắc nhở lịch thi đấu sắp tới',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          enableLights: true,
          color: const Color.fromARGB(255, 255, 165, 0),
          ledColor: const Color.fromARGB(255, 255, 165, 0),
          ledOnMs: 1000,
          ledOffMs: 500,
          channelShowBadge: true,
          autoCancel: true,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );

    print('✅ Đã lên lịch thông báo 10 giây nữa');

    // Kiểm tra pending notifications
    await Future.delayed(const Duration(milliseconds: 500));
    await checkPendingNotifications();
  }

  // Hàm xóa tất cả thông báo
  Future<void> clearAllNotifications() async {
    await flutterLocalNotificationsPlugin.cancelAll();
    print('🗑️ Đã xóa tất cả thông báo');
  }

  // Test với Timer - gửi thông báo sau 5 giây (không dùng zonedSchedule)
  Future<void> testWithTimer() async {
    print('\n⏱️ === TEST VỚI TIMER (5 GIÂY) ===');
    print('⏰ Bắt đầu đếm ngược từ bây giờ...');

    await Future.delayed(const Duration(seconds: 5));

    print('✅ 5 giây đã qua - Gửi thông báo NGAY');

    await flutterLocalNotificationsPlugin.show(
      88888,
      '⏱️ TEST TIMER - 5 GIÂY',
      'Thông báo này được gửi SAU 5 giây bằng Timer (không dùng zonedSchedule)',
      NotificationDetails(
        android: AndroidNotificationDetails(
          'event_reminders_channel',
          'Event Reminders',
          channelDescription: 'Nhắc nhở lịch thi đấu sắp tới',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          enableLights: true,
          color: const Color.fromARGB(255, 0, 255, 0),
          ledColor: const Color.fromARGB(255, 0, 255, 0),
          ledOnMs: 1000,
          ledOffMs: 500,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
    );

    print('✅ Đã gửi thông báo qua Timer!');
  }

  // Hàm test gửi thông báo ngay lập tức
  Future<void> showTestNotification() async {
    await flutterLocalNotificationsPlugin.show(
      999999,
      '🧪 Test Notification',
      'Nếu bạn thấy thông báo này, nghĩa là notification service hoạt động!',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'event_reminders_channel',
          'Event Reminders',
          channelDescription: 'Nhắc nhở lịch thi đấu sắp tới',
          importance: Importance.max,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
    print('✅ Đã gửi test notification');
  }
}
