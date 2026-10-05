# Contributing to Between

Thanks for helping. This guide gets the app running on your computer, then covers the optional parts: cloud backup with your own Firebase project, and signing release builds. It ends with how changes are made and checked.

## 1. Run the app

You need:

- **Flutter 3.44** on the stable channel (Dart 3.12). Check with `flutter doctor`.
- **Android Studio**, which brings the Android SDK, an emulator and Java, or a phone with USB debugging on. For iOS, Xcode on a Mac.

```sh
git clone https://github.com/1AdityaX/finance_tracker.git
cd finance_tracker
flutter pub get
flutter run
```

That's enough for almost every change. Without a Firebase config the app keeps records on the device only, and the "Back up to Google" row doesn't appear.

## 2. Check your work

Run these before every commit. The strict lint rules live in `analysis_options.yaml`.

```sh
dart format lib test
flutter analyze
flutter test
```

All tests must pass and the analyzer must report no issues. Widget tests drive a simulated keyboard, so after changing a flow also try it on a real device. README.md lists the manual checks.

## 3. Optional: cloud backup with your own Firebase project

Backup uses Firebase Authentication (Google sign-in) and Cloud Firestore. Each developer uses their own Firebase project, and its config file is gitignored.

### Install the tools

```sh
npm install -g firebase-tools     # or: curl -sL https://firebase.tools | bash
firebase login
```

### Create the project

1. Open https://console.firebase.google.com, choose **Create a project**, and turn Google Analytics off.
2. Choose the **Android** icon and register the app with the package name `com.example.finance_tracker`, exactly as in `android/app/build.gradle.kts`.
3. Download **google-services.json** and put it at `android/app/google-services.json`. Skip the console's SDK steps; the project already has them.

You don't need `flutterfire configure`. The app reads `google-services.json` directly. If you ran it anyway, delete `lib/firebase_options.dart` and `firebase.json`, and run `git checkout android/` to undo its Gradle edits.

### Add your signing fingerprints

Google sign-in only works for builds whose signing key Firebase knows. Get the fingerprints:

```sh
# Debug builds (flutter run):
keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android
# Release builds (your key from section 4):
keytool -list -v -keystore ~/keys/between-release.jks -alias upload
```

In the console, go to **Project settings → Your apps → Add fingerprint** and add the **SHA-1** and **SHA-256** of each. Then download `google-services.json` again, so it includes the sign-in client, and replace the old one.

### Turn on sign-in and the database

1. **Authentication → Get started → Sign-in method → Google → Enable**, pick a support email, and save.
2. **Firestore Database → Create database**. Choose a location near you, such as `asia-south1 (Mumbai)`; it can't be changed later. Start in **production mode**.
3. In Firestore's **Rules** tab, publish these rules, so each person can reach only their own records:

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

Run `flutter run`, tap **Back up to Google** on home, and sign in. Your records appear in Firestore under `users/{your uid}`, one document per record. Uninstall, reinstall and sign in again, and they come back.

If sign-in says it isn't set up for this build, the fingerprint of the key that signed the build is missing from Firebase, or `google-services.json` is older than the fingerprints. Fix both, then rebuild.

## 4. Optional: sign release builds

Android only installs an update over an app signed with the same key. A different key means uninstalling, which erases the app's records. Make one key and keep using it.

```sh
mkdir -p ~/keys
keytool -genkey -v -keystore ~/keys/between-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

It asks for a password; save it in your password manager, and back up the `.jks` file somewhere safe. If you lose either, you can never update the installed app again.

Create `android/key.properties`. It's gitignored; never commit it or the `.jks`:

```properties
storePassword=<the password you typed>
keyPassword=<the same password>
keyAlias=upload
storeFile=/Users/you/keys/between-release.jks
```

Then build:

```sh
flutter build apk --release --split-per-abi
# build/app/outputs/flutter-apk/app-arm64-v8a-release.apk fits most phones
```

Without `key.properties`, release builds fall back to the debug key, so `flutter run --release` still works.

## 5. Making a change

- **Read README.md first.** It explains how flows, questions and the ledger fit together, and where each piece lives.
- **Keep it small and plain.** Add only the code a change needs, match the surrounding style, and prefer clear names to comments. When a comment is needed, explain why.
- **Money is integer paise.** Splits must add up exactly. See "Money rules" in README.md.
- **Never reset saved data.** If you change the ledger's JSON, bump `Ledger.version` and teach `decodeLedger` to read the old format, with a test.
- **Test what you change.** Data and flows have unit tests in `test/`; screens have widget tests in `test/app_test.dart`.
- **UI follows DESIGN.md**, the colours, type, spacing and components the app uses, and **PRODUCT.md** for who it's for.
- **Commits:** one logical change per commit, with a short imperative subject ("Let one payment pay toward several expenses") and a body saying what changed and why.

### Pull requests

Before opening one, check that:

- [ ] `dart format`, `flutter analyze` and `flutter test` are clean.
- [ ] New behaviour has tests, and README.md is updated where behaviour changed.
- [ ] You tried the change on a device or emulator, including at a large text size.
- [ ] No secrets are committed: `key.properties`, `*.jks` and `google-services.json` stay local.
