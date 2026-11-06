import 'package:flutter_timezone/flutter_timezone.dart';

Future<String?> deviceTimezoneIdentifier() async {
  final name = (await FlutterTimezone.getLocalTimezone()).identifier;
  if (name.isEmpty) return null;
  return name;
}
