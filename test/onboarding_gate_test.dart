import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gournet_kiosk/app.dart';

void main() {
  testWidgets('una instalación sin API Key sólo muestra la activación', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const ProviderScope(child: GournetKioskApp()));
    await tester.pump();

    expect(find.text('Activa tu tótem'), findsOneWidget);
    expect(
      find.text('Comparte este código con soporte Gour-net.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('support-activation-code')), findsOneWidget);
    expect(find.byKey(const Key('activation-countdown')), findsOneWidget);
    expect(find.byKey(const Key('onboarding-api-key')), findsNothing);
    expect(find.byKey(const Key('standby-touch-target')), findsNothing);
    expect(find.byKey(const Key('catalog-scroll')), findsNothing);
  });
}
