import 'package:http/http.dart' as http;
import 'dart:convert';

class ApiService {
  static Future<http.StreamedResponse> sendChatMessage({
    required String userID,
    required String? sessionId,
    required String text,
    required double? lat,
    required double? lng,
    String? prefsContext,
  }) async {
    final String backendUrl = "http://10.0.2.2:8000/api/chat";
    final request = http.Request('POST', Uri.parse(backendUrl));
    request.headers['Content-Type'] = 'application/json';
    request.body = jsonEncode({
      "user_id": userID,
      "session_id": sessionId ?? "",
      "message": text,
      "user_lat": lat,
      "user_lng": lng,
      "prefs_context":
          prefsContext ??
          "Budget: Moderate, Style: General, Interests: Sightseeing",
    });

    return await http.Client().send(request);
  }
}
