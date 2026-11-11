import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripthread/utils/error_handler.dart';
import 'package:tripthread/providers/share_provider.dart';
import 'package:tripthread/services/share_service.dart';
class MockShareService extends ShareService {
  bool shouldFail = false;
  String? failError;
  int createCallCount = 0;

  @override
  Future<ShareLinkResult> createShare(
    String entityType,
    String entityId,
  ) async {
    createCallCount++;
    if (shouldFail) {
      throw Exception(failError ?? 'Failed to create share');
    }
    await Future.delayed(const Duration(milliseconds: 100));
    return ShareLinkResult(
      webUrl: 'https://tripthread.app/share/test-token-$createCallCount',
      shareToken: 'test-token-$createCallCount',
    );
  }

  @override
  Future<SharedEntity> resolveShare(String shareToken) async {
    if (shouldFail) {
      throw Exception(failError ?? 'Failed to resolve share');
    }
    await Future.delayed(const Duration(milliseconds: 100));
    return SharedEntity(
      entityType: 'TRIP_FINAL_POST',
      entityId: 'entity1',
      entityData: {'id': 'entity1'},
      shareData: {'shareToken': shareToken},
    );
  }

  Future<void> trackShareOpen(
    String shareToken, {
    String? platform,
    String? userAgent,
  }) async {
    if (shouldFail) {
      throw Exception(failError ?? 'Failed to track share');
    }
    await Future.delayed(const Duration(milliseconds: 50));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ShareProvider provider;
  late MockShareService mockShareService;

  setUp(() {
    mockShareService = MockShareService();
    // ShareProvider requires DeepLinkService, but we can't easily mock it
    // So we'll use the real instance for testing
    provider = ShareProvider(
      shareService: mockShareService,
    );
  });

  group('ShareProvider', () {
    test('initial state - should have empty share history', () {
      expect(provider.userShares, isEmpty);
      expect(provider.error, isNull);
    });

    test('createShare - should create and cache share URL', () async {
      final entityKey = 'TRIP_FINAL_POST:entity1';

      expect(provider.isCreating(entityKey), false);

      final shareFuture = provider.createShare('TRIP_FINAL_POST', 'entity1');

      expect(provider.isCreating(entityKey), true);

      final link = await shareFuture;

      expect(link, isA<ShareLinkResult>());
      expect(link.webUrl, contains('/share/'));
      expect(link.shareToken, isNotEmpty);
      expect(provider.isCreating(entityKey), false);
      expect(provider.userShares, isNotEmpty);
    });

    test('createShare - should handle API failure', () async {
      mockShareService.shouldFail = true;
      mockShareService.failError = 'Network error';

      try {
        await provider.createShare('TRIP_FINAL_POST', 'entity1');
        fail('Should have thrown an exception');
      } catch (e) {
        expect(provider.error, isNotNull);
        expect(provider.userShares, isEmpty);
      }
    });

    test('createShare - should prevent duplicate creation', () async {
      final share1 = provider.createShare('TRIP_FINAL_POST', 'entity1');
      await expectLater(
        provider.createShare('TRIP_FINAL_POST', 'entity1'),
        throwsA(isA<AppException>()),
      );
      await share1;
      expect(mockShareService.createCallCount, 1);
    });

    test('openNativeShare - fails without platform plugin (vm test)', () async {
      final link = await provider.createShare('TRIP_FINAL_POST', 'entity1');

      await expectLater(
        provider.openNativeShare(link),
        throwsA(isA<MissingPluginException>()),
      );
    });

    test('resolveShare - should resolve share token', () async {
      final sharedEntity = await provider.resolveShare('test-token-123');

      expect(sharedEntity, isA<Map<String, dynamic>>());
      expect(sharedEntity['entityType'], 'TRIP_FINAL_POST');
      expect(sharedEntity['entityId'], 'entity1');
    });

    test('resolveShare - should handle invalid token', () async {
      mockShareService.shouldFail = true;
      mockShareService.failError = 'Share token not found';

      expect(
        () => provider.resolveShare('invalid-token'),
        throwsA(isA<Exception>()),
      );
    });

    test('clearError - should clear error state', () {
      provider.clearError();
      expect(provider.error, isNull);
    });
  });
}

