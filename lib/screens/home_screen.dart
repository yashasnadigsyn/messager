import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../data/database_helper.dart';
import '../models/conversation.dart';
import 'new_chat_screen.dart';
import 'chat_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final DatabaseHelper _db = DatabaseHelper();
  List<Conversation> _conversations = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadConversations();
  }

  Future<void> _loadConversations() async {
    final conversations = await _db.getConversations();
    setState(() {
      _conversations = conversations;
      _loading = false;
    });
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) {
      return DateFormat('h:mm a').format(dt);
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return DateFormat('EEEE').format(dt);
    } else {
      return DateFormat('MM/dd/yy').format(dt);
    }
  }

  IconData _backendIcon(BackendType type) {
    switch (type) {
      case BackendType.litert:
        return Icons.phone_android;
      case BackendType.gemini:
        return Icons.auto_awesome;
      case BackendType.openrouter:
        return Icons.cloud;
    }
  }

  Color _backendColor(BackendType type) {
    switch (type) {
      case BackendType.litert:
        return const Color(0xFF4CAF50);
      case BackendType.gemini:
        return const Color(0xFF4285F4);
      case BackendType.openrouter:
        return const Color(0xFFFF6F00);
    }
  }

  void _showConversationOptions(Conversation conversation) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A2332),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.edit, color: Colors.white70),
                title: const Text('Rename', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  _renameConversation(conversation);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_sweep, color: Colors.white70),
                title: const Text('Clear messages', style: TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.pop(context);
                  await _db.deleteMessages(conversation.id);
                  conversation.lastMessage = '';
                  conversation.updatedAt = DateTime.now();
                  await _db.updateConversation(conversation);
                  _loadConversations();
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_forever, color: Color(0xFFEF5350)),
                title: const Text('Delete conversation',
                    style: TextStyle(color: Color(0xFFEF5350))),
                onTap: () async {
                  Navigator.pop(context);
                  await _db.deleteConversation(conversation.id);
                  _loadConversations();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _renameConversation(Conversation conversation) {
    final controller = TextEditingController(text: conversation.displayName);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1A2332),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Rename', style: TextStyle(color: Colors.white)),
          content: TextField(
            controller: controller,
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Display name',
              hintStyle: const TextStyle(color: Colors.white38),
              filled: true,
              fillColor: const Color(0xFF0D1520),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF1E88E5),
              ),
              onPressed: () async {
                final newName = controller.text.trim();
                if (newName.isNotEmpty) {
                  conversation.displayName = newName;
                  await _db.updateConversation(conversation);
                  _loadConversations();
                }
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1520),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E88E5),
        elevation: 0,
        title: Row(
          children: [
            Image.asset('assets/logo.png', height: 28, width: 28),
            const SizedBox(width: 10),
            const Text(
              'Messager',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF1E88E5)))
          : _conversations.isEmpty
              ? _buildEmptyState()
              : _buildConversationList(),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF1E88E5),
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const NewChatScreen()),
          );
          _loadConversations();
        },
        child: const Icon(Icons.add, color: Colors.white, size: 28),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset('assets/logo.png', height: 80, width: 80, opacity: const AlwaysStoppedAnimation(0.3)),
          const SizedBox(height: 24),
          const Text(
            'No conversations yet',
            style: TextStyle(color: Colors.white38, fontSize: 18, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          const Text(
            'Tap + to start chatting with an AI',
            style: TextStyle(color: Colors.white24, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildConversationList() {
    return ListView.builder(
      padding: const EdgeInsets.only(top: 4),
      itemCount: _conversations.length,
      itemBuilder: (context, index) {
        final conv = _conversations[index];
        return InkWell(
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => ChatScreen(conversation: conv)),
            );
            _loadConversations();
          },
          onLongPress: () => _showConversationOptions(conv),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFF1A2332), width: 1)),
            ),
            child: Row(
              children: [
                // Avatar with backend icon
                CircleAvatar(
                  radius: 26,
                  backgroundColor: _backendColor(conv.backendType).withValues(alpha: 0.15),
                  child: Icon(
                    _backendIcon(conv.backendType),
                    color: _backendColor(conv.backendType),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                // Name and last message
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        conv.displayName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        conv.lastMessage.isEmpty ? 'No messages yet' : conv.lastMessage,
                        style: TextStyle(
                          color: conv.lastMessage.isEmpty ? Colors.white24 : Colors.white54,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Time
                Text(
                  _formatTime(conv.updatedAt),
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
