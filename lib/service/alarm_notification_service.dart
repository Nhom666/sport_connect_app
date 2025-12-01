import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:flutter/material.dart';

// Callback phải là top-level function hoặc static method
@pragma('vm:entry-point')
void alarmCallback() async {
  print('🔔 ALARM CALLBACK TRIGGERED!');

  // Lấy thông tin từ SharedPreferences
  final prefs = await SharedPreferences.getInstance();
  final String? eventDataJson = prefs.getString('pending_notification');

  if (eventDataJson != null) {
    final eventData = json.decode(eventDataJson);
    final String eventName = eventData['eventName'] ?? 'Sự kiện';
    final int minutes = eventData['minutes'] ?? 15;

    print('📱 Gửi thông báo: $eventName ($minutes phút trước)');

    // Gửi thông báo
    final FlutterLocalNotificationsPlugin notificationsPlugin =
        FlutterLocalNotificationsPlugin();

    await notificationsPlugin.show(
      DateTime.now().millisecondsSinceEpoch % 100000,
      'Sắp diễn ra: $eventName',
      'Sự kiện bắt đầu trong $minutes phút nữa!',
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
        ),
      ),
    );

    print('✅ Đã gửi thông báo qua AlarmManager!');
  }
}

class AlarmNotificationService {
  static final AlarmNotificationService _instance =
      AlarmNotificationService._internal();
  factory AlarmNotificationService() => _instance;
  AlarmNotificationService._internal();

  Future<void> init() async {
    await AndroidAlarmManager.initialize();
    print('✅ AlarmManager đã khởi tạo');
  }

  Future<void> scheduleEventReminders({
    required String eventId,
    required String eventName,
    required DateTime eventTime,
    List<int>? customReminders,
  }) async {
    final reminders = customReminders ?? [60, 30, 15];
    final prefs = await SharedPreferences.getInstance();

    print('🔔 [AlarmManager] Lên lịch thông báo cho: $eventName');
    print('⏰ Thời gian sự kiện: $eventTime');
    print('🕐 Giờ hiện tại: ${DateTime.now()}');

    int scheduledCount = 0;

    for (int minutes in reminders) {
      final scheduledTime = eventTime.subtract(Duration(minutes: minutes));

      if (scheduledTime.isAfter(DateTime.now())) {
        // Lưu thông tin sự kiện vào SharedPreferences
        final eventData = {
          'eventId': eventId,
          'eventName': eventName,
          'minutes': minutes,
        };
        await prefs.setString('pending_notification', json.encode(eventData));

        // Tính milliseconds từ bây giờ đến thời điểm cần nhắc
        final alarmId = eventId.hashCode + minutes;
        final delay = scheduledTime.difference(DateTime.now());

        print('✅ Lên lịch alarm $minutes phút trước: $scheduledTime');
        print('   Alarm ID: $alarmId');
        print('   Delay: ${delay.inSeconds} seconds');

        await AndroidAlarmManager.oneShot(
          delay,
          alarmId,
          alarmCallback,
          exact: true,
          wakeup: true,
          rescheduleOnReboot: true,
        );

        scheduledCount++;
      } else {
        print('❌ Bỏ qua thông báo $minutes phút (đã qua): $scheduledTime');
      }
    }

    if (scheduledCount > 0) {
      print(
        '✨ [AlarmManager] Đã lên lịch $scheduledCount/${reminders.length} thông báo',
      );
      print('🎯 Thông báo sẽ hoạt động ngay cả khi app đóng!');
    } else {
      print('⚠️ Không có thông báo nào được lên lịch (tất cả đã qua)');
    }
  }

  Future<void> cancelNotificationsForEvent(String eventId) async {
    final reminders = [60, 30, 15];
    for (int minutes in reminders) {
      final alarmId = eventId.hashCode + minutes;
      await AndroidAlarmManager.cancel(alarmId);
    }
    print('🗑️ Đã hủy alarm cho event: $eventId');
  }

  // Test với alarm 10 giây nữa
  Future<void> testAlarmIn10Seconds() async {
    final prefs = await SharedPreferences.getInstance();

    print('\n🧪 === TEST ALARM 10 GIÂY ===');
    print('⏰ Hiện tại: ${DateTime.now().toIso8601String()}');

    final eventData = {'eventName': 'TEST Alarm 10 giây', 'minutes': 10};
    await prefs.setString('pending_notification', json.encode(eventData));

    await AndroidAlarmManager.oneShot(
      const Duration(seconds: 10),
      99999,
      alarmCallback,
      exact: true,
      wakeup: true,
    );

    print('✅ Đã lên lịch alarm 10 giây nữa');
    print('🎯 Thông báo sẽ hiện NGAY CẢ KHI APP ĐÓNG!');
  }
}
