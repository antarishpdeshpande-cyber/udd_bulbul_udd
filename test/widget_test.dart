import 'package:flutter_test/flutter_test.dart';
import 'package:udd_bulbul_udd/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const UddBulbulUddApp());

    // Verify that our app renders the menu.
    expect(find.text('Udd Bulbul Udd'), findsOneWidget);
    expect(find.text('Tap to Fly!'), findsOneWidget);
  });
}
