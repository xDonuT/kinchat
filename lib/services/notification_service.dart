import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../screens/chat_screen.dart';
import 'chat_service.dart';

/// Owns push notifications: requests permission, keeps this phone's token in
/// Firestore, shows a local notification for messages that arrive while the
/// app is open, and opens the right chat when a notification is tapped.
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  static const _initSettings = InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
  );

  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  String? _currentRoomId;
  bool _started = false;

  /// The chat currently on screen, so we don't ding you for messages you can
  /// already see.
  void setCurrentRoom(String? roomId) => _currentRoomId = roomId;

  Future<void> init() async {
    if (_started) return;
    _started = true;

    await _local.initialize(
      settings: _initSettings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null) _openRoom(_decode(payload));
      },
    );
    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(alert: true, badge: true, sound: true);

    FirebaseMessaging.onMessage.listen((message) {
      final data = message.data;
      if (data['roomId'] != null && data['roomId'] == _currentRoomId) return;
      _showLocal(
        message.notification?.title ?? 'KinChat',
        message.notification?.body ?? 'New message',
        data,
      );
    });

    FirebaseMessaging.onMessageOpenedApp.listen(
      (message) => _openRoom(message.data),
    );

    final initial = await messaging.getInitialMessage();
    if (initial != null) _openRoom(initial.data);
  }

  /// Keep this phone's token up to date for the signed-in account.
  Future<void> handleSignedIn() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final messaging = FirebaseMessaging.instance;
      final token = await messaging.getToken();
      if (token != null) await _storeToken(uid, token);
      messaging.onTokenRefresh.listen((t) => _storeToken(uid, t));
    } catch (err) {
      debugPrint('KinChat: notification setup skipped: $err');
    }
  }

  Future<void> _storeToken(String uid, String token) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('tokens')
          .doc('phone')
          .set({
        'token': token,
        'platform': 'android',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (err) {
      debugPrint('KinChat: could not save notification token: $err');
    }
  }

  Future<void> _showLocal(
    String title,
    String body,
    Map<String, dynamic> data,
  ) async {
    await _local.show(
      id: 1,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'kinchat',
          'KinChat messages',
          channelDescription: 'Notifications when someone messages you',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      payload: jsonEncode(data),
    );
  }

  Map<String, dynamic> _decode(String payload) {
    try {
      final decoded = jsonDecode(payload) as Map<String, dynamic>;
      return decoded;
    } catch (_) {
      return const {};
    }
  }

  Future<void> _openRoom(Map<String, dynamic> data) async {
    final nav = navigatorKey.currentState;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final roomId = data['roomId']?.toString();
    if (nav == null || uid == null || roomId == null || roomId.isEmpty) {
      return;
    }
    final room = data['room'] == 'group'
        ? ChatRoom.group()
        : ChatRoom.private(roomId);
    nav.push(
      MaterialPageRoute<void>(
        builder: (_) => ChatScreen(
          uid: uid,
          room: room,
          title: data['title']?.toString() ?? 'KinChat',
          names: const {},
        ),
      ),
    );
  }
}