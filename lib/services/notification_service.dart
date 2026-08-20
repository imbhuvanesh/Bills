import 'dart:async';

import 'package:alarm_volume_control/alarm.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();

  factory NotificationService() => _instance;

  NotificationService._internal();

  bool _initialized = false;
  Future<void> Function(int alarmId)? _onAlarmTriggered;
  StreamSubscription<dynamic>? _ringingSubscription;

  Future<void> init() async {
    if (_initialized) {
      return;
    }

    await Alarm.init();
    _ringingSubscription ??= Alarm.ringing.listen((alarms) {
      for (final alarm in alarms.alarms) {
        final callback = _onAlarmTriggered;
        if (callback != null) {
          unawaited(callback(alarm.id));
        }
      }
    });
    _initialized = true;
  }

  void setAlarmTriggeredCallback(Future<void> Function(int alarmId) callback) {
    _onAlarmTriggered = callback;
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

    await Alarm.set(
      alarmSettings: AlarmSettings(
        id: id,
        dateTime: localScheduledDate.isBefore(DateTime.now())
            ? DateTime.now().add(const Duration(seconds: 1))
            : localScheduledDate,
        volumeSettings: const VolumeSettings.fixed(volume: 1),
        notificationSettings: NotificationSettings(
          title: title,
          body: body,
          stopButton: 'Turn off alarm',
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
  }

  Future<void> cancelAll() async {
    await init();
    await Alarm.stopAll();
  }
}
