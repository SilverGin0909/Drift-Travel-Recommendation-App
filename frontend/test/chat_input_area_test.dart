import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/widgets/chat_input_area.dart';

void main() {
  testWidgets('ChatInputArea default mode sends false for isItineraryMode', 
      (WidgetTester tester) async {
    String? sentMessage;
    Map<String, String>? sentPrefs;
    bool? sentItineraryMode;

    final controller = TextEditingController();

    // Build the widget
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatInputArea(
            inputController: controller,
            isSending: false,
            onSend: (message, preferences, isItineraryMode) {
              sentMessage = message;
              sentPrefs = preferences;
              sentItineraryMode = isItineraryMode;
            },
          ),
        ),
      ),
    );

    // Enter text
    await tester.enterText(find.byType(TextField), 'Hello Kuala Lumpur');
    await tester.pump();

    // Tap send button
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();

    // Assertions
    expect(sentMessage, 'Hello Kuala Lumpur');
    expect(sentItineraryMode, false);
    expect(sentPrefs?['budget'], 'Moderate');
  });

  testWidgets('Toggling Itinerary Mode sends true for isItineraryMode', 
      (WidgetTester tester) async {
    String? sentMessage;
    bool? sentItineraryMode;

    final controller = TextEditingController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatInputArea(
            inputController: controller,
            isSending: false,
            onSend: (message, preferences, isItineraryMode) {
              sentMessage = message;
              sentItineraryMode = isItineraryMode;
            },
          ),
        ),
      ),
    );

    // Enter text
    await tester.enterText(find.byType(TextField), 'Plan a 3 day trip');
    await tester.pump();

    // Tap the Itinerary Mode Toggle Pill
    await tester.tap(find.text('Itinerary Mode'));
    await tester.pump(); // trigger frame for state rebuild

    // Tap send button
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();

    // Assertions
    expect(sentMessage, 'Plan a 3 day trip');
    expect(sentItineraryMode, true);
  });

  testWidgets('When isSending is true, stop button renders and triggers onStop',
      (WidgetTester tester) async {
    bool stopTriggered = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatInputArea(
            inputController: TextEditingController(),
            isSending: true,
            onSend: (message, preferences, isItineraryMode) {},
            onStop: () {
              stopTriggered = true;
            },
          ),
        ),
      ),
    );

    // Verify stop button renders (it has Icon(Icons.stop_rounded))
    expect(find.byIcon(Icons.stop_rounded), findsOneWidget);

    // Tap the stop button
    await tester.tap(find.byIcon(Icons.stop_rounded));
    await tester.pump();

    // Verify onStop callback triggered
    expect(stopTriggered, true);
  });
}
