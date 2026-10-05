import 'dart:async';

import 'package:flutter/material.dart';

import 'cloud/account.dart';
import 'data/cloud.dart';
import 'data/store.dart';
import 'screens/home_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final storage = SyncedStorage(
    local: SqliteStorage(),
    base: SqliteStorage(name: 'cloud_base.db'),
  );
  final store = Store(storage);
  // Null when this build has no Firebase project: records stay on the phone.
  final account = await GoogleAccount.start(store, storage);
  unawaited(store.load());
  runApp(BetweenApp(store: store, account: account));
}

class BetweenApp extends StatelessWidget {
  const BetweenApp({super.key, required this.store, this.account});
  final Store store;

  /// Google sign-in for cloud backup, when this build has Firebase.
  final Account? account;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Between',
    debugShowCheckedModeBanner: false,
    theme: buildTheme(Brightness.light),
    darkTheme: buildTheme(Brightness.dark),
    home: ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        if (store.loading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (store.loadError != null) return _LoadError(store: store);
        return HomeScreen(store: store, account: account);
      },
    ),
  );
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.store});
  final Store store;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your records couldn’t be opened',
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text(
                'Nothing was changed or deleted. Please try again.',
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 8),
              Text(
                '${store.loadError}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: store.load,
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
