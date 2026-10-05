import 'dart:async';
import 'dart:convert';

import 'ledger.dart';
import 'store.dart';

/// The kinds of record a ledger holds, as named in its JSON.
const recordKinds = ['friends', 'bills', 'categories', 'expenses', 'payments'];

/// One record to save in the cloud, or to delete when [record] is null.
typedef RecordChange = ({String kind, String id, Map<String, Object?>? record});

/// A copy of the ledger kept somewhere else, one document per record.
abstract interface class Cloud {
  /// The whole ledger as JSON, or null when nothing was ever saved there.
  Future<Map<String, Object?>?> read();

  /// Saves and deletes records, and notes the ledger [version].
  Future<void> apply(int version, List<RecordChange> changes);
}

/// [json] parsed and upgraded to the current format, so ledgers saved by any
/// version compare record by record.
Map<String, Object?> normalLedger(String json) =>
    (jsonDecode(jsonEncode(decodeLedger(json).toJson())) as Map)
        .cast<String, Object?>();

/// What to save in the cloud to turn [before] into [after]. Everything in
/// [after] when the cloud has nothing yet.
List<RecordChange> changesBetween(
  Map<String, Object?>? before,
  Map<String, Object?> after,
) => [
  for (final kind in recordKinds)
    ...() {
      final old = _byId(before?[kind]);
      final now = _byId(after[kind]);
      return [
        for (final MapEntry(key: id, value: record) in now.entries)
          if (old[id] == null || _canon(old[id]) != _canon(record))
            (kind: kind, id: id, record: record),
        for (final id in old.keys)
          if (!now.containsKey(id)) (kind: kind, id: id, record: null),
      ];
    }(),
];

/// Combines this phone's records with the cloud's, record by record, using
/// [base], what both last agreed on. A record changed on only one side takes
/// that side's version, so additions, edits and deletions all carry over.
/// A record changed on both sides keeps this phone's version. With no base,
/// as on a first sync, both sides' records are kept.
Map<String, Object?> mergeLedgers({
  required Map<String, Object?>? base,
  required Map<String, Object?> local,
  required Map<String, Object?>? remote,
}) => {
  'version': Ledger.version,
  for (final kind in recordKinds)
    kind: () {
      final b = _byId(base?[kind]);
      final l = _byId(local[kind]);
      final r = _byId(remote?[kind]);
      // This phone's order first, then what only the cloud has.
      return [
        for (final id in {...l.keys, ...r.keys}) ?_pick(b[id], l[id], r[id]),
      ];
    }(),
};

Map<String, Object?>? _pick(
  Map<String, Object?>? base,
  Map<String, Object?>? local,
  Map<String, Object?>? remote,
) {
  final (b, l, r) = (_canon(base), _canon(local), _canon(remote));
  if (l == r || r == b) return local;
  if (l == b) return remote;
  return local ?? remote;
}

Map<String, Map<String, Object?>> _byId(Object? records) => {
  for (final record in (records as List?) ?? const [])
    (record as Map)['id']! as String: record.cast<String, Object?>(),
};

/// JSON with map keys sorted, so equal records encode the same.
String? _canon(Object? value) =>
    value == null ? null : jsonEncode(_sorted(value));

Object? _sorted(Object? value) => switch (value) {
  final Map<Object?, Object?> map => {
    for (final key in map.keys.map((k) => k! as String).toList()..sort())
      key: _sorted(map[key]),
  },
  final List<Object?> list => [for (final item in list) _sorted(item)],
  _ => value,
};

/// Keeps the ledger on the phone and, once [connect]ed, a copy in a [Cloud].
///
/// Every save goes to the phone first, then its changes go to the cloud
/// without waiting, so the app works the same offline. Connecting merges the
/// two copies record by record against what they last agreed on, which is
/// kept in [base].
class SyncedStorage implements Storage {
  SyncedStorage({required this.local, required this.base});
  final Storage local;

  /// What the cloud last held, with the account it belongs to.
  final Storage base;

  /// Called when what is saved changed without the store writing it, as
  /// after connecting, so the store can read it again.
  void Function()? onChanged;

  /// Called when the cloud couldn't take a change.
  void Function(Object error)? onError;

  Cloud? _cloud;
  String? _account;

  /// What is saved on the phone, and what the store last read or wrote.
  /// They differ when a sync changed the ledger under the store.
  String? _saved;
  String? _known;

  bool get connected => _cloud != null;

  Future<void> _lock = Future.value();

  /// Runs [action] after everything already queued, one at a time.
  Future<T> _locked<T>(Future<T> Function() action) {
    final result = _lock.then((_) => action());
    _lock = result.then((_) {}, onError: (Object _) {});
    return result;
  }

  @override
  Future<String?> read() =>
      _locked(() async => _known = _saved = await local.read());

  @override
  Future<void> write(String json) async {
    final rebased = await _locked(() async {
      final saved = _saved;
      final known = _known;
      // The store built [json] on a ledger a sync has since replaced, so
      // apply just its change on top of what is saved now.
      final next = saved != null && known != null && saved != known
          ? jsonEncode(
              mergeLedgers(
                base: normalLedger(known),
                local: normalLedger(json),
                remote: normalLedger(saved),
              ),
            )
          : json;
      await local.write(next);
      _saved = next;
      _known = json;
      _push(saved, next);
      return next != json;
    });
    if (rebased) onChanged?.call();
  }

  /// Merges the phone's records with [cloud]'s for [account] and keeps
  /// them in step from now on. Throws, changing nothing, if the cloud can't
  /// be read.
  Future<void> connect(Cloud cloud, String account) async {
    final remote = await cloud.read();
    final changed = await _locked(() async {
      final saved = _saved ?? await local.read();
      final merged = jsonEncode(
        mergeLedgers(
          // An empty cloud has nothing to take away: keep every record.
          base: remote == null ? null : await _baseFor(account),
          local: normalLedger(saved ?? jsonEncode(Ledger.empty.toJson())),
          remote: remote,
        ),
      );
      if (merged != saved) await local.write(merged);
      _saved = merged;
      _cloud = cloud;
      _account = account;
      _push(remote == null ? null : jsonEncode(remote), merged);
      return merged != _known;
    });
    if (changed) onChanged?.call();
  }

  /// Stops sending changes to the cloud. The phone keeps every record.
  void disconnect() {
    _cloud = null;
    _account = null;
  }

  Future<Map<String, Object?>?> _baseFor(String account) async {
    final saved = await base.read();
    if (saved == null) return null;
    final json = (jsonDecode(saved) as Map).cast<String, Object?>();
    if (json['account'] != account) return null;
    return normalLedger(jsonEncode(json['ledger']));
  }

  /// Sends what changed from [before] to [after]. Once the cloud has it,
  /// and nothing newer was saved meanwhile, it becomes the new base.
  void _push(String? before, String after) {
    final cloud = _cloud;
    final account = _account;
    if (cloud == null) return;
    final changes = changesBetween(
      before == null ? null : normalLedger(before),
      normalLedger(after),
    );
    Future<void> agreed() async {
      if (_saved == after && _account == account) {
        await base.write(
          jsonEncode({'account': account, 'ledger': jsonDecode(after)}),
        );
      }
    }

    final sent = changes.isEmpty && before != null
        ? agreed()
        : cloud.apply(Ledger.version, changes).then((_) => agreed());
    unawaited(sent.catchError((Object error) => onError?.call(error)));
  }
}
