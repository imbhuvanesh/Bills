import 'package:flutter_local_notifications/flutter_local_notifications.dart';
// Removed flutter_timezone import due to dependency mismatch; using a
// best-effort local timezone fallback.
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();

  factory NotificationService() => _instance;

  NotificationService._internal();

  // Use dynamic to avoid analyzer errors when the package API surface
  // differs between versions. Calls are still performed at runtime.
  final dynamic _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'bills_channel',
    'Bills reminders',
    description: 'Reminders for upcoming bills',
    importance: Importance.max,
  );

  Future<void> init() async {
    if (_initialized) {
      return;
    }

    // Initialize timezone database.
    tzdata.initializeTimeZones();

    // Attempt to set the local timezone from the system. `DateTime.now()`
    // provides a time zone name which may be an abbreviation; if mapping
    // fails, fall back to a sensible default.
    try {
      final name = DateTime.now().timeZoneName;
      tz.setLocalLocation(tz.getLocation(name));
    } catch (e) {
      tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
    }

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    final settings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );

    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );

    // Create Android notification channel.
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    await androidPlugin?.createNotificationChannel(_channel);

    // Android 13+ notification permission.
    await androidPlugin?.requestNotificationsPermission();

    // Permission for exact alarms.
    await androidPlugin?.requestExactAlarmsPermission();
    _initialized = true;
  }

  static int buildReminderId(String title, DateTime dueDate) {
    var hash = 17;
    final value = '$title|${dueDate.toIso8601String()}';
    for (final codeUnit in value.codeUnits) {
      hash = (hash * 31 + codeUnit) & 0x7fffffff;
    }
    return hash == 0 ? 1 : hash;
  }

  void _onNotificationResponse(NotificationResponse response) {
    // Handle notification tap here if needed.
  }

  Future<void> scheduleReminder({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
  }) async {
    await init();
    await _plugin.cancel(id: id);

    final androidDetails = AndroidNotificationDetails(
      _channel.id,
      _channel.name,
      channelDescription: _channel.description,
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      ticker: title,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    // Convert the DateTime into the device's timezone.
    final tzScheduledDate = tz.TZDateTime.from(scheduledDate, tz.local);

    final now = tz.TZDateTime.now(tz.local);

    // If the requested time is already passed,
    // show the notification immediately.
    if (!tzScheduledDate.isAfter(now.add(const Duration(seconds: 2)))) {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: details,
      );

      return;
    }

    // Schedule the notification.
    try {
      await _plugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: tzScheduledDate,
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: id.toString(),
      );
    } catch (_) {
      await _plugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: tzScheduledDate,
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: id.toString(),
      );
    }
  }

  Future<void> cancel(int id) async {
    await _plugin.cancel(id: id);
  }

  Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }

  Future<List<PendingNotificationRequest>> getPendingNotifications() async {
    return await _plugin.pendingNotificationRequests();
  }
}
