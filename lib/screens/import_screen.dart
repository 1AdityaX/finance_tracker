import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/import.dart';
import '../data/store.dart';
import '../theme.dart';
import 'widgets.dart';

/// Opens the phone's file picker. Completes with the chosen file's text, or
/// null if nothing was picked. See `MainActivity.kt`.
Future<String?> pickTextFile() =>
    const MethodChannel('between/files').invokeMethod<String>('openText');

/// Adds records from a file, after showing what it would add.
class ImportScreen extends StatefulWidget {
  const ImportScreen({
    super.key,
    required this.store,
    this.pick = pickTextFile,
  });
  final Store store;
  final Future<String?> Function() pick;

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  ImportPreview? _preview;

  /// The chosen file's text, read again on saving.
  String? _source;
  String? _error;
  bool _busy = false;

  Store get store => widget.store;

  Future<void> _choose() async {
    setState(() => _busy = true);
    try {
      final source = await widget.pick();
      if (!mounted || source == null) return;
      final preview = previewImport(store.ledger, source);
      setState(() {
        _preview = preview;
        _source = source;
        _error = null;
      });
    } on ImportError catch (error) {
      setState(() {
        _preview = null;
        _error = error.message;
      });
    } on Object {
      setState(() {
        _preview = null;
        _error = 'Couldn’t read that file.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final preview = _preview;
    return Scaffold(
      appBar: AppBar(title: const Text('Import')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Text(
              'Add expenses, payments and money in from a Between import '
              'file. Nothing you already have is changed, and importing the '
              'same file again adds nothing new.',
              style: muted,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _choose,
              icon: const Icon(Icons.file_open_outlined),
              label: Text(preview == null ? 'Choose file' : 'Choose another'),
            ),
          ),
          if (_error case final error?)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Text(
                error,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.forSign(-1),
                ),
              ),
            ),
          if (preview != null) ..._summary(context, preview),
        ],
      ),
    );
  }

  List<Widget> _summary(BuildContext context, ImportPreview preview) {
    if (preview.isEmpty) {
      return [
        const SectionHeader('Nothing new'),
        EmptyNote(
          'Everything in this file is already in your records'
          '${preview.skipped > 0 ? ' (${preview.skipped} items)' : ''}.',
        ),
      ];
    }
    final range = switch ((preview.from, preview.to)) {
      (final from?, final to?) => '${shortDate(from)} to ${shortDate(to)}',
      _ => null,
    };
    return [
      const SectionHeader('This file adds'),
      ListTile(
        leading: const IconBadge(Icons.receipt_long_outlined),
        title: Text(_count(preview)),
        subtitle: range == null ? null : Text(range),
      ),
      if (preview.newFriends.isNotEmpty)
        _names(
          Icons.person_add_alt_1_outlined,
          'New friends',
          preview.newFriends,
        ),
      if (preview.newCategories.isNotEmpty)
        _names(Icons.sell_outlined, 'New categories', preview.newCategories),
      if (preview.newBills.isNotEmpty)
        _names(Icons.folder_open_outlined, 'New groups', preview.newBills),
      if (preview.skipped > 0)
        ListTile(
          leading: const IconBadge(Icons.done_all),
          title: Text('${preview.skipped} already in your records, skipped'),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        child: FilledButton(
          onPressed: _busy ? null : _save,
          child: const Text('Add to my records'),
        ),
      ),
    ];
  }

  Widget _names(IconData icon, String title, List<String> names) => ListTile(
    leading: IconBadge(icon),
    title: Text('$title (${names.length})'),
    subtitle: Text(names.join(', ')),
  );

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    // Added to the ledger as it is now, which a sync may have changed since
    // the preview.
    final preview = previewImport(store.ledger, _source!);
    final message = 'Imported ${_count(preview)}';
    await store.save(preview.ledger, message);
    navigator.pop();
    showUndo(messenger, store, message);
  }
}

/// "132 expenses, 36 payments and 9 money in".
String _count(ImportPreview preview) {
  String plural(int n, String one, String many) =>
      n == 1 ? '1 $one' : '$n $many';
  final parts = [
    if (preview.expenses > 0) plural(preview.expenses, 'expense', 'expenses'),
    if (preview.payments > 0) plural(preview.payments, 'payment', 'payments'),
    if (preview.incomes > 0) '${preview.incomes} money in',
  ];
  return switch (parts) {
    [final only] => only,
    [...final rest, final last] => '${rest.join(', ')} and $last',
    _ => 'nothing',
  };
}
