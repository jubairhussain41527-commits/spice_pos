# SpicePOS — Restaurant Billing & Thermal Printer App

## Quick Setup
1. Run `flutter create .` inside this folder (if platform folders like `android/build.gradle` are needed).
2. Ensure `android/app/src/main/AndroidManifest.xml` has the Bluetooth permissions included in this package.
3. Install dependencies:
   ```bash
   flutter pub get
   ```
4. Connect a physical Android phone via USB and run:
   ```bash
   flutter run
   ```
5. Build release APK:
   ```bash
   flutter build apk --release
   ```
