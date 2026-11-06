import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('Intl.DateTimeFormat')
extension type _JSDateTimeFormat._(JSObject _) implements JSObject {
  external factory _JSDateTimeFormat();
  external JSObject resolvedOptions();
}

/// IANA zone from the browser, for example Asia/Kolkata.
Future<String?> deviceTimezoneIdentifier() async {
  final options = _JSDateTimeFormat().resolvedOptions();
  final zone = options.getProperty<JSString>('timeZone'.toJS).toDart;
  if (zone.isEmpty) return null;
  return zone;
}
