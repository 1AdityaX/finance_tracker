import 'package:flutter/material.dart';

import '../cloud/account.dart';
import '../theme.dart';
import 'widgets.dart';

/// Whether records are backed up to Google, as a row that signs in, says
/// who is signed in, or tries again after a failure.
class BackupTile extends StatelessWidget {
  const BackupTile({super.key, required this.account});
  final Account account;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: account,
    builder: (context, _) {
      final scheme = Theme.of(context).colorScheme;
      final email = account.email ?? 'your Google account';
      return switch (account.state) {
        SyncState.signedOut => ListTile(
          leading: const IconBadge(Icons.cloud_off_outlined),
          title: const Text('Back up to Google'),
          subtitle: const Text(
            'Sign in so your records come back after a reinstall or on a '
            'new phone.',
          ),
          onTap: () => signInWithGoogle(context, account),
        ),
        SyncState.syncing => ListTile(
          leading: const IconBadge(Icons.cloud_sync_outlined),
          title: const Text('Backing up…'),
          subtitle: Text(email),
        ),
        SyncState.synced => ListTile(
          leading: const IconBadge(Icons.cloud_done_outlined),
          title: const Text('Backed up to Google'),
          subtitle: Text(email),
          onTap: () => _showAccount(context),
        ),
        SyncState.failed => ListTile(
          leading: const IconBadge(Icons.cloud_off_outlined),
          title: const Text('Couldn’t back up'),
          subtitle: Text(
            'Your records are safe on this phone. Tap to try again.',
            style: TextStyle(color: scheme.forSign(-1)),
          ),
          onTap: account.retry,
        ),
      };
    },
  );

  Future<void> _showAccount(BuildContext context) async {
    final signOut = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Backed up to Google'),
        content: Text(
          'Signed in as ${account.email}. Every change is copied to your '
          'account, and signing in on a new install brings it all back.\n\n'
          'If you sign out, your records stay on this phone, but new '
          'changes aren’t backed up.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign out'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    if (signOut == true) await account.signOut();
  }
}

/// Signs in with Google, saying so in a snackbar if it fails.
Future<void> signInWithGoogle(BuildContext context, Account account) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await account.signIn();
  } on SignInFailure catch (failure) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(failure.message)));
  }
}
