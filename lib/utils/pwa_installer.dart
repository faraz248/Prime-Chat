import 'pwa_installer_stub.dart'
    if (dart.library.html) 'pwa_installer_web.dart' as impl;

class PwaInstaller {
  static Future<bool> promptInstall() async {
    return await impl.promptInstall();
  }

  static bool isInstallAvailable() {
    return impl.isInstallAvailable();
  }
}
