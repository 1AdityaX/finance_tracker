import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../data/cloud.dart';
import '../data/store.dart';
import 'firestore_cloud.dart';

enum SyncState { signedOut, syncing, synced, failed }

/// Who is signed in for cloud backup, and how the backup is going.
abstract class Account extends ChangeNotifier {
  SyncState get state;

  /// The signed-in Google account, or null when signed out.
  String? get email;

  /// Signs in with Google. Completes with false if the user backed out, and
  /// throws a [SignInFailure] saying what went wrong otherwise.
  Future<bool> signIn();

  /// Stops backing up. Every record stays on the phone.
  Future<void> signOut();

  /// Syncs again after it failed.
  Future<void> retry();
}

class SignInFailure implements Exception {
  const SignInFailure(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Google sign-in with Firebase, keeping the ledger in step with Firestore.
class GoogleAccount extends Account {
  GoogleAccount._(this._store, this._storage, this._auth) {
    _storage
      ..onChanged = _store.reload
      ..onError = (error) {
        debugPrint('Cloud backup failed: $error');
        _set(SyncState.failed);
      };
    _auth.authStateChanges().listen(_changed);
  }

  /// Sets up Firebase and returns the account, or null when this build has
  /// no Firebase project (no `android/app/google-services.json`). Then the
  /// app keeps every record on the phone only, as it always did.
  static Future<GoogleAccount?> start(
    Store store,
    SyncedStorage storage,
  ) async {
    try {
      await Firebase.initializeApp();
      await GoogleSignIn.instance.initialize();
    } on Object catch (error) {
      debugPrint('Cloud backup is off: $error');
      return null;
    }
    return GoogleAccount._(store, storage, FirebaseAuth.instance);
  }

  final Store _store;
  final SyncedStorage _storage;
  final FirebaseAuth _auth;

  @override
  SyncState get state => _state;
  SyncState _state = SyncState.signedOut;

  @override
  String? get email => _auth.currentUser?.email;

  void _set(SyncState state) {
    _state = state;
    notifyListeners();
  }

  Future<void> _changed(User? user) async {
    if (user == null) {
      _storage.disconnect();
      _set(SyncState.signedOut);
    } else {
      await _connect(user);
    }
  }

  Future<void> _connect(User user) async {
    _set(SyncState.syncing);
    try {
      await _storage.connect(FirestoreCloud(user.uid), user.uid);
      _set(SyncState.synced);
    } on Object catch (error) {
      debugPrint('Cloud backup failed: $error');
      _set(SyncState.failed);
    }
  }

  @override
  Future<bool> signIn() async {
    try {
      final google = await GoogleSignIn.instance.authenticate();
      await _auth.signInWithCredential(
        GoogleAuthProvider.credential(idToken: google.authentication.idToken),
      );
      return true;
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) return false;
      throw SignInFailure(switch (error.code) {
        GoogleSignInExceptionCode.clientConfigurationError ||
        GoogleSignInExceptionCode.providerConfigurationError =>
          'Google sign-in isn’t set up for this build. Check its SHA-1 '
              'fingerprint in Firebase.',
        _ => 'Couldn’t sign in. Check your connection and try again.',
      });
    } on FirebaseAuthException catch (error) {
      throw SignInFailure(error.message ?? 'Couldn’t sign in.');
    }
  }

  @override
  Future<void> signOut() async {
    _storage.disconnect();
    await GoogleSignIn.instance.signOut();
    await _auth.signOut();
  }

  @override
  Future<void> retry() async {
    if (_auth.currentUser case final user?) await _connect(user);
  }
}
