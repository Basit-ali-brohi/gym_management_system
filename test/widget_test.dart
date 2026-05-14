import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gym_management_system/src/app.dart';
import 'package:gym_management_system/src/core/providers.dart';
import 'package:gym_management_system/src/core/token_store.dart';

void main() {
  testWidgets('Renders login when not authenticated', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStoreProvider.overrideWithValue(_FakeTokenStore()),
        ],
        child: const GymSaasApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Gym Management'), findsOneWidget);
  });
}

class _FakeTokenStore extends TokenStore {
  @override
  Future<String?> getToken() async => null;

  @override
  Future<String?> getTenantSlug() async => null;

  @override
  Future<void> clear() async {}
}
