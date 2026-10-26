// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:math';

String getSavedSessionId() {
  try {
    final saved = html.window.localStorage['nexus_session_id'];
    if (saved != null && saved.isNotEmpty) {
      return saved;
    }
  } catch (_) {}
  return generateNewSessionId();
}

void saveSessionId(String id) {
  try {
    html.window.localStorage['nexus_session_id'] = id;
  } catch (_) {}
}

String generateNewSessionId() {
  final now = DateTime.now().millisecondsSinceEpoch;
  final rand = Random().nextInt(999999);
  final id = 'sess_${now}_$rand';
  try {
    html.window.localStorage['nexus_session_id'] = id;
  } catch (_) {}
  return id;
}
