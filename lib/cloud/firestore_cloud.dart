import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/cloud.dart';

/// The ledger in Firestore, under `users/{uid}`: a document per record in a
/// collection per kind (`users/{uid}/expenses/{id}` and so on), and the
/// ledger version on `users/{uid}` itself.
///
/// Each record is stored as its JSON text, so it reads back exactly as it was
/// saved. Firestore keeps writes made offline and sends them when it can.
class FirestoreCloud implements Cloud {
  FirestoreCloud(this.uid);
  final String uid;
  final _db = FirebaseFirestore.instance;

  /// Firestore allows at most 500 writes in one batch.
  static const _batchSize = 450;

  DocumentReference<Map<String, dynamic>> get _user =>
      _db.collection('users').doc(uid);

  @override
  Future<Map<String, Object?>?> read() async {
    final meta = await _user.get();
    if (!meta.exists) return null;
    final json = <String, Object?>{'version': meta.data()!['version']};
    for (final kind in recordKinds) {
      final records = [
        for (final doc in (await _user.collection(kind).get()).docs)
          (jsonDecode(doc.data()['json'] as String) as Map)
              .cast<String, Object?>(),
      ];
      // Firestore returns documents by id; the app lists records oldest
      // first, General bill first.
      if (_dateOf[kind] case final field?) {
        records.sort(
          (a, b) => (a[field]! as String).compareTo(b[field]! as String),
        );
      }
      json[kind] = records;
    }
    return json;
  }

  static const _dateOf = {
    'bills': 'created',
    'expenses': 'date',
    'payments': 'date',
    'incomes': 'date',
  };

  @override
  Future<void> apply(int version, List<RecordChange> changes) async {
    // At least one batch, so the version is noted even with no changes.
    for (
      var start = 0;
      start == 0 || start < changes.length;
      start += _batchSize
    ) {
      final batch = _db.batch()
        ..set(_user, {
          'version': version,
          'updated': FieldValue.serverTimestamp(),
        });
      for (final change in changes.skip(start).take(_batchSize)) {
        final doc = _user.collection(change.kind).doc(_docId(change.id));
        switch (change.record) {
          case null:
            batch.delete(doc);
          case final record:
            batch.set(doc, {'json': jsonEncode(record)});
        }
      }
      await batch.commit();
    }
  }

  /// Record ids are app-made, but a document id can never contain "/".
  static String _docId(String id) => Uri.encodeComponent(id);
}
