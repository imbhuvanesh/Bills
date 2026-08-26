import 'dart:async';

import 'package:alarm_volume_control/alarm.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

final FlutterLocalNotificationsPlugin _flutterLocalNotifications =
    FlutterLocalNotificationsPlugin();

@pragma('vm:entry-point')
void onDidReceiveBackgroundNotificationResponse(NotificationResponse response) {
  if (response.actionId == 'turn_off_alarm') {
    final alarmId = int.tryParse(response.payload ?? '');
    if (alarmId != null) {
      Alarm.stop(alarmId);
    }
  }
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();

  factory NotificationService() => _instance;

  NotificationService._internal();

  bool _initialized = false;
  StreamSubscription<dynamic>? _ringingSubscription;

  Set<int> _previouslyRinging = {};
  final Set<int> _stoppedAlarmIds = {};

  void Function(int alarmId)? onTurnOff;

  static const _channelId = 'bills_alarm_channel';
  static const _channelName = 'Bill Reminders';
  static const _notificationId = 99999;

  Future<void> init() async {
    if (_initialized) return;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);

    await _flutterLocalNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        if (response.actionId == 'turn_off_alarm') {
          final alarmId = int.tryParse(response.payload ?? '');
          if (alarmId != null) {
            _stopAlarmAndComplete(alarmId);
          }
        }
      },
      onDidReceiveBackgroundNotificationResponse:
          onDidReceiveBackgroundNotificationResponse,
    );

    final androidPlugin = _flutterLocalNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: 'Notifications for bill reminder alarms',
          importance: Importance.max,
          enableVibration: true,
          playSound: true,
        ),
      );
    }

    await Alarm.init();

    _ringingSubscription ??= Alarm.ringing.listen((alarmSet) {
      final currentIds = alarmSet.alarms.map((a) => a.id).toSet();

      for (final alarm in alarmSet.alarms) {
        if (!_previouslyRinging.contains(alarm.id)) {
          final title = alarm.notificationSettings.title;
          final body = alarm.notificationSettings.body;
          _showAlarmNotification(title, body, alarm.id);
        }
      }

      for (final prevId in _previouslyRinging) {
        if (!currentIds.contains(prevId)) {
          _stoppedAlarmIds.add(prevId);
          _cancelNotification();
        }
      }

      _previouslyRinging = Set<int>.from(currentIds);
    });

    _initialized = true;
  }

  Future<bool> requestPermission() async {
    final androidPlugin = _flutterLocalNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin == null) return true;
    final result = await androidPlugin.requestNotificationsPermission();
    return result ?? false;
  }

  void _stopAlarmAndComplete(int alarmId) {
    Alarm.stop(alarmId);
    _cancelNotification();
    onTurnOff?.call(alarmId);
  }

  void _showAlarmNotification(String title, String body, int alarmId) {
    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: 'Notifications for bill reminder alarms',
      importance: Importance.max,
      priority: Priority.high,
      ongoing: true,
      autoCancel: false,
      fullScreenIntent: true,
      actions: [
        const AndroidNotificationAction(
          'turn_off_alarm',
          'Turn Off',
          showsUserInterface: true,
          cancelNotification: true,
        ),
      ],
    );

    final details = NotificationDetails(android: androidDetails);

    _flutterLocalNotifications.show(
      _notificationId,
      title,
      body,
      details,
      payload: alarmId.toString(),
    );
  }

  void _cancelNotification() {
    _flutterLocalNotifications.cancel(_notificationId);
  }

  Set<int> consumeStoppedAlarmIds() {
    final ids = Set<int>.from(_stoppedAlarmIds);
    _stoppedAlarmIds.clear();
    return ids;
  }

  Set<int> getActiveAlarmIds() {
    return Set<int>.from(_previouslyRinging);
  }

  static int buildReminderId(String title, DateTime dueDate) {
    var hash = 17;
    final value = '$title|${dueDate.toIso8601String()}';
    for (final codeUnit in value.codeUnits) {
      hash = (hash * 31 + codeUnit) & 0x7fffffff;
    }
    return hash == 0 ? 1 : hash;
  }

  Future<void> scheduleReminder({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
  }) async {
    await init();
    await Alarm.stop(id);

    final localScheduledDate = DateTime(
      scheduledDate.year,
      scheduledDate.month,
      scheduledDate.day,
      scheduledDate.hour,
      scheduledDate.minute,
    );

    if (localScheduledDate.isBefore(DateTime.now()) &&
        !isSameLocalDate(localScheduledDate, DateTime.now())) {
      return;
    }

    final fireAt = localScheduledDate.isBefore(DateTime.now())
        ? DateTime.now().add(const Duration(seconds: 1))
        : localScheduledDate;

    await Alarm.set(
      alarmSettings: AlarmSettings(
        id: id,
        dateTime: fireAt,
        volumeSettings: const VolumeSettings.fixed(volume: 1),
        notificationSettings: NotificationSettings(
          title: title,
          body: body,
          stopButton: 'Turn off',
        ),
        loopAudio: true,
        vibrate: true,
        warningNotificationOnKill: false,
      ),
    );
  }

  bool isSameLocalDate(DateTime first, DateTime second) =>
      first.year == second.year &&
      first.month == second.month &&
      first.day == second.day;

  Future<void> cancel(int id) async {
    await init();
    await Alarm.stop(id);
    _cancelNotification();
  }

  Future<void> cancelAll() async {
    await init();
    await Alarm.stopAll();
    _cancelNotification();
  }
}
