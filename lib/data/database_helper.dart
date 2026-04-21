import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/conversation.dart';
import '../models/message.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'messager.db');

    return await openDatabase(
      path,
      version: 5,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE conversations (
        id TEXT PRIMARY KEY,
        backendType TEXT NOT NULL,
        modelIdentifier TEXT NOT NULL,
        displayName TEXT NOT NULL,
        apiKey TEXT,
        systemPrompt TEXT DEFAULT '',
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        lastMessage TEXT DEFAULT '',
        UNIQUE(backendType, modelIdentifier)
      )
    ''');

    await db.execute('''
      CREATE TABLE messages (
        id TEXT PRIMARY KEY,
        conversationId TEXT NOT NULL,
        role TEXT NOT NULL,
        content TEXT NOT NULL,
        imagePath TEXT,
        audioPath TEXT,
        timestamp TEXT NOT NULL,
        reaction TEXT,
        replyToId TEXT,
        replyToContent TEXT,
        status TEXT DEFAULT 'sent',
        FOREIGN KEY (conversationId) REFERENCES conversations(id) ON DELETE CASCADE
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
        "ALTER TABLE conversations ADD COLUMN systemPrompt TEXT DEFAULT ''",
      );
    }
    if (oldVersion < 3) {
      await db.execute("ALTER TABLE messages ADD COLUMN imagePath TEXT");
    }
    if (oldVersion < 4) {
      await db.execute("ALTER TABLE messages ADD COLUMN audioPath TEXT");
    }
    if (oldVersion < 5) {
      await db.execute("ALTER TABLE messages ADD COLUMN reaction TEXT");
      await db.execute("ALTER TABLE messages ADD COLUMN replyToId TEXT");
      await db.execute("ALTER TABLE messages ADD COLUMN replyToContent TEXT");
      await db.execute(
        "ALTER TABLE messages ADD COLUMN status TEXT DEFAULT 'sent'",
      );
    }
  }

  // ── Conversations ──

  Future<void> insertConversation(Conversation conversation) async {
    final db = await database;
    await db.insert(
      'conversations',
      conversation.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<List<Conversation>> getConversations() async {
    final db = await database;
    final maps = await db.query('conversations', orderBy: 'updatedAt DESC');
    return maps.map((m) => Conversation.fromMap(m)).toList();
  }

  Future<Conversation?> getConversation(String id) async {
    final db = await database;
    final maps = await db.query(
      'conversations',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isEmpty) return null;
    return Conversation.fromMap(maps.first);
  }

  Future<bool> conversationExists(
    BackendType backendType,
    String modelIdentifier,
  ) async {
    final db = await database;
    final maps = await db.query(
      'conversations',
      where: 'backendType = ? AND modelIdentifier = ?',
      whereArgs: [backendType.name, modelIdentifier],
    );
    return maps.isNotEmpty;
  }

  Future<void> updateConversation(Conversation conversation) async {
    final db = await database;
    await db.update(
      'conversations',
      conversation.toMap(),
      where: 'id = ?',
      whereArgs: [conversation.id],
    );
  }

  Future<void> deleteConversation(String id) async {
    final db = await database;
    await db.delete('messages', where: 'conversationId = ?', whereArgs: [id]);
    await db.delete('conversations', where: 'id = ?', whereArgs: [id]);
  }

  // ── Messages ──

  Future<void> insertMessage(Message message) async {
    final db = await database;
    await db.insert('messages', message.toMap());
  }

  Future<void> updateMessage(Message message) async {
    final db = await database;
    await db.update(
      'messages',
      message.toMap(),
      where: 'id = ?',
      whereArgs: [message.id],
    );
  }

  Future<List<Message>> getMessages(String conversationId) async {
    final db = await database;
    final maps = await db.query(
      'messages',
      where: 'conversationId = ?',
      whereArgs: [conversationId],
      orderBy: 'timestamp ASC',
    );
    return maps.map((m) => Message.fromMap(m)).toList();
  }

  Future<void> deleteMessages(String conversationId) async {
    final db = await database;
    await db.delete(
      'messages',
      where: 'conversationId = ?',
      whereArgs: [conversationId],
    );
  }
}
