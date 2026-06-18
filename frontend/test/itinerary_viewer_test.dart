import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/screens/itinerary_viewer.dart';

void main() {
  final mockItinerary = {
    "destination": "Kyoto Trip",
    "duration_days": 2,
    "days": [
      {
        "day_number": 1,
        "theme": "Historic Exploration",
        "activities": [
          {
            "time": "09:00 AM",
            "title": "Fushimi Inari Shrine",
            "description": "Walk through torii gates",
            "location": "Kyoto, Japan"
          },
          {
            "time": "02:00 PM",
            "title": "Kinkaku-ji Temple",
            "description": "Golden pavilion visit",
            "location": "Northern Kyoto"
          }
        ]
      },
      {
        "day_number": 2,
        "theme": "Nature Trails",
        "activities": [
          {
            "time": "10:00 AM",
            "title": "Arashiyama Bamboo Grove",
            "description": "Walk among towering bamboo stalks",
            "location": "Western Kyoto"
          }
        ]
      }
    ]
  };

  testWidgets('ItineraryViewer displays destination, tabs, and Day 1 activities', 
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ItineraryViewer(
          itinerary: mockItinerary,
          sessionId: "test-session-123",
        ),
      ),
    );

    // Verify destination is in the AppBar
    expect(find.text('Kyoto Trip'), findsOneWidget);

    // Verify both day tabs are rendered
    expect(find.text('Day 1'), findsOneWidget);
    expect(find.text('Day 2'), findsOneWidget);

    // Verify Day 1 theme banner is displayed
    expect(find.text('Historic Exploration'), findsOneWidget);

    // Verify Day 1 activities are visible
    expect(find.text('Fushimi Inari Shrine'), findsOneWidget);
    expect(find.text('Kinkaku-ji Temple'), findsOneWidget);
  });

  testWidgets('Deleting an activity removes it from the view state', 
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ItineraryViewer(
          itinerary: mockItinerary,
          sessionId: "test-session-123",
        ),
      ),
    );

    // Verify Fushimi Inari is initially visible
    expect(find.text('Fushimi Inari Shrine'), findsOneWidget);

    // Find the delete button (trash bin icon) for the first activity card
    final deleteButtons = find.byIcon(Icons.delete_outline_rounded);
    
    // Tap the first delete button to remove Fushimi Inari
    await tester.tap(deleteButtons.first);
    await tester.pumpAndSettle(); // Rebuild state and settle deletions

    // Verify Fushimi Inari is removed, but Kinkaku-ji remains
    expect(find.text('Fushimi Inari Shrine'), findsNothing);
    expect(find.text('Kinkaku-ji Temple'), findsOneWidget);
  });
}
