import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bhai_app/features/home/presentation/home_screen.dart';

void main() {
  testWidgets('V1 Home Dashboard renders emergency elements correctly', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: HomeScreen(),
      ),
    );

    // Verify V1 title & emergency header
    expect(find.text('BHAI'), findsOneWidget);
    expect(find.text('EMERGENCY NEARBY ALERT'), findsOneWidget);

    // Verify 🚨 BHAI HELP primary action button
    expect(find.text('🚨 BHAI HELP'), findsOneWidget);
    expect(find.text('TAP IN AN EMERGENCY'), findsOneWidget);

    // Verify initial standby status
    expect(
      find.text('Standby • Ready to broadcast or detect nearby emergency alerts'),
      findsOneWidget,
    );
  });
}
