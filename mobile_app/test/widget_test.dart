import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CCIS Attendance mobile tests', () {
    testWidgets('Flutter widget environment loads correctly', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Center(child: Text('CCIS Attendance'))),
        ),
      );

      await tester.pump();

      expect(find.text('CCIS Attendance'), findsOneWidget);

      expect(find.byType(MaterialApp), findsOneWidget);

      expect(find.byType(Scaffold), findsOneWidget);
    });
  });
}
