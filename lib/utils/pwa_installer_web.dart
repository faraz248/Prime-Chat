// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:js' as js;

Future<bool> promptInstall() async {
  try {
    final result = js.context.callMethod('triggerPwaInstall');
    if (result != null) {
      return true;
    }
  } catch (e) {
    // ignore
  }
  return false;
}

bool isInstallAvailable() {
  try {
    return js.context.callMethod('hasInstallPrompt') == true;
  } catch (_) {
    return false;
  }
}
