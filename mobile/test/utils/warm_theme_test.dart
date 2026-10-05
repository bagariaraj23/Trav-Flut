import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/src/google_fonts_base.dart';
import 'package:tripthread/utils/app_layout.dart';
import 'package:tripthread/utils/app_theme.dart';

/// Theme construction asks google_fonts to download Playfair and DM Sans.
/// The widget test binding blocks that HTTP call, and the package reports the
/// failure on an unawaited future. Keep the color assertions and let that
/// future finish inside a zone that records the font error.
Future<T> withThemeFonts<T>(Future<T> Function() body) {
  return runZonedGuarded(() async {
    final result = await body();
    final pending = List<Future<void>>.from(pendingFontFutures);
    await Future.wait(
      pending.map((future) => future.catchError((Object _) {})),
    ).timeout(const Duration(seconds: 2), onTimeout: () => <void>[]);
    return result;
  }, (Object _, StackTrace __) {})!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // google_fonts looks for a cached file before HTTP. The test binding never
  // answers path_provider, which leaves that lookup pending.
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler(
    'dev.flutter.pigeon.path_provider_foundation.PathProviderApi.getDirectoryPath',
    (ByteData? message) async => null,
  );

  test('light theme uses cream surfaces and a terracotta accent', () {
    return withThemeFonts(() async {
      final theme = AppTheme.lightTheme;
      expect(theme.scaffoldBackgroundColor, AppTheme.cream);
      expect(theme.colorScheme.secondary, AppTheme.accent);
      expect(theme.colorScheme.onSecondary, Colors.white);
      expect(theme.appBarTheme.backgroundColor, AppTheme.cream);
    });
  });

  test('dark theme keeps the warm accent on buttons', () {
    return withThemeFonts(() async {
      final theme = AppTheme.darkTheme;
      expect(theme.scaffoldBackgroundColor, AppTheme.darkBackground);
      expect(theme.colorScheme.secondary, AppTheme.accentDark);
    });
  });

  testWidgets('auth spacing tightens on a short phone', (tester) async {
    late AuthSpacing shortPhone;
    late AuthSpacing tallPhone;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(390, 680)),
          child: Builder(
            builder: (context) {
              shortPhone = AppLayout.authSpacing(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(390, 900)),
          child: Builder(
            builder: (context) {
              tallPhone = AppLayout.authSpacing(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(shortPhone.top, lessThan(tallPhone.top));
    expect(shortPhone.logo, lessThan(tallPhone.logo));
    expect(shortPhone.pagePadding, 16);
    expect(tallPhone.pagePadding, 24);
  });

  testWidgets('reading column caps width on a wide window', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(1200, 800)),
          child: Builder(
            builder: (context) {
              return AppLayout.reading(
                context: context,
                child: const SizedBox(key: Key('body'), width: 2000, height: 20),
              );
            },
          ),
        ),
      ),
    );

    final boxes = tester.renderObjectList<RenderConstrainedBox>(
      find.byType(ConstrainedBox),
    );
    expect(
      boxes.any(
        (box) => box.additionalConstraints.maxWidth == AppLayout.readingMaxWidth,
      ),
      isTrue,
    );
  });
}
