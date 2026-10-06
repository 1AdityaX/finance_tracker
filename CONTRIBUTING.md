# Contributing

## 1. Run the app

You need:

- Flutter 3.44, stable channel (Dart 3.12). Check with `flutter doctor`.
- Android Studio (Android SDK, emulator, Java) or a phone with USB debugging. For iOS, Xcode on a Mac.

```sh
git clone https://github.com/1AdityaX/finance_tracker.git
cd finance_tracker
flutter pub get
flutter run
```

Without a Firebase config, records stay on the device and the "Back up to Google" row is hidden. That's fine for most changes.

## 2. Check your work

Before every commit:

```sh
dart format lib test
flutter analyze
flutter test
```

Tests must pass and the analyzer must be clean. After changing a flow, also run the manual device checks in README.md.

## 3. Optional: cloud backup

Backup uses Firebase Authentication (Google sign-in) and Cloud Firestore. Use your own Firebase project; its config file is gitignored.

### Install the tools

```sh
npm install -g firebase-tools     # or: curl -sL https://firebase.tools | bash
firebase login
```

### Create the project

1. At https://console.firebase.google.com, choose **Create a project** and turn Google Analytics off.
2. Choose the **Android** icon and register the package name `com.example.finance_tracker`, as in `android/app/build.gradle.kts`.
3. Download **google-services.json** to `android/app/google-services.json`. Skip the console's SDK steps; they're already done.

Don't run `flutterfire configure`; the app reads `google-services.json` directly. If you ran it, delete `lib/firebase_options.dart` and `firebase.json`, and run `git checkout android/` to undo its Gradle edits.

### Add signing fingerprints

Google sign-in only works for builds signed with a key Firebase knows.

```sh
# Debug builds (flutter run):
keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android
# Release builds (your key from section 4):
keytool -list -v -keystore ~/keys/between-release.jks -alias upload
```

In **Project settings → Your apps → Add fingerprint**, add the **SHA-1** and **SHA-256** of each. Then download `google-services.json` again (it now includes the sign-in client) and replace the old one.

### Enable sign-in and the database

1. **Authentication → Get started → Sign-in method → Google → Enable**, pick a support email, save.
2. **Firestore Database → Create database**. Pick a nearby location, e.g. `asia-south1 (Mumbai)`; it can't be changed later. Start in **production mode**.
3. In Firestore's **Rules** tab, publish:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{uid}/{document=**} {
      allow read, write: if request.auth != null && request.auth.uid == uid;
    }
  }
}
```

### Try it

`flutter run`, tap **Back up to Google** on home, and sign in. Records appear under `users/{your uid}`, one document per record. Reinstall and sign in again to check they come back.

If sign-in says it isn't set up for this build, either the signing key's fingerprint is missing from Firebase or `google-services.json` predates it. Fix both and rebuild.

## 4. Optional: sign release builds

Android only installs an update signed with the same key, and switching keys means uninstalling, which erases records. Make one key and keep it.

```sh
mkdir -p ~/keys
keytool -genkey -v -keystore ~/keys/between-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Store the password in a password manager and back up the `.jks` file. Lose either and you can't update the installed app.

Create `android/key.properties` (gitignored; never commit it or the `.jks`):

```properties
storePassword=<the password you typed>
keyPassword=<the same password>
keyAlias=upload
storeFile=/Users/you/keys/between-release.jks
```

Build:

```sh
flutter build apk --release --split-per-abi
# build/app/outputs/flutter-apk/app-arm64-v8a-release.apk fits most phones
```

Without `key.properties`, release builds use the debug key.

## 5. Making a change

- README.md describes how flows, questions and the ledger fit together.
- Keep changes small, match the surrounding style, and prefer clear names to comments. Comments explain why.
- Money is integer paise and splits must sum exactly. See "Money rules" in README.md.
- Never reset saved data. If the ledger JSON changes, bump `Ledger.version` and teach `decodeLedger` the old format, with a test.
- Test what you change: unit tests for data and flows in `test/`, widget tests in `test/app_test.dart`.
- UI: money uses tabular figures (`tabular` in `theme.dart`); balance colours come from `forSign`, and what you owe is amber, never error red (red is for validation errors); pages use a 20px side gutter.
- Commits: one logical change each, a short imperative subject ("Let one payment pay toward several expenses"), and a body saying what changed and why.

### Pull requests

- [ ] `dart format`, `flutter analyze` and `flutter test` are clean.
- [ ] New behaviour has tests, and README.md reflects behaviour changes.
- [ ] Tried on a device or emulator, including at a large text size.
- [ ] No secrets committed: `key.properties`, `*.jks` and `google-services.json` stay local.
