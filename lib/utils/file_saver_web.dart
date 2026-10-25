// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

void downloadFileFromUrl(String url, String fileName) {
  final anchor = html.AnchorElement(href: url)
    ..target = '_blank'
    ..download = fileName;
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
}
