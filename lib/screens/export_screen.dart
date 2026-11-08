import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/export.dart';
import '../data/store.dart';
import 'widgets.dart';

/// Opens the phone's "save as" picker and writes [text] to the chosen file.
/// Completes with true once saved, false if nothing was chosen. See
/// `MainActivity.kt`.
Future<bool> saveTextFile(String name, String mime, String text) async =>
    await const MethodChannel('between/files').invokeMethod<bool>('saveText', {
      'name': name,
      'mime': mime,
      'text': text,
    }) ??
    false;

/// Saves every record to a file: JSON that `/import` reads back, or CSV for
/// a spreadsheet.
class ExportScreen extends StatefulWidget {
  const ExportScreen({
    super.key,
    required this.store,
    this.save = saveTextFile,
  });
  final Store store;
  final Future<bool> Function(String name, String mime, String text) save;

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  bool _busy = false;

  Future<void> _export({required bool csv}) async {
    final messenger = ScaffoldMessenger.of(context);
    final ledger = widget.store.ledger;
    final name = exportFileName(DateTime.now(), csv ? 'csv' : 'json');
    setState(() => _busy = true);
    String message;
    try {
      final saved = await widget.save(
        name,
        csv ? 'text/csv' : 'application/json',
        csv ? exportCsv(ledger) : exportJson(ledger),
      );
      if (!saved) return;
      message = 'Saved $name';
    } on Object {
      message = 'Couldn’t save the file.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ledger = widget.store.ledger;
    final empty =
        ledger.expenses.isEmpty &&
        ledger.payments.isEmpty &&
        ledger.incomes.isEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('Export')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: Text(
              'Save all your expenses, payments and money in to a file. '
              'Nothing on this phone changes.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (empty) const EmptyNote('There are no records to export yet.'),
          ListTile(
            leading: const IconBadge(Icons.table_chart_outlined),
            title: const Text('Spreadsheet (CSV)'),
            subtitle: const Text(
              'One row per record, for Excel or Google Sheets.',
            ),
            enabled: !_busy,
            onTap: () => _export(csv: true),
          ),
          ListTile(
            leading: const IconBadge(Icons.data_object),
            title: const Text('Between file (JSON)'),
            subtitle: const Text(
              'Everything, including friends, groups and categories. '
              'Bring it back with /import.',
            ),
            enabled: !_busy,
            onTap: () => _export(csv: false),
          ),
        ],
      ),
    );
  }
}
