import 'url_helper_stub.dart'
    if (dart.library.html) 'url_helper_web.dart';

void openUrl(String url) {
  openBrowserUrl(url);
}
