# Getting Started & Deployment

This guide covers setting up your local Flutter development environment, configuring backend endpoints, and deploying SYNQRA to physical devices and emulators.

---

## Prerequisites

- **Flutter SDK**: `>=3.7.0` ([flutter.dev](https://flutter.dev))
- **Dart SDK**: `>=3.7.0`
- **Android Studio / Android SDK**: Platform API 34+
- **Physical Device or Emulator**: Google Pixel 8 Pro recommended
- **Java**: OpenJDK 17+

---

## 1. Clone & Resolve Dependencies

Clone the repository and install all Flutter packages:

```bash
git clone https://github.com/your-username/Flutter-Project.git
cd Flutter-Project

# Resolve Dart dependencies
flutter pub get
```

---

## 2. Configure Backend Endpoints

### Default Production Backend
By default, the application is pre-configured to communicate with the live production HTTPS service:
```
https://synqra-api.duckdns.org
```
No extra networking steps are required when using the production backend.

### Local Development Backend (FastAPI on Port 8000)
If developing against a locally running FastAPI instance, reverse-forward host port `8000` via ADB so the Android client can access `http://localhost:8000`:

```bash
# Verify connected physical device
adb devices

# Reverse port forwarding for FastAPI server
adb reverse tcp:8000 tcp:8000

# Verify endpoint accessibility
curl http://localhost:8000/documents
```

---

## 3. Running & Building

### Run in Debug Mode
Launch the application with hot-reload enabled:
```bash
flutter run
```

### Build Debug APK
Generate an unsigned debug APK for testing:
```bash
flutter build apk --debug
```
Output artifact located at:
```
build/app/outputs/flutter-apk/app-debug.apk
```

### Install Directly via ADB (Google Pixel 8 Pro)
```bash
# Install to connected device
adb install -r build/app/outputs/flutter-apk/app-debug.apk

# Force-stop and launch main activity
adb shell am force-stop com.example.my_flutter_proj_dq
adb shell am start -n com.example.my_flutter_proj_dq/.MainActivity
```

### Build Release APK
```bash
flutter build apk --release
```
Output artifact located at:
```
build/app/outputs/flutter-apk/app-release.apk
```
