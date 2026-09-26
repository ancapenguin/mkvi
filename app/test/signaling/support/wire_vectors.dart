/// Reads the shared wire contract `vectors/wire-v1.json`.
///
/// The file is parsed with `dart:convert` exactly as the TypeScript suite parses
/// it with `JSON.parse`. There is no code generator and no Dart mirror of the
/// vectors, because a mirror is exactly where the two implementations would
/// start disagreeing again.
library;

import 'dart:convert';
import 'dart:io';

/// Where the vector file lives relative to this file and to the `app` package.
const List<String> _candidatePaths = <String>[
  '../vectors/wire-v1.json',
  'vectors/wire-v1.json',
  '../../vectors/wire-v1.json',
];

String _readVectorFile() {
  final List<String> tried = <String>[];
  for (final String candidate in _candidatePaths) {
    final File file = File(candidate);
    tried.add(candidate);
    if (file.existsSync()) return file.readAsStringSync();
  }
  throw StateError('vectors/wire-v1.json not found; looked in: ${tried.join(", ")}');
}

/// One case of the shared contract.
class WireCase {
  const WireCase(this.id, this.kind, this.aciklama, this.fields);

  final String id;
  final String kind;

  /// The Turkish explanation of what this case protects against.
  final String aciklama;

  /// The whole case object, decoded.
  final Map<String, Object?> fields;

  Object? field(String name) => fields[name];

  Object? get expect => fields['expect'];
  Object? get input => fields['input'];
  Object? get value => fields['value'];
  Object? get payload => fields['payload'];
  Object? get api => fields['api'];
  Object? get endpoint => fields['endpoint'];
  Object? get expectedError => fields['expectError'];

  /// The literal frame an `incoming` case feeds to the client. Named
  /// `incomingRaw` because `fields['raw']` would collide with the case map.
  String get incomingRaw => fields['raw']! as String;

  Map<String, Object?> get params => (fields['params'] as Map<Object?, Object?>? ?? const <Object?, Object?>{})
      .cast<String, Object?>()
      .map((String key, Object? item) => MapEntry<String, Object?>(key, item));

  bool get expectedBool => expect! as bool;
  String get expectedString => expect! as String;

  /// The `expect` of an `incoming` case: which handler fired, and with what.
  IncomingExpect get incoming {
    final Map<Object?, Object?> value = expect! as Map<Object?, Object?>;
    return IncomingExpect(
      closeCode: value['closeCode'] as int?,
      signal: value['signal'] as String?,
      presence: value['presence'] as int?,
    );
  }

  /// The `expect` of a shape case: alphabet, length and sample count.
  ShapeExpect get shape {
    final Map<Object?, Object?> value = expect! as Map<Object?, Object?>;
    return ShapeExpect(
      alphabet: value['alphabet']! as String,
      length: value['length']! as int,
      uniqueSamples: value['uniqueSamples']! as int,
    );
  }

  @override
  String toString() => 'WireCase($id, $kind)';
}

/// The expected effect of feeding one raw frame to the client.
class IncomingExpect {
  const IncomingExpect({required this.closeCode, required this.signal, required this.presence});

  /// Null when the socket must stay open.
  final int? closeCode;

  /// Null when `onSignal` must not fire.
  final String? signal;

  /// Null when `onPresence` must not fire.
  final int? presence;
}

/// The expected shape of a generated identifier.
class ShapeExpect {
  const ShapeExpect({required this.alphabet, required this.length, required this.uniqueSamples});

  final String alphabet;
  final int length;
  final int uniqueSamples;
}

/// A group of related cases, kept so a failing run says which area broke.
class WireGroup {
  const WireGroup(this.id, this.aciklama, this.cases);

  final String id;
  final String aciklama;
  final List<WireCase> cases;
}

/// The parsed contract.
class WireVectors {
  const WireVectors({
    required this.schema,
    required this.version,
    required this.patterns,
    required this.connectError,
    required this.notOpenError,
    required this.forbiddenKeys,
    required this.groups,
  });

  final String schema;
  final int version;
  final Map<String, Object?> patterns;
  final String connectError;
  final String notOpenError;

  /// Keys that must never appear in a signaling payload, with the reason.
  final List<ForbiddenKey> forbiddenKeys;
  final List<WireGroup> groups;

  Iterable<WireCase> get allCases => groups.expand((WireGroup group) => group.cases);

  List<WireCase> casesOfKind(String kind) =>
      allCases.where((WireCase item) => item.kind == kind).toList(growable: false);

  WireCase caseById(String id) => allCases.firstWhere(
    (WireCase item) => item.id == id,
    orElse: () => throw StateError('vectors/wire-v1.json has no case $id'),
  );
}

/// One entry of the `forbiddenKeys` list.
class ForbiddenKey {
  const ForbiddenKey(this.key, this.aciklama);

  final String key;
  final String aciklama;
}

Map<String, Object?> _asMap(Object? value) => (value! as Map<Object?, Object?>).cast<String, Object?>();

/// Loads and parses the shared contract. Throws [StateError] with every path it
/// tried when the file is missing, so a moved file is obvious.
WireVectors loadWireVectors({String? path}) {
  final String source = path != null ? File(path).readAsStringSync() : _readVectorFile();
  final Map<String, Object?> root = _asMap(jsonDecode(source));

  if (root['schema'] != 'mkvi.wire') {
    throw StateError('unexpected vector schema: ${root['schema']}');
  }
  final Map<String, Object?> errors = _asMap(root['errors']);
  final Map<String, Object?> forbidden = _asMap(root['forbiddenKeys']);
  final List<Object?> keys = (forbidden['keys']! as List<Object?>);

  return WireVectors(
    schema: root['schema']! as String,
    version: root['version']! as int,
    patterns: _asMap(root['patterns']),
    connectError: errors['connect']! as String,
    notOpenError: errors['notOpen']! as String,
    forbiddenKeys: keys
        .map((Object? entry) => _asMap(entry))
        .map((Map<String, Object?> entry) => ForbiddenKey(entry['key']! as String, entry['aciklama']! as String))
        .toList(growable: false),
    groups: (root['groups']! as List<Object?>).map((Object? entry) {
      final Map<String, Object?> group = _asMap(entry);
      return WireGroup(
        group['id']! as String,
        group['aciklama']! as String,
        (group['cases']! as List<Object?>)
            .map((Object? item) => _asMap(item))
            .map(
              (Map<String, Object?> item) => WireCase(
                item['id']! as String,
                item['kind']! as String,
                item['aciklama']! as String,
                item,
              ),
            )
            .toList(growable: false),
      );
    }).toList(growable: false),
  );
}
