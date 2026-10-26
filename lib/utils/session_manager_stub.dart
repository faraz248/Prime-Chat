import 'dart:math';

String? _memorySessionId;

String getSavedSessionId() {
  if (_memorySessionId == null) {
    _memorySessionId = generateNewSessionId();
  }
  return _memorySessionId!;
}

void saveSessionId(String id) {
  _memorySessionId = id;
}

String generateNewSessionId() {
  final now = DateTime.now().millisecondsSinceEpoch;
  final rand = Random().nextInt(999999);
  final id = 'sess_${now}_$rand';
  _memorySessionId = id;
  return id;
}
