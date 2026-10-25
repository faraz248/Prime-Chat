import 'dart:convert';
import 'package:http/http.dart' as http;

class GeminiService {
  static final String _apiKey = const String.fromEnvironment('GEMINI_API_KEY', defaultValue: '').isNotEmpty
      ? const String.fromEnvironment('GEMINI_API_KEY')
      : utf8.decode(base64Decode('QVEuQWI4Uk42SmxkT2J1VnVtdmExZTM1Y0VGLWxLZHR0UjFPczJNbXROSTdJb1VKSUV1aXc='));

  // Active models in priority order with automatic fallback
  final List<String> _models = [
    'gemini-3.5-flash-lite',
    'gemini-flash-lite-latest',
    'gemini-3.5-flash',
    'gemini-3.8-flash',
  ];

  static const String _systemInstruction = 
    'You are Nexus AI Assistant, a friendly and intelligent personal assistant inside Nexus Chat. '
    'If the user asks for any photo, image, picture, wallpaper, drawing, or visual (e.g. "dog ki photo bhejo", "cat picture", "send a photo of a sports car", "ek kutte ki photo send kro", "tasveer dikhao"), you CAN and MUST provide it! '
    'To provide an image, you MUST include [IMAGE: descriptive english visual prompt] in your response alongside a natural, warm message in the user\'s language (Hindi, Hinglish, or English). '
    'Example 1: "Yeh lijiye pyaare se dog ki photo! 🐶 [IMAGE: a cute golden retriever puppy sitting happily in a green sunny park]" '
    'Example 2: "Here is a stunning photo of a red sports car for you! 🏎️ [IMAGE: modern sleek red sports car parked in a modern city during sunset]" '
    'NEVER say you cannot send photos or that you are text-only. You generate images dynamically using the [IMAGE: ...] tag.';

  Future<String> getAiResponse(String prompt) async {
    for (final model in _models) {
      try {
        final url = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$_apiKey',
        );

        final response = await http.post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'system_instruction': {
              'parts': [
                {'text': _systemInstruction}
              ]
            },
            'contents': [
              {
                'parts': [
                  {'text': prompt}
                ]
              }
            ]
          }),
        ).timeout(const Duration(seconds: 12));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final candidates = data['candidates'] as List?;
          if (candidates != null && candidates.isNotEmpty) {
            final content = candidates[0]['content'];
            final parts = content?['parts'] as List?;
            if (parts != null && parts.isNotEmpty) {
              final text = parts[0]['text'] as String?;
              if (text != null && text.trim().isNotEmpty) {
                return text.trim();
              }
            }
          }
        }
      } catch (_) {
        // Try next fallback model
        continue;
      }
    }

    return "Sorry, I couldn't generate a response right now. Please try again in a moment.";
  }
}
