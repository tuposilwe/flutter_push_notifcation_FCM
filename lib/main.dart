import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;

import 'firebase_options.dart';

/// Must be a top-level function: this runs in a separate isolate when a
/// message arrives while the app is terminated or in the background.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint('Handling a background message: ${message.messageId}');
}

final FlutterLocalNotificationsPlugin _localNotifications =
    FlutterLocalNotificationsPlugin();

const AndroidNotificationChannel _channel = AndroidNotificationChannel(
  'high_importance_channel',
  'High Importance Notifications',
  description: 'Used for important notifications shown while the app is open.',
  importance: Importance.high,
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Register the background/terminated handler as early as possible.
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  await _initLocalNotifications();

  runApp(const MyApp());
}

Future<void> _initLocalNotifications() async {
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const iosInit = DarwinInitializationSettings();
  const initSettings = InitializationSettings(android: androidInit, iOS: iosInit);

  await _localNotifications.initialize(settings: initSettings);

  await _localNotifications
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(_channel);
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FCM Notification Demo',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const NotificationHomePage(),
    );
  }
}

class NotificationHomePage extends StatefulWidget {
  const NotificationHomePage({super.key});

  @override
  State<NotificationHomePage> createState() => _NotificationHomePageState();
}

class _NotificationHomePageState extends State<NotificationHomePage> {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final TextEditingController _topicController = TextEditingController(text: 'news');

  String? _token;
  bool _subscribed = false;
  final List<_ReceivedMessage> _messages = [];

  @override
  void initState() {
    super.initState();
    _setup();
  }

  Future<void> _setup() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    debugPrint('Permission status: ${settings.authorizationStatus}');

    final token = await _messaging.getToken();
    setState(() => _token = token);
    debugPrint('FCM token: $token');

    _messaging.onTokenRefresh.listen((newToken) {
      setState(() => _token = newToken);
    });

    // Foreground messages: FCM does not show a system notification on its
    // own, so display one via flutter_local_notifications.
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      _logMessage(message, source: 'foreground');
      _showLocalNotification(message);
    });

    // App was in the background and the user tapped the notification.
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _logMessage(message, source: 'opened from background');
    });

    // App was terminated and launched by tapping a notification.
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _logMessage(initialMessage, source: 'opened from terminated');
    }
  }

  void _logMessage(RemoteMessage message, {required String source}) {
    setState(() {
      _messages.insert(
        0,
        _ReceivedMessage(
          title: message.notification?.title ?? '(no title)',
          body: message.notification?.body ?? '(no body)',
          source: source,
          data: message.data,
        ),
      );
    });
  }

  Future<void> _showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    final imageUrl = notification.android?.imageUrl ?? notification.apple?.imageUrl;
    final image = imageUrl == null ? null : await _downloadImage(imageUrl);

    await _localNotifications.show(
      id: notification.hashCode,
      title: notification.title,
      body: notification.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
          styleInformation: image == null
              ? null
              : BigPictureStyleInformation(
                  ByteArrayAndroidBitmap(image.bytes),
                  largeIcon: ByteArrayAndroidBitmap(image.bytes),
                ),
        ),
        iOS: DarwinNotificationDetails(
          attachments: image == null ? null : [DarwinNotificationAttachment(image.path)],
        ),
      ),
    );
  }

  /// Downloads the image and saves it to a temp file: the Android bitmap
  /// style takes raw bytes, but the iOS attachment API only accepts a file path.
  Future<({Uint8List bytes, String path})?> _downloadImage(String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) return null;

      final dir = await Directory.systemTemp.createTemp('fcm_image_');
      final file = File('${dir.path}/image.jpg');
      await file.writeAsBytes(response.bodyBytes);

      return (bytes: response.bodyBytes, path: file.path);
    } catch (e) {
      debugPrint('Failed to download notification image: $e');
      return null;
    }
  }

  Future<void> _toggleTopic() async {
    final topic = _topicController.text.trim();
    if (topic.isEmpty) return;

    if (_subscribed) {
      await _messaging.unsubscribeFromTopic(topic);
    } else {
      await _messaging.subscribeToTopic(topic);
    }
    setState(() => _subscribed = !_subscribed);
  }

  void _copyToken() {
    final token = _token;
    if (token == null) return;
    Clipboard.setData(ClipboardData(text: token));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Token copied to clipboard')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Firebase Push Notifications')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Device token', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SelectableText(
                    _token ?? 'Fetching token…',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy),
                  onPressed: _copyToken,
                  tooltip: 'Copy token',
                ),
              ],
            ),
            const Divider(height: 32),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _topicController,
                    decoration: const InputDecoration(labelText: 'Topic'),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: _toggleTopic,
                  child: Text(_subscribed ? 'Unsubscribe' : 'Subscribe'),
                ),
              ],
            ),
            const Divider(height: 32),
            Text('Received messages', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Expanded(
              child: _messages.isEmpty
                  ? const Center(child: Text('No messages yet'))
                  : ListView.builder(
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final m = _messages[index];
                        return Card(
                          child: ListTile(
                            title: Text(m.title),
                            subtitle: Text('${m.body}\nsource: ${m.source}'),
                            isThreeLine: true,
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReceivedMessage {
  _ReceivedMessage({
    required this.title,
    required this.body,
    required this.source,
    required this.data,
  });

  final String title;
  final String body;
  final String source;
  final Map<String, dynamic> data;
}
