import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netprobe/screens/home_screen.dart';
import 'package:netprobe/theme/app_theme.dart';

// Les tests widget pompent HomeScreen directement (pas via AudaceApp)
// pour éviter d'attendre les 10 secondes du splash screen.
MaterialApp _wrap(Widget child) => MaterialApp(
      theme: AudaceTheme.light,
      home: child,
    );

// Simule les dimensions d'un téléphone Android standard (ex: Pixel 6).
// flutter_map affiche un widget d'avertissement OSM dont le contenu dépasse
// dans le viewport étroit par défaut (800×600 px) — ce qui cause une
// FlutterError "RenderFlex overflowed" qui fait échouer le test.
void _setPhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 1920);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset); // Restaure les valeurs par défaut après le test
}

void main() {
  testWidgets('affiche les trois onglets principaux', (tester) async {
    _setPhoneViewport(tester);
    await tester.pumpWidget(_wrap(const HomeScreen()));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const Key('tab-home')), findsOneWidget);
    expect(find.byKey(const Key('tab-ranking')), findsOneWidget);
    expect(find.byKey(const Key('tab-map')), findsOneWidget);
    expect(find.text('Prêt à analyser'), findsOneWidget);
  });

  testWidgets('navigue vers le classement puis la carte heatmap', (
    tester,
  ) async {
    _setPhoneViewport(tester);
    await tester.pumpWidget(_wrap(const HomeScreen()));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byKey(const Key('tab-ranking')));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byKey(const Key('ranking-screen')), findsOneWidget);
    expect(find.text('Classement réseau'), findsOneWidget);

    await tester.tap(find.byKey(const Key('tab-map')));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byKey(const Key('coverage-map-screen')), findsOneWidget);
    expect(find.byKey(const Key('coverage-heatmap')), findsOneWidget);
  });
}
