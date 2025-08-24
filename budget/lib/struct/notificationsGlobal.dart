import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// The plugin instance for showing notifications.
FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

// A class to hold the details of a notification that the app was opened with.
// This is used in main.dart to handle what happens when the app is launched from a notification.
class NotificationPayload {
  const NotificationPayload({
    required this.id,
    this.title,
    this.body,
    this.payload,
  });

  final int id;
  final String? title;
  final String? body;
  final String? payload;
}
