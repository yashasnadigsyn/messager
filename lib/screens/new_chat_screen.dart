import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:file_picker/file_picker.dart';
import '../data/database_helper.dart';
import '../models/conversation.dart';
import 'chat_screen.dart';

class NewChatScreen extends StatefulWidget {
  const NewChatScreen({super.key});

  @override
  State<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends State<NewChatScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final DatabaseHelper _db = DatabaseHelper();

  // LiteRT fields
  final _litertPathController = TextEditingController();
  bool _isLitertUrl = false;

  // Gemini fields
  final _geminiApiKeyController = TextEditingController();
  final _geminiModelController = TextEditingController(
    text: 'gemini-2.5-flash',
  );

  // OpenRouter fields
  final _openrouterApiKeyController = TextEditingController();
  final _openrouterModelController = TextEditingController(
    text: 'google/gemma-3-27b-it:free',
  );

  // Common
  final _displayNameController = TextEditingController();
  bool _isCreating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(
      () => setState(() {
        _error = null;
      }),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _litertPathController.dispose();
    _geminiApiKeyController.dispose();
    _geminiModelController.dispose();
    _openrouterApiKeyController.dispose();
    _openrouterModelController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any);
    if (result != null && result.files.single.path != null) {
      setState(() {
        _litertPathController.text = result.files.single.path!;
      });
    }
  }

  Future<void> _createChat() async {
    setState(() {
      _error = null;
      _isCreating = true;
    });

    try {
      BackendType backendType;
      String modelIdentifier;
      String? apiKey;
      String defaultName;

      switch (_tabController.index) {
        case 0: // LiteRT
          backendType = BackendType.litert;
          modelIdentifier = _litertPathController.text.trim();
          if (modelIdentifier.isEmpty) {
            throw Exception('Please provide a model file path or URL.');
          }
          defaultName = modelIdentifier
              .split('/')
              .last
              .replaceAll('.litertlm', '');
          break;
        case 1: // Gemini
          backendType = BackendType.gemini;
          apiKey = _geminiApiKeyController.text.trim();
          modelIdentifier = _geminiModelController.text.trim();
          if (apiKey.isEmpty) {
            throw Exception('Please enter your Gemini API key.');
          }
          if (modelIdentifier.isEmpty) {
            throw Exception('Please enter a model name.');
          }
          defaultName = modelIdentifier;
          break;
        case 2: // OpenRouter
          backendType = BackendType.openrouter;
          apiKey = _openrouterApiKeyController.text.trim();
          modelIdentifier = _openrouterModelController.text.trim();
          if (apiKey.isEmpty) {
            throw Exception('Please enter your OpenRouter API key.');
          }
          if (modelIdentifier.isEmpty) {
            throw Exception('Please enter a model name.');
          }
          defaultName = modelIdentifier.split('/').last;
          break;
        default:
          return;
      }

      // Check for duplicate
      final exists = await _db.conversationExists(backendType, modelIdentifier);
      if (exists) {
        throw Exception(
          'A conversation with this model already exists. Open it from the home screen.',
        );
      }

      final displayName = _displayNameController.text.trim().isEmpty
          ? defaultName
          : _displayNameController.text.trim();

      final now = DateTime.now();
      final conversation = Conversation(
        id: const Uuid().v4(),
        backendType: backendType,
        modelIdentifier: modelIdentifier,
        displayName: displayName,
        apiKey: apiKey,
        createdAt: now,
        updatedAt: now,
      );

      await _db.insertConversation(conversation);

      if (mounted) {
        // Navigate to chat screen, replacing this screen
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ChatScreen(conversation: conversation),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() => _isCreating = false);
      }
    }
  }

  InputDecoration _inputDecoration(String hint, {IconData? icon}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white30),
      prefixIcon: icon != null
          ? Icon(icon, color: Colors.white38, size: 20)
          : null,
      filled: true,
      fillColor: const Color(0xFF0D1520),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1520),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E88E5),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context, false),
        ),
        title: const Text(
          'New Chat',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(icon: Icon(Icons.phone_android), text: 'LiteRT'),
            Tab(icon: Icon(Icons.auto_awesome), text: 'Gemini'),
            Tab(icon: Icon(Icons.cloud), text: 'OpenRouter'),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildLiteRTTab(),
                _buildGeminiTab(),
                _buildOpenRouterTab(),
              ],
            ),
          ),
          // Error message
          if (_error != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: const Color(0xFF3E1E1E),
              child: Row(
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: Color(0xFFEF5350),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        color: Color(0xFFEF5350),
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          // Display name + create button
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFF1A2332),
              border: Border(
                top: BorderSide(color: Color(0xFF243447), width: 1),
              ),
            ),
            child: Column(
              children: [
                TextField(
                  controller: _displayNameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: _inputDecoration(
                    'Display name (optional)',
                    icon: Icons.badge,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF1E88E5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _isCreating ? null : _createChat,
                    child: _isCreating
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'Start Chat',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiteRTTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E88E5).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFF1E88E5).withValues(alpha: 0.2),
              ),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: Color(0xFF1E88E5), size: 20),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Run AI models locally on your device. Only a single .litertlm file is needed — it includes the tokenizer.',
                    style: TextStyle(color: Colors.white60, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Toggle between file and URL
          Row(
            children: [
              ChoiceChip(
                label: const Text('Local File'),
                selected: !_isLitertUrl,
                selectedColor: const Color(0xFF1E88E5),
                labelStyle: TextStyle(
                  color: !_isLitertUrl ? Colors.white : Colors.white54,
                ),
                backgroundColor: const Color(0xFF1A2332),
                onSelected: (_) => setState(() => _isLitertUrl = false),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('URL'),
                selected: _isLitertUrl,
                selectedColor: const Color(0xFF1E88E5),
                labelStyle: TextStyle(
                  color: _isLitertUrl ? Colors.white : Colors.white54,
                ),
                backgroundColor: const Color(0xFF1A2332),
                onSelected: (_) => setState(() => _isLitertUrl = true),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_isLitertUrl)
            TextField(
              controller: _litertPathController,
              style: const TextStyle(color: Colors.white),
              decoration: _inputDecoration(
                'https://huggingface.co/.../model.litertlm',
                icon: Icons.link,
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _litertPathController,
                    style: const TextStyle(color: Colors.white),
                    readOnly: true,
                    decoration: _inputDecoration(
                      'Select .litertlm file',
                      icon: Icons.folder,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFF1E88E5),
                  ),
                  icon: const Icon(Icons.file_open, color: Colors.white),
                  onPressed: _pickFile,
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildGeminiTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF4285F4).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFF4285F4).withValues(alpha: 0.2),
              ),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: Color(0xFF4285F4), size: 20),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Chat using Google\'s Gemini API. Get your API key from aistudio.google.com.',
                    style: TextStyle(color: Colors.white60, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'API Key',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _geminiApiKeyController,
            style: const TextStyle(color: Colors.white),
            obscureText: true,
            decoration: _inputDecoration('AIza...', icon: Icons.key),
          ),
          const SizedBox(height: 20),
          const Text(
            'Model',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _geminiModelController,
            style: const TextStyle(color: Colors.white),
            decoration: _inputDecoration(
              'e.g. gemini-2.5-flash',
              icon: Icons.smart_toy,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOpenRouterTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFF6F00).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFFFF6F00).withValues(alpha: 0.2),
              ),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: Color(0xFFFF6F00), size: 20),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Access 100+ models via OpenRouter. Get your API key from openrouter.ai.',
                    style: TextStyle(color: Colors.white60, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'API Key',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _openrouterApiKeyController,
            style: const TextStyle(color: Colors.white),
            obscureText: true,
            decoration: _inputDecoration('sk-or-...', icon: Icons.key),
          ),
          const SizedBox(height: 20),
          const Text(
            'Model',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _openrouterModelController,
            style: const TextStyle(color: Colors.white),
            decoration: _inputDecoration(
              'e.g. google/gemma-3-27b-it:free',
              icon: Icons.smart_toy,
            ),
          ),
        ],
      ),
    );
  }
}
