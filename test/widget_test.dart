import 'package:flutter_test/flutter_test.dart';
import 'package:acode/app.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ACodeApp());
    expect(find.text('ACode'), findsOneWidget);
  });
}
