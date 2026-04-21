import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_litert_lm/flutter_litert_lm.dart';
import '../models/message.dart';
import 'chat_backend.dart';

class LiteRTBackend extends ChatBackend {
  final String modelSource; // local path or URL
  final String systemPrompt;

  LiteLmEngine? _engine;
  LiteLmConversation? _conversation;
  bool _isLoaded = false;

  /// Download progress: 0.0–1.0 for download, -1 for indeterminate, -2 for done
  final ValueNotifier<double> progress = ValueNotifier<double>(0.0);

  /// Status text for UI display
  final ValueNotifier<String> statusText = ValueNotifier<String>('Preparing...');

  LiteRTBackend({required this.modelSource, this.systemPrompt = ''});

  @override
  Future<void> initialize() async {
    String modelPath;

    // If it's a URL, download the model first
    if (modelSource.startsWith('http://') || modelSource.startsWith('https://')) {
      statusText.value = 'Starting download...';
      modelPath = await _downloadModel(modelSource);
    } else {
      // Local file path
      final file = File(modelSource);
      if (!await file.exists()) {
        throw Exception('Model file not found at: $modelSource');
      }
      modelPath = modelSource;
    }

    // Load the model using flutter_litert_lm
    statusText.value = 'Loading model into memory...';
    progress.value = -1; // indeterminate
    try {
      _engine = await LiteLmEngine.create(
        LiteLmEngineConfig(
          modelPath: modelPath,
          backend: LiteLmBackend.cpu,
        ),
      );

      _conversation = await _engine!.createConversation(
        LiteLmConversationConfig(
          systemInstruction: systemPrompt.isNotEmpty ? systemPrompt : null,
          samplerConfig: const LiteLmSamplerConfig(
            temperature: 0.7,
            topK: 40,
            topP: 0.95,
          ),
        ),
      );

      _isLoaded = true;
      statusText.value = 'Ready';
      progress.value = -2; // done
    } catch (e) {
      throw Exception('Failed to load LiteRT model: $e');
    }
  }

  Future<String> _downloadModel(String url) async {
    final dir = await getApplicationDocumentsDirectory();
    final fileName = url.split('/').last.split('?').first;
    final filePath = '${dir.path}/$fileName';

    final file = File(filePath);
    if (await file.exists() && await file.length() > 1024 * 1024) {
      statusText.value = 'Model already downloaded';
      progress.value = 1.0;
      return filePath;
    }

    final dio = Dio();
    await dio.download(
      url,
      filePath,
      onReceiveProgress: (received, total) {
        if (total != -1) {
          final pct = received / total;
          progress.value = pct;
          final receivedMB = (received / 1024 / 1024).toStringAsFixed(1);
          final totalMB = (total / 1024 / 1024).toStringAsFixed(1);
          statusText.value = 'Downloading: ${(pct * 100).toStringAsFixed(1)}% ($receivedMB / $totalMB MB)';
        } else {
          final receivedMB = (received / 1024 / 1024).toStringAsFixed(1);
          statusText.value = 'Downloading: $receivedMB MB';
        }
      },
    );

    statusText.value = 'Download complete';
    progress.value = 1.0;
    return filePath;
  }

  @override
  Future<String> sendMessage(String prompt, List<Message> history, {String? imagePath, String? audioPath}) async {
    if (!_isLoaded || _conversation == null) {
      throw Exception('Model not loaded yet.');
    }

    try {
      if (imagePath != null || audioPath != null) {
        final List<LiteLmContent> parts = [];
        if (imagePath != null) parts.add(LiteLmContent.imageFile(imagePath));
        if (audioPath != null) parts.add(LiteLmContent.audioFile(audioPath));
        
        if (prompt.isNotEmpty) parts.add(LiteLmContent.text(prompt));
        
        final reply = await _conversation!.sendMultimodalMessage(parts);
        return reply.text;
      } else {
        final reply = await _conversation!.sendMessage(prompt);
        return reply.text;
      }
    } catch (e) {
      return 'Error: $e';
    }
  }

  @override
  void dispose() {
    _conversation?.dispose();
    _engine?.dispose();
    progress.dispose();
    statusText.dispose();
  }
}
