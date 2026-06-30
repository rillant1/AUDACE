import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:netprobe/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('parcours point à point classement et carte', (tester) async {
    await tester.pumpWidget(const AudaceApp());
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('AUDACE'), findsOneWidget);

    await tester.tap(find.byKey(const Key('tab-ranking')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Classement national'), findsOneWidget);

    await tester.tap(find.byKey(const Key('tab-map')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const Key('coverage-heatmap')), findsOneWidget);

    await tester.tap(find.byKey(const Key('tab-home')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Prêt à mesurer'), findsOneWidget);
  });
}
