import '../models/message.dart';

abstract class ChatBackend {
  /// Initialize the backend (load model, validate API key, etc.)
  Future<void> initialize();

  /// Send a message and get a response. History is provided for context.
  Future<String> sendMessage(String prompt, List<Message> history, {String? imagePath, String? audioPath});

  /// Clean up resources
  void dispose();
}
