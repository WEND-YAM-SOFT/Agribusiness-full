import 'package:flutter_test/flutter_test.dart';

import 'package:agribusiness/main.dart';

void main() {
  testWidgets('app shell renders', (WidgetTester tester) async {
    await tester.pumpWidget(const AgriBusiness());
    await tester.pump();

    expect(find.text('AgriBusiness'), findsNothing);
  });
}
