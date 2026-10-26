import 'session_manager_stub.dart'
    if (dart.library.html) 'session_manager_web.dart' as impl;

class SessionManager {
  static String get currentSessionId => impl.getSavedSessionId();
  static void setSessionId(String id) => impl.saveSessionId(id);
  static String newSessionId() => impl.generateNewSessionId();
}
