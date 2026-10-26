import 'dart:convert';
import 'package:http/http.dart' as http;

class GeminiService {
  static final String _apiKey = const String.fromEnvironment('GEMINI_API_KEY', defaultValue: '').isNotEmpty
      ? const String.fromEnvironment('GEMINI_API_KEY')
      : utf8.decode(base64Decode('QVEuQWI4Uk42SmxkT2J1VnVtdmExZTM1Y0VGLWxLZHR0UjFPczJNbXROSTdJb1VKSUV1aXc='));

  // Active models in priority order with automatic fallback
  final List<String> _models = [
    'gemini-1.5-flash',
    'gemini-2.0-flash',
    'gemini-1.5-flash-8b',
    'gemini-1.5-pro',
    'gemini-flash-lite-latest',
  ];

  static const String _systemInstruction = 
    'You are Prime AI Assistant & Tutor, a friendly, ultra-intelligent personal assistant and academic tutor inside Prime Chat. '
    '1. ACADEMIC & PROBLEM SOLVER: When a user sends an image of a problem, question, textbook page, homework, math equation, coding question, or assignment, inspect the image thoroughly. Answer the user\'s question or problem step-by-step with high accuracy, clarity, and helpful explanations in their language (Hindi, Hinglish, or English). If the problem is complex, break it down clearly. '
    '2. FORMATTING RULES (CRITICAL): '
    '- NEVER use LaTeX math notation, dollar signs (\$ or \$\$), backslashes, or code tags like \\text{}, \\emptyset, \\{...\\}, etc. '
    '- NEVER use raw markdown headers (### or ##). '
    '- Write all mathematical formulas and answers in simple, crystal-clear plain text using standard symbols (e.g., write "A - B = 1", "Visited: {A}", "Empty set", "x^2", "a / b", "Cost = 1"). '
    '- Keep explanations super easy for a student to read on a mobile phone without confusing mathematical symbols. Use clean numbered steps (1., 2., 3.) and bullet points (•). '
    '3. IMAGE GENERATION: If the user asks for any photo, image, picture, wallpaper, drawing, or visual (e.g. "dog ki photo bhejo", "send a photo of a sports car", "tasveer dikhao"), you CAN and MUST provide it! '
    'To provide an image, you MUST include [IMAGE: descriptive english visual prompt] in your response alongside a natural, warm message. '
    'NEVER say you cannot view images or that you are text-only. You fully support multimodal vision and can analyze all photos, documents, and homework assignments.';

  static String cleanAiFormatting(String text) {
    var s = text;
    // Replace common LaTeX terms with plain words/symbols
    s = s.replaceAll(r'\emptyset', 'Empty Set (∅)');
    s = s.replaceAll(r'\infty', '∞');
    s = s.replaceAll(r'\times', '×');
    s = s.replaceAll(r'\div', '÷');
    s = s.replaceAll(r'\leq', '≤');
    s = s.replaceAll(r'\geq', '≥');
    s = s.replaceAll(r'\neq', '≠');
    s = s.replaceAll(r'\approx', '≈');
    s = s.replaceAll(r'\pm', '±');
    s = s.replaceAll(r'\to', '➔');
    s = s.replaceAll(r'\leftarrow', '←');
    s = s.replaceAll(r'\rightarrow', '➔');

    // Remove LaTeX wrapper commands like \text{...}, \mathbf{...}, \mathit{...}
    s = s.replaceAllMapped(RegExp(r'\\(?:text|mathbf|mathit|mathrm|mathbb|mathcal)\{([^}]*)\}'), (m) => m.group(1) ?? '');
    
    // Clean fractions: \frac{a}{b} -> (a / b)
    s = s.replaceAllMapped(RegExp(r'\\frac\{([^}]*)\}\{([^}]*)\}'), (m) => '(${m.group(1)} / ${m.group(2)})');

    // Clean square root: \sqrt{x} -> √(x)
    s = s.replaceAllMapped(RegExp(r'\\sqrt\{([^}]*)\}'), (m) => '√(${m.group(1)})');

    // Clean LaTeX escaped braces: \{A\} -> {A}
    s = s.replaceAll(r'\{', '{').replaceAll(r'\}', '}');

    // Remove all dollar signs used for math blocks ($$ and $)
    s = s.replaceAll(r'$$', '');
    s = s.replaceAll(r'$', '');

    // Remove raw Markdown header hashes at beginning of lines (### Title -> Title)
    s = s.replaceAll(RegExp(r'^\s*#{1,6}\s*', multiLine: true), '');

    // Clean up nested asterisks like ****A**** -> **A**
    s = s.replaceAll('****', '**');

    // Clean up multiple horizontal rule lines (---)
    s = s.replaceAll(RegExp(r'^\s*---+\s*$', multiLine: true), '');

    // Replace standalone asterisk bullets (* ) with nice clean bullet points (• )
    s = s.replaceAll(RegExp(r'^\s*\*\s+', multiLine: true), '• ');

    // Normalize excessive newlines
    s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n');

    return s.trim();
  }

  Future<String> getAiResponse(String prompt, {String? imageUrl}) async {
    // Prepare image payload if available
    Map<String, dynamic>? inlineDataPart;
    if (imageUrl != null && imageUrl.isNotEmpty) {
      try {
        if (imageUrl.startsWith('data:')) {
          final regex = RegExp(r'data:([^;]+);base64,(.+)');
          final match = regex.firstMatch(imageUrl);
          if (match != null) {
            inlineDataPart = {
              'inline_data': {
                'mime_type': match.group(1) ?? 'image/jpeg',
                'data': match.group(2)!.trim(),
              }
            };
          }
        } else if (imageUrl.startsWith('http')) {
          final imgRes = await http.get(Uri.parse(imageUrl)).timeout(const Duration(seconds: 8));
          if (imgRes.statusCode == 200) {
            final contentType = imgRes.headers['content-type'] ?? 'image/jpeg';
            inlineDataPart = {
              'inline_data': {
                'mime_type': contentType.split(';').first.trim(),
                'data': base64Encode(imgRes.bodyBytes),
              }
            };
          }
        }
      } catch (_) {
        // Continue even if image fetch failed
      }
    }

    final effectivePrompt = prompt.isNotEmpty 
        ? prompt 
        : (inlineDataPart != null ? 'Please analyze this image, solve the question or assignment shown, and provide a clear step-by-step solution.' : 'Hello');

    for (final model in _models) {
      try {
        final url = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$_apiKey',
        );

        final parts = <Map<String, dynamic>>[
          {'text': effectivePrompt}
        ];
        if (inlineDataPart != null) {
          parts.add(inlineDataPart);
        }

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
                'parts': parts
              }
            ]
          }),
        ).timeout(const Duration(seconds: 15));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final candidates = data['candidates'] as List?;
          if (candidates != null && candidates.isNotEmpty) {
            final content = candidates[0]['content'];
            final returnedParts = content?['parts'] as List?;
            if (returnedParts != null && returnedParts.isNotEmpty) {
              final text = returnedParts[0]['text'] as String?;
              if (text != null && text.trim().isNotEmpty) {
                return cleanAiFormatting(text);
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
