import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/message.dart';
import 'chat_backend.dart';

class OpenRouterBackend extends ChatBackend {
  final String apiKey;
  final String modelName;
  final String systemPrompt;

  static const String _baseUrl = 'https://openrouter.ai/api/v1/chat/completions';

  OpenRouterBackend({
    required this.apiKey,
    required this.modelName,
    this.systemPrompt = '',
  });

  @override
  Future<void> initialize() async {
    // Validate API key with a lightweight request
    // For now, just mark as ready — errors will surface on first message
  }

  @override
  Future<String> sendMessage(String prompt, List<Message> history, {String? imagePath, String? audioPath}) async {
    final messages = <Map<String, dynamic>>[];

    // Add system prompt first
    if (systemPrompt.isNotEmpty) {
      messages.add({
        'role': 'system',
        'content': systemPrompt,
      });
    }

    // Add conversation history for context
    for (final msg in history) {
      messages.add({
        'role': msg.role == 'user' ? 'user' : 'assistant',
        'content': msg.content,
      });
    }

    // Add the new user message
    if (imagePath != null) {
      final bytes = await File(imagePath).readAsBytes();
      final base64Image = base64Encode(bytes);
      final ext = imagePath.split('.').last.toLowerCase();
      final mimeType = ext == 'png' ? 'image/png' : (ext == 'webp' ? 'image/webp' : 'image/jpeg');
      
      messages.add({
        'role': 'user',
        'content': [
          {'type': 'text', 'text': prompt},
          {
            'type': 'image_url',
            'image_url': {'url': 'data:$mimeType;base64,$base64Image'}
          }
        ],
      });
    } else {
      messages.add({
        'role': 'user',
        'content': prompt,
      });
    }

    // Ensure API key doesn't have extra whitespace
    final cleanKey = apiKey.trim();

    try {
      final response = await http.post(
        Uri.parse(_baseUrl),
        headers: {
          'Authorization': 'Bearer $cleanKey',
          'Content-Type': 'application/json',
          'HTTP-Referer': 'https://github.com/yashasnadigsyn/messager',
          'X-Title': 'Messager',
        },
        body: jsonEncode({
          'model': modelName,
          'messages': messages,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final content = data['choices']?[0]?['message']?['content'];
        if (content != null) {
          return content as String;
        }
        return 'No response received.';
      } else if (response.statusCode == 401) {
        throw Exception(
          'Authentication failed. Please check your OpenRouter API key. '
          'Make sure it starts with "sk-or-" and is valid at openrouter.ai/keys',
        );
      } else {
        final error = jsonDecode(response.body);
        throw Exception(
          'OpenRouter error (${response.statusCode}): ${error['error']?['message'] ?? response.body}',
        );
      }
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Network error: $e');
    }
  }

  @override
  void dispose() {
    // Nothing to clean up for HTTP-based backend
  }
}
