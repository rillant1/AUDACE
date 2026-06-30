import 'package:audace_art_dashboard/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpUntilFound(
    WidgetTester tester,
    Finder finder, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 100));
      if (finder.evaluate().isNotEmpty) return;
    }
  }

  Future<void> openSidebarTab(WidgetTester tester, int index) async {
    final finder = find.byKey(ValueKey('sidebar-tab-$index'));
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('main dashboard navigation and primary actions work', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    await tester.pumpWidget(const AudaceApp());
    await tester.pump(const Duration(milliseconds: 500));

    await openSidebarTab(tester, 6);
    await pumpUntilFound(tester, find.text('LISTE DES INCIDENTS'));
    expect(find.text('LISTE DES INCIDENTS'), findsOneWidget);
    await tester.tap(find.text('Acquitter').first);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Pris en charge'), findsOneWidget);

    await openSidebarTab(tester, 7);
    await pumpUntilFound(tester, find.text('PARC DES SONDES'));
    expect(find.text('PARC DES SONDES'), findsOneWidget);
    await tester.tap(find.text('Redémarrer').first);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Redémarrage demandé'), findsOneWidget);

    await openSidebarTab(tester, 8);
    await tester.tap(find.text('3. Moyens de Paiement'));
    await tester.pump(const Duration(milliseconds: 500));

    Future<void> confirmPayment({
      required String confirmationLabel,
      String? methodKey,
    }) async {
      if (methodKey != null) {
        final methodFinder = find.byKey(ValueKey(methodKey));
        await tester.ensureVisible(methodFinder);
        await tester.tap(methodFinder);
        await tester.pump(const Duration(milliseconds: 500));
      }

      await tester.tap(find.text('Payer maintenant'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        find.text(
          'Confirmer le paiement de 5 000 000 FCFA via $confirmationLabel ?',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Payer'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Paiement $confirmationLabel confirmé'), findsOneWidget);
    }

    await confirmPayment(confirmationLabel: 'Orange Money');
    await confirmPayment(
      confirmationLabel: 'MTN Mobile Money',
      methodKey: 'payment-method-mtn-mobile-money',
    );
    await confirmPayment(
      confirmationLabel: 'Carte bancaire',
      methodKey: 'payment-method-bank-card',
    );
    await confirmPayment(
      confirmationLabel: 'Virement bancaire',
      methodKey: 'payment-method-bank-transfer',
    );
  });
}
