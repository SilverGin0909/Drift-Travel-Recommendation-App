import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/screens/signup.dart';

void main() {
  testWidgets('App onboarding smoke test', (WidgetTester tester) async {
    // Build the signup onboarding page directly
    await tester.pumpWidget(
      const MaterialApp(
        home: SignupPage(),
      ),
    );

    // Verify onboarding details are rendered
    expect(find.text('Create Account'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(3)); // Username, Email, and Password fields
  });
}
