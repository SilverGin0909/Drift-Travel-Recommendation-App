import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';

class UserService {
  static Future<Map<String, dynamic>?> fetchProfileDetails(
    String userId,
  ) async {
    return await Supabase.instance.client
        .from('user_preferences')
        .select('username, avatar_url')
        .eq('id', userId)
        .maybeSingle();
  }

  static Future<Map<String, dynamic>?> fetchLatestSession(String userId) async {
    return await Supabase.instance.client
        .from('chat_sessions')
        .select('id')
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
  }

  static Future<String> uploadProfilePicture(String userId, XFile image) async {
    final bytes = await image.readAsBytes();
    final fileExt = image.name.split('.').last;
    final fileName =
        '$userId-${DateTime.now().millisecondsSinceEpoch}.$fileExt';

    await Supabase.instance.client.storage
        .from('avatars')
        .uploadBinary(fileName, bytes);

    final String publicUrl = Supabase.instance.client.storage
        .from('avatars')
        .getPublicUrl(fileName);

    await Supabase.instance.client
        .from('user_preferences')
        .update({'avatar_url': publicUrl})
        .eq('id', userId);

    return publicUrl;
  }

  static Future<List<Map<String, dynamic>>> fetchChatMessages(
    String sessionId,
  ) async {
    return await Supabase.instance.client
        .from('chat_messages')
        .select('role, content')
        .eq('session_id', sessionId)
        .order('created_at', ascending: true);
  }
}
