import 'dart:io';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../models/message.dart';
import 'chat_backend.dart';

class GeminiBackend extends ChatBackend {
  final String apiKey;
  final String modelName;
  final String systemPrompt;

  GenerativeModel? _model;
  ChatSession? _chat;

  GeminiBackend({
    required this.apiKey,
    required this.modelName,
    this.systemPrompt = '',
  });

  @override
  Future<void> initialize() async {
    _model = GenerativeModel(
      model: modelName,
      apiKey: apiKey,
      systemInstruction: systemPrompt.isNotEmpty
          ? Content.system(systemPrompt)
          : null,
    );
    _chat = _model!.startChat();
  }

  @override
  Future<String> sendMessage(String prompt, List<Message> history, {String? imagePath, String? audioPath}) async {
    if (_chat == null) {
      throw Exception('Gemini model not initialized.');
    }

    // If chat session is fresh but we have history, rebuild it
    if (_chat!.history.isEmpty && history.isNotEmpty) {
      final historyContent = history.map((m) {
        return Content(m.role == 'user' ? 'user' : 'model', [TextPart(m.content)]);
      }).toList();

      _chat = _model!.startChat(history: historyContent);
    }

    try {
      final parts = <Part>[TextPart(prompt)];
      if (imagePath != null) {
        final bytes = await File(imagePath).readAsBytes();
        final ext = imagePath.split('.').last.toLowerCase();
        final mimeType = ext == 'png' ? 'image/png' : (ext == 'webp' ? 'image/webp' : 'image/jpeg');
        parts.add(DataPart(mimeType, bytes));
      }
      final response = await _chat!.sendMessage(Content.multi(parts));
      return response.text ?? 'No response received.';
    } catch (e) {
      throw Exception('Gemini API error: $e');
    }
  }

  @override
  void dispose() {
    _chat = null;
    _model = null;
  }
}
