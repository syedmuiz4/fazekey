# FaceKey

FaceKey is a Flutter Final Year Project app for smart campus access control. It uses Firebase Auth and Firestore for cloud data, Google ML Kit for face detection, MobileFaceNet through TensorFlow Lite for 192-dimensional embeddings, SQLite for offline face matching, and a pending-log queue that syncs when Firestore is reachable again.

## Features

- Email/password login and administrator registration
- Three-sample face registration with live camera guide overlay
- Offline face login using local SQLite embeddings and Euclidean distance
- Firestore-backed users, areas, access logs, notifications, and dashboard stats
- Dashboard with bottom navigation, glassmorphic cards, weekly usage chart, add-area action, and report action placeholder
- Areas management with realtime list, pull-to-refresh, add area form, edit and permissions actions
- Searchable and paginated access logs
- Realtime notifications
- Settings with profile, recognition state, grouped system options, dark mode, and logout
- Animated access success/failure result

## Firebase Setup

1. Create a Firebase project.
2. Enable **Authentication > Email/Password**.
3. Create Cloud Firestore.
4. Add Android and iOS apps using your package IDs.
5. Download and place:
   - `android/app/google-services.json`
   - `ios/Runner/GoogleService-Info.plist`
6. Configure FlutterFire if desired:

```bash
dart pub global activate flutterfire_cli
flutterfire configure
```

Firestore collections used by the app:

- `users`
- `areas`
- `accessLogs`
- `notifications`

## MobileFaceNet Model

Place your TensorFlow Lite model here:

```text
assets/models/mobilefacenet.tflite
```

The implementation expects:

- Input shape: `[1, 112, 112, 3]`
- Normalization: `(pixel - 127.5) / 128.0`
- Output shape: `[1, 192]`

If your model has different input/output shapes, update `lib/services/face_recognition_service.dart`.

## Permissions

Android permissions are already added in `android/app/src/main/AndroidManifest.xml`:

- `CAMERA`
- `INTERNET`

iOS camera permission is added in `ios/Runner/Info.plist`.

## Run

```bash
flutter pub get
flutter run
```

Use a physical device for camera, ML Kit, and TFLite testing.

## Offline Recognition And Sync

When a face is registered, the averaged 192D embedding is saved both to Firestore and the local SQLite `faces` table. Face login compares a live embedding against local embeddings using Euclidean distance, so recognition works offline. Access logs are written to Firestore when online; if Firestore is unavailable, logs are queued in SQLite and synced from the dashboard startup path.
