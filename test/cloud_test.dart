import 'dart:async';
import 'dart:convert';

import 'package:finance_tracker/data/cloud.dart';
import 'package:finance_tracker/data/ledger.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// A cloud kept in memory, record by record, as Firestore keeps it.
class FakeCloud implements Cloud {
  final records = <String, Map<String, Map<String, Object?>>>{};
  int? version;
  int applied = 0;

  /// When set, [apply] fails with it.
  Object? failWith;

  /// When set, [apply] waits for it, as Firestore does while offline.
  Completer<void>? holdApply;

  @override
  Future<Map<String, Object?>?> read() async => version == null
      ? null
      : {
          'version': version,
          for (final kind in recordKinds) kind: [...?records[kind]?.values],
        };

  @override
  Future<void> apply(int version, List<RecordChange> changes) async {
    await holdApply?.future;
    if (failWith case final error?) throw error;
    applied++;
    this.version = version;
    for (final change in changes) {
      final kind = records.putIfAbsent(change.kind, () => {});
      change.record == null
          ? kind.remove(change.id)
          : kind[change.id] = change.record!;
    }
  }

  Set<String> ids(String kind) => {...?records[kind]?.keys};
}

String json(Ledger ledger) => jsonEncode(ledger.toJson());

Ledger saved(MemoryStorage storage) =>
    Ledger.fromJson((jsonDecode(storage.json!) as Map).cast<String, Object?>());

/// Lets queued cloud writes and base updates finish.
Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  final dinner = expense();
  final cab = expense(id: 'e2', name: 'Cab', amount: 40000);

  group('changesBetween', () {
    test('sends everything to an empty cloud', () {
      final changes = changesBetween(null, ledgerWith().toJson().cast());
      expect(changes.map((c) => '${c.kind}/${c.id}'), [
        'friends/rahul',
        'friends/priya',
        'bills/general',
        'bills/goa',
        'categories/travel',
        'categories/rent',
      ]);
    });

    test('sends only what changed, and deletions', () {
      final before = normalLedger(json(ledgerWith(expenses: [dinner, cab])));
      final after = normalLedger(
        json(ledgerWith(expenses: [expense(name: 'Lunch')])),
      );
      expect(
        changesBetween(before, after).map((c) => (c.id, c.record?['name'])),
        [('e1', 'Lunch'), ('e2', null)],
      );
      expect(changesBetween(after, after), isEmpty);
    });

    test('ignores the order of keys inside a record', () {
      final a = normalLedger(json(ledgerWith(expenses: [dinner])));
      final b = normalLedger(json(ledgerWith(expenses: [dinner])));
      final reordered = (b['expenses']! as List).single as Map<String, Object?>;
      (b['expenses']! as List)[0] = {
        for (final key in reordered.keys.toList().reversed) key: reordered[key],
      };
      expect(changesBetween(a, b), isEmpty);
    });
  });

  group('mergeLedgers', () {
    Map<String, Object?> of(Ledger ledger) => normalLedger(json(ledger));
    List<String> names(Map<String, Object?> ledger) => [
      for (final e in ledger['expenses']! as List)
        (e as Map)['name']! as String,
    ];

    test('keeps both sides on a first sync', () {
      final merged = mergeLedgers(
        base: null,
        local: of(ledgerWith(expenses: [dinner])),
        remote: of(ledgerWith(expenses: [cab])),
      );
      expect(names(merged), ['Dinner', 'Cab']);
    });

    test('takes each side’s changes, deletions included', () {
      final base = of(ledgerWith(expenses: [dinner, cab]));
      // This phone renamed the dinner; the cloud deleted the cab.
      final merged = mergeLedgers(
        base: base,
        local: of(
          ledgerWith(
            expenses: [
              expense(name: 'Lunch'),
              cab,
            ],
          ),
        ),
        remote: of(ledgerWith(expenses: [dinner])),
      );
      expect(names(merged), ['Lunch']);
    });

    test('keeps this phone’s version when both sides changed a record', () {
      final merged = mergeLedgers(
        base: of(ledgerWith(expenses: [dinner])),
        local: of(ledgerWith(expenses: [expense(name: 'Lunch')])),
        remote: of(ledgerWith(expenses: [expense(name: 'Supper')])),
      );
      expect(names(merged), ['Lunch']);
    });

    test('never loses an edit to a deletion on the other side', () {
      final merged = mergeLedgers(
        base: of(ledgerWith(expenses: [dinner])),
        local: of(ledgerWith()),
        remote: of(ledgerWith(expenses: [expense(name: 'Supper')])),
      );
      expect(names(merged), ['Supper']);
    });
  });

  group('SyncedStorage', () {
    late MemoryStorage local;
    late MemoryStorage base;
    late SyncedStorage storage;
    late FakeCloud cloud;
    var changed = 0;

    setUp(() {
      local = MemoryStorage();
      base = MemoryStorage();
      storage = SyncedStorage(local: local, base: base)
        ..onChanged = () => changed++;
      cloud = FakeCloud();
      changed = 0;
    });

    test('keeps everything on the phone until connected', () async {
      await storage.read();
      await storage.write(json(ledgerWith(expenses: [dinner])));
      expect(saved(local).expenses.single.name, 'Dinner');
      expect(cloud.applied, 0);
    });

    test('uploads the phone’s records to an empty cloud', () async {
      local.json = json(ledgerWith(expenses: [dinner]));
      await storage.read();
      await storage.connect(cloud, 'aditya');
      await settle();
      expect(cloud.ids('expenses'), {'e1'});
      expect(cloud.version, Ledger.version);
      expect(changed, 0, reason: 'nothing new for the store to read');
      expect(base.json, contains('"account":"aditya"'));
    });

    test('restores the cloud’s records on a fresh install', () async {
      await cloud.apply(
        Ledger.version,
        changesBetween(
          null,
          normalLedger(json(ledgerWith(expenses: [dinner]))),
        ),
      );
      await storage.read();
      await storage.connect(cloud, 'aditya');
      expect(saved(local).expenses.single.name, 'Dinner');
      expect(saved(local).friends.map((f) => f.name), ['Rahul', 'Priya']);
      expect(changed, 1, reason: 'the store reads the restored records');
    });

    test('sends each save once connected', () async {
      local.json = json(ledgerWith(expenses: [dinner]));
      await storage.read();
      await storage.connect(cloud, 'aditya');
      await storage.write(json(ledgerWith(expenses: [dinner, cab])));
      await settle();
      expect(cloud.ids('expenses'), {'e1', 'e2'});
      await storage.write(json(ledgerWith(expenses: [cab])));
      await settle();
      expect(cloud.ids('expenses'), {'e2'});
    });

    test('a deletion on another phone carries over', () async {
      local.json = json(ledgerWith(expenses: [dinner, cab]));
      await storage.read();
      await storage.connect(cloud, 'aditya');
      await settle();
      // Another phone deletes the cab while this one is closed.
      cloud.records['expenses']!.remove('e2');

      final reopened = SyncedStorage(local: local, base: base);
      await reopened.read();
      await reopened.connect(cloud, 'aditya');
      expect(saved(local).expenses.map((e) => e.id), ['e1']);
    });

    test(
      'changes made while signed out are sent on the next sign-in',
      () async {
        local.json = json(ledgerWith(expenses: [dinner]));
        await storage.read();
        await storage.connect(cloud, 'aditya');
        await settle();
        storage.disconnect();
        await storage.write(json(ledgerWith(expenses: [dinner, cab])));
        expect(cloud.ids('expenses'), {'e1'});
        await storage.connect(cloud, 'aditya');
        await settle();
        expect(cloud.ids('expenses'), {'e1', 'e2'});
      },
    );

    test('a failed upload is sent again on the next sync', () async {
      local.json = json(ledgerWith(expenses: [dinner]));
      Object? reported;
      storage.onError = (error) => reported = error;
      await storage.read();
      await storage.connect(cloud, 'aditya');
      await settle();
      cloud.failWith = StateError('offline');
      await storage.write(json(ledgerWith(expenses: [dinner, cab])));
      await settle();
      expect(reported, isA<StateError>());
      expect(cloud.ids('expenses'), {'e1'});

      cloud.failWith = null;
      final reopened = SyncedStorage(local: local, base: base);
      await reopened.read();
      await reopened.connect(cloud, 'aditya');
      await settle();
      expect(cloud.ids('expenses'), {'e1', 'e2'});
    });

    test('an emptied cloud never deletes the phone’s records', () async {
      local.json = json(ledgerWith(expenses: [dinner]));
      await storage.read();
      await storage.connect(cloud, 'aditya');
      await settle();
      final emptied = FakeCloud();
      final reopened = SyncedStorage(local: local, base: base);
      await reopened.read();
      await reopened.connect(emptied, 'aditya');
      await settle();
      expect(saved(local).expenses, hasLength(1));
      expect(emptied.ids('expenses'), {'e1'});
    });

    test('another account starts from both sides, not the old base', () async {
      local.json = json(ledgerWith(expenses: [dinner]));
      await storage.read();
      await storage.connect(cloud, 'aditya');
      await settle();
      final other = FakeCloud()..version = Ledger.version;
      await storage.connect(other, 'someone-else');
      expect(saved(local).expenses, hasLength(1));
    });

    test('a save built before a sync keeps what the sync brought', () async {
      await cloud.apply(
        Ledger.version,
        changesBetween(null, normalLedger(json(ledgerWith(expenses: [cab])))),
      );
      local.json = json(ledgerWith());
      await storage.read(); // The store knows an empty ledger.
      await storage.connect(cloud, 'aditya'); // The cab arrives.
      // The store hasn't reloaded yet and adds the dinner to what it had.
      await storage.write(json(ledgerWith(expenses: [dinner])));
      await settle();
      expect(
        saved(local).expenses.map((e) => e.id),
        unorderedEquals(['e1', 'e2']),
      );
      expect(cloud.ids('expenses'), {'e1', 'e2'});
      expect(changed, 2, reason: 'after the sync, and after the rebased save');
    });

    test('an upload still waiting doesn’t hold up saving', () async {
      local.json = json(ledgerWith());
      await storage.read();
      cloud.holdApply = Completer();
      await storage.connect(cloud, 'aditya');
      await storage.write(json(ledgerWith(expenses: [dinner])));
      expect(saved(local).expenses, hasLength(1));
      expect(base.json, isNull, reason: 'the cloud hasn’t taken it yet');
      cloud.holdApply!.complete();
      await settle();
      expect(cloud.ids('expenses'), {'e1'});
    });
  });
}
