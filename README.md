# pushnotification

A Flutter sample app demonstrating Firebase Cloud Messaging (FCM): permission requests, device
tokens, topic subscriptions, and handling push notifications in foreground, background, and
terminated app states.

For the full write-up — architecture, file-by-file explanation, testing steps, and a log of setup
issues and fixes — see [Firebase_Push_Notifications_Guide.md](Firebase_Push_Notifications_Guide.md)
(also available as [Firebase_Push_Notifications_Guide.pdf](Firebase_Push_Notifications_Guide.pdf)).

## Quick start

```bash
flutter pub get
flutter run
```

Grant the notification permission prompt, then copy the device token shown in the app.

## Send a test notification

1. Open [Firebase Console → Messaging](https://console.firebase.google.com/project/pushnotification-4281b/messaging).
2. **New campaign → Notifications**, or use **Send test message** with the copied device token.
3. To target the topic subscribed to in-app (default `news`), set **Target → Topic** to the same name.

## Firebase project

This app is wired to the Firebase project `pushnotification-4281b`. Platform config
(`lib/firebase_options.dart`, `android/app/google-services.json`,
`ios/Runner/GoogleService-Info.plist`) was generated with:

```bash
dart pub global run flutterfire_cli:flutterfire configure
```

Re-run that command if you add/remove platforms or switch to a different Firebase project.
