import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ContactManagementApp());
}

/// Root Application Widget
class ContactManagementApp extends StatelessWidget {
  const ContactManagementApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Contact Book - Local CRUD',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB), // Modern Royal Blue
          brightness: Brightness.light,
          primary: const Color(0xFF2563EB),
          surface: const Color(0xFFF8FAFC),
        ),
        scaffoldBackgroundColor: const Color(0xFFF1F5F9),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 1,
          centerTitle: false,
          titleTextStyle: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Color(0xFF0F172A),
          ),
        ),
        cardTheme: CardTheme(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          color: Colors.white,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF8FAFC),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF2563EB), width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFEF4444)),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFEF4444), width: 2),
          ),
        ),
      ),
      home: const ContactListScreen(),
    );
  }
}

// ==========================================
// 1. DATA MODEL
// ==========================================

class Contact {
  final int? id;
  final String name;
  final String phone;
  final String email;
  final String address;
  final bool isFavorite;

  const Contact({
    this.id,
    required this.name,
    required this.phone,
    required this.email,
    required this.address,
    this.isFavorite = false,
  });

  /// Convert Contact object to Map for SQLite storage
  Map<String, Object?> toMap() {
    final map = <String, Object?>{
      'name': name.trim(),
      'phone': phone.trim(),
      'email': email.trim(),
      'address': address.trim(),
      'is_favorite': isFavorite ? 1 : 0,
    };
    if (id != null) {
      map['id'] = id;
    }
    return map;
  }

  /// Create Contact object from SQLite Map
  factory Contact.fromMap(Map<String, Object?> map) {
    return Contact(
      id: map['id'] as int?,
      name: map['name'] as String,
      phone: map['phone'] as String,
      email: map['email'] as String,
      address: map['address'] as String,
      isFavorite: (map['is_favorite'] as int?) == 1,
    );
  }

  /// Create a copy with modified fields
  Contact copyWith({
    int? id,
    String? name,
    String? phone,
    String? email,
    String? address,
    bool? isFavorite,
  }) {
    return Contact(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      address: address ?? this.address,
      isFavorite: isFavorite ?? this.isFavorite,
    );
  }
}

// ==========================================
// 2. DATABASE HELPER (LOCAL SQLITE CRUD + CROSS-PLATFORM)
// ==========================================

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static sqflite.Database? _database;

  // Graceful in-memory fallback store
  bool _useFallback = false;
  final List<Contact> _fallbackStore = [];
  int _fallbackIdCounter = 1;

  DatabaseHelper._init();

  Future<sqflite.Database?> get database async {
    if (_useFallback) return null;
    if (_database != null) return _database!;

    try {
      final sqflite.DatabaseFactory factory;
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        sqfliteFfiInit();
        factory = databaseFactoryFfi;
      } else {
        factory = sqflite.databaseFactory;
      }

      final dbPath = await factory.getDatabasesPath();
      final path = p.join(dbPath, 'contacts_manager.db');

      _database = await factory.openDatabase(
        path,
        options: sqflite.OpenDatabaseOptions(
          version: 1,
          onCreate: (db, version) async {
            await db.execute('''
              CREATE TABLE contacts (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                phone TEXT NOT NULL,
                email TEXT NOT NULL,
                address TEXT NOT NULL,
                is_favorite INTEGER NOT NULL DEFAULT 0
              )
            ''');
          },
        ),
      );
      return _database!;
    } catch (e) {
      debugPrint('SQLite initialization note: using fallback store ($e)');
      _useFallback = true;
      return null;
    }
  }

  /// CREATE: Insert a new contact
  Future<int> insertContact(Contact contact) async {
    final db = await database;
    if (db != null) {
      final map = contact.toMap()..remove('id');
      return await db.insert('contacts', map);
    } else {
      final newId = _fallbackIdCounter++;
      _fallbackStore.add(contact.copyWith(id: newId));
      return newId;
    }
  }

  /// READ: Get contacts with optional search query & favorites filter
  Future<List<Contact>> getAllContacts({
    String query = '',
    bool favoritesOnly = false,
  }) async {
    final db = await database;
    final trimmedQuery = query.trim().toLowerCase();

    if (db != null) {
      String? whereClause;
      List<Object?> whereArgs = [];

      if (favoritesOnly && trimmedQuery.isNotEmpty) {
        whereClause = 'is_favorite = 1 AND LOWER(name) LIKE ?';
        whereArgs = ['%$trimmedQuery%'];
      } else if (favoritesOnly) {
        whereClause = 'is_favorite = 1';
      } else if (trimmedQuery.isNotEmpty) {
        whereClause = 'LOWER(name) LIKE ?';
        whereArgs = ['%$trimmedQuery%'];
      }

      final result = await db.query(
        'contacts',
        where: whereClause,
        whereArgs: whereArgs.isEmpty ? null : whereArgs,
        orderBy: 'is_favorite DESC, name COLLATE NOCASE ASC',
      );

      return result.map((json) => Contact.fromMap(json)).toList();
    } else {
      var list = List<Contact>.from(_fallbackStore);
      if (favoritesOnly) {
        list = list.where((c) => c.isFavorite).toList();
      }
      if (trimmedQuery.isNotEmpty) {
        list = list.where((c) => c.name.toLowerCase().contains(trimmedQuery)).toList();
      }
      list.sort((a, b) {
        if (a.isFavorite != b.isFavorite) {
          return b.isFavorite ? 1 : -1;
        }
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      return list;
    }
  }

  /// UPDATE: Update an existing contact
  Future<int> updateContact(Contact contact) async {
    final db = await database;
    if (db != null) {
      return await db.update(
        'contacts',
        contact.toMap(),
        where: 'id = ?',
        whereArgs: [contact.id],
      );
    } else {
      final index = _fallbackStore.indexWhere((c) => c.id == contact.id);
      if (index != -1) {
        _fallbackStore[index] = contact;
        return 1;
      }
      return 0;
    }
  }

  /// DELETE: Remove a contact by ID
  Future<int> deleteContact(int id) async {
    final db = await database;
    if (db != null) {
      return await db.delete(
        'contacts',
        where: 'id = ?',
        whereArgs: [id],
      );
    } else {
      final initialLength = _fallbackStore.length;
      _fallbackStore.removeWhere((c) => c.id == id);
      return initialLength - _fallbackStore.length;
    }
  }

  /// TOGGLE FAVORITE
  Future<int> toggleFavorite(int id, bool currentStatus) async {
    final db = await database;
    final newStatus = !currentStatus;
    if (db != null) {
      return await db.update(
        'contacts',
        {'is_favorite': newStatus ? 1 : 0},
        where: 'id = ?',
        whereArgs: [id],
      );
    } else {
      final index = _fallbackStore.indexWhere((c) => c.id == id);
      if (index != -1) {
        _fallbackStore[index] = _fallbackStore[index].copyWith(isFavorite: newStatus);
        return 1;
      }
      return 0;
    }
  }

  /// Get stats: total contacts and favorites count
  Future<Map<String, int>> getStats() async {
    final all = await getAllContacts();
    final favorites = all.where((c) => c.isFavorite).length;
    return {
      'total': all.length,
      'favorites': favorites,
    };
  }
}

// ==========================================
// 3. MAIN UI SCREEN
// ==========================================

class ContactListScreen extends StatefulWidget {
  const ContactListScreen({super.key});

  @override
  State<ContactListScreen> createState() => _ContactListScreenState();
}

class _ContactListScreenState extends State<ContactListScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Contact> _contacts = [];
  bool _isLoading = true;
  bool _showFavoritesOnly = false;
  int _totalCount = 0;
  int _favoritesCount = 0;

  @override
  void initState() {
    super.initState();
    _refreshContacts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Reload contacts and counters from local database
  Future<void> _refreshContacts() async {
    setState(() => _isLoading = true);

    final contacts = await DatabaseHelper.instance.getAllContacts(
      query: _searchController.text,
      favoritesOnly: _showFavoritesOnly,
    );

    final stats = await DatabaseHelper.instance.getStats();

    if (mounted) {
      setState(() {
        _contacts = contacts;
        _totalCount = stats['total'] ?? 0;
        _favoritesCount = stats['favorites'] ?? 0;
        _isLoading = false;
      });
    }
  }

  /// Open Bottom Sheet to Add or Edit contact
  Future<void> _openContactForm([Contact? contact]) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ContactFormSheet(contact: contact),
    );

    if (result == true) {
      _refreshContacts();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              contact == null
                  ? 'Contact saved successfully!'
                  : 'Contact updated successfully!',
            ),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  /// Confirm and delete contact
  Future<void> _confirmDeleteContact(Contact contact) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444), size: 28),
            SizedBox(width: 8),
            Text('Delete Contact'),
          ],
        ),
        content: Text(
          'Are you sure you want to delete "${contact.name}"? This action cannot be undone.',
          style: const TextStyle(color: Color(0xFF475569), fontSize: 15),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && contact.id != null) {
      await DatabaseHelper.instance.deleteContact(contact.id!);
      _refreshContacts();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Removed ${contact.name}'),
            backgroundColor: const Color(0xFF334155),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            action: SnackBarAction(
              label: 'UNDO',
              textColor: const Color(0xFF60A5FA),
              onPressed: () async {
                await DatabaseHelper.instance.insertContact(contact);
                _refreshContacts();
              },
            ),
          ),
        );
      }
    }
  }

  /// Show contact details dialog
  void _viewContactDetails(Contact contact) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ContactDetailSheet(
        contact: contact,
        onEdit: () {
          Navigator.pop(context);
          _openContactForm(contact);
        },
        onDelete: () {
          Navigator.pop(context);
          _confirmDeleteContact(contact);
        },
        onToggleFavorite: () async {
          if (contact.id != null) {
            await DatabaseHelper.instance.toggleFavorite(contact.id!, contact.isFavorite);
            Navigator.pop(context);
            _refreshContacts();
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Contacts'),
            Text(
              '$_totalCount saved • $_favoritesCount favorites',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.normal,
                color: Color(0xFF64748B),
              ),
            ),
          ],
        ),
        actions: [
          // Filter favorites toggle
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: FilterChip(
              avatar: Icon(
                _showFavoritesOnly ? Icons.star_rounded : Icons.star_outline_rounded,
                size: 18,
                color: _showFavoritesOnly ? Colors.white : const Color(0xFFF59E0B),
              ),
              label: const Text('Favorites'),
              selected: _showFavoritesOnly,
              selectedColor: const Color(0xFFF59E0B),
              labelStyle: TextStyle(
                color: _showFavoritesOnly ? Colors.white : const Color(0xFF0F172A),
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
              showCheckmark: false,
              side: BorderSide(
                color: _showFavoritesOnly ? const Color(0xFFF59E0B) : const Color(0xFFCBD5E1),
              ),
              onSelected: (selected) {
                setState(() => _showFavoritesOnly = selected);
                _refreshContacts();
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openContactForm(),
        backgroundColor: const Color(0xFF2563EB),
        foregroundColor: Colors.white,
        elevation: 3,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text(
          'Add Contact',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => _refreshContacts(),
              decoration: InputDecoration(
                hintText: 'Search contacts by name...',
                hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
                prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF64748B)),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B)),
                        onPressed: () {
                          _searchController.clear();
                          _refreshContacts();
                        },
                      )
                    : null,
              ),
            ),
          ),

          // Active filter indicator if favorites only
          if (_showFavoritesOnly)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.star_rounded, color: Color(0xFFD97706), size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Showing favorite contacts only (${_contacts.length})',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF92400E),
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () {
                      setState(() => _showFavoritesOnly = false);
                      _refreshContacts();
                    },
                    child: const Text(
                      'Clear',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFB45309),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Contact List / Empty State / Loading State
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _contacts.isEmpty
                    ? _buildEmptyState()
                    : RefreshIndicator(
                        onRefresh: _refreshContacts,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
                          itemCount: _contacts.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final contact = _contacts[index];
                            return ContactListItemCard(
                              contact: contact,
                              onTap: () => _viewContactDetails(contact),
                              onEdit: () => _openContactForm(contact),
                              onDelete: () => _confirmDeleteContact(contact),
                              onToggleFavorite: () async {
                                if (contact.id != null) {
                                  await DatabaseHelper.instance.toggleFavorite(
                                    contact.id!,
                                    contact.isFavorite,
                                  );
                                  _refreshContacts();
                                }
                              },
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  /// Empty state helper
  Widget _buildEmptyState() {
    final hasSearch = _searchController.text.trim().isNotEmpty;
    final isFav = _showFavoritesOnly;

    IconData icon;
    String title;
    String subtitle;

    if (hasSearch) {
      icon = Icons.person_search_rounded;
      title = 'No contacts found';
      subtitle = 'No contacts match "${_searchController.text.trim()}". Try another name.';
    } else if (isFav) {
      icon = Icons.star_border_rounded;
      title = 'No favorite contacts';
      subtitle = 'Tap the star icon on any contact to mark them as a favorite.';
    } else {
      icon = Icons.contact_page_outlined;
      title = 'No contacts yet';
      subtitle = 'Your address book is empty. Tap "Add Contact" to save your first contact.';
    }

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFE2E8F0),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 54, color: const Color(0xFF64748B)),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Color(0xFF64748B)),
            ),
            if (hasSearch) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () {
                  _searchController.clear();
                  _refreshContacts();
                },
                icon: const Icon(Icons.clear_rounded, size: 18),
                label: const Text('Clear Search'),
              ),
            ] else if (!isFav) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => _openContactForm(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Contact Now'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 4. CONTACT LIST ITEM CARD WIDGET
// ==========================================

class ContactListItemCard extends StatelessWidget {
  final Contact contact;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggleFavorite;

  const ContactListItemCard({
    super.key,
    required this.contact,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleFavorite,
  });

  /// Generate a consistent pleasant avatar color based on name
  Color _getAvatarColor(String name) {
    final colors = [
      const Color(0xFF3B82F6), // Blue
      const Color(0xFF10B981), // Green
      const Color(0xFF8B5CF6), // Purple
      const Color(0xFFF59E0B), // Amber
      const Color(0xFFEC4899), // Pink
      const Color(0xFF14B8A6), // Teal
      const Color(0xFF6366F1), // Indigo
      const Color(0xFFF97316), // Orange
    ];
    if (name.isEmpty) return colors[0];
    return colors[name.codeUnits.reduce((a, b) => a + b) % colors.length];
  }

  /// Get initials (e.g. "John Doe" -> "JD", "Alex" -> "A")
  String _getInitials(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return (parts[0][0] + parts[1][0]).toUpperCase();
    }
    return trimmed[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final avatarColor = _getAvatarColor(contact.name);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Avatar
              CircleAvatar(
                radius: 26,
                backgroundColor: avatarColor.withOpacity(0.15),
                child: Text(
                  _getInitials(contact.name),
                  style: TextStyle(
                    color: avatarColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
              const SizedBox(width: 14),

              // Contact Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            contact.name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0F172A),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (contact.isFavorite) ...[
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.star_rounded,
                            size: 18,
                            color: Color(0xFFF59E0B),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),

                    // Phone
                    Row(
                      children: [
                        const Icon(Icons.phone_rounded, size: 14, color: Color(0xFF64748B)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            contact.phone,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF334155),
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),

                    // Email
                    Row(
                      children: [
                        const Icon(Icons.email_outlined, size: 14, color: Color(0xFF94A3B8)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            contact.email,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF64748B),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Action Buttons
              IconButton(
                icon: Icon(
                  contact.isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: contact.isFavorite ? const Color(0xFFF59E0B) : const Color(0xFFCBD5E1),
                ),
                tooltip: contact.isFavorite ? 'Unfavorite' : 'Favorite',
                onPressed: onToggleFavorite,
              ),

              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded, color: Color(0xFF64748B)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                onSelected: (value) {
                  switch (value) {
                    case 'view':
                      onTap();
                      break;
                    case 'edit':
                      onEdit();
                      break;
                    case 'delete':
                      onDelete();
                      break;
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'view',
                    child: Row(
                      children: [
                        Icon(Icons.visibility_outlined, size: 18, color: Color(0xFF475569)),
                        SizedBox(width: 10),
                        Text('View Details'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit_outlined, size: 18, color: Color(0xFF475569)),
                        SizedBox(width: 10),
                        Text('Edit Contact'),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline_rounded, size: 18, color: Color(0xFFEF4444)),
                        SizedBox(width: 10),
                        Text('Delete', style: TextStyle(color: Color(0xFFEF4444))),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==========================================
// 5. ADD / EDIT CONTACT FORM (BOTTOM SHEET)
// ==========================================

class ContactFormSheet extends StatefulWidget {
  final Contact? contact;

  const ContactFormSheet({super.key, this.contact});

  @override
  State<ContactFormSheet> createState() => _ContactFormSheetState();
}

class _ContactFormSheetState extends State<ContactFormSheet> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;
  late final TextEditingController _addressController;
  late bool _isFavorite;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final c = widget.contact;
    _nameController = TextEditingController(text: c?.name ?? '');
    _phoneController = TextEditingController(text: c?.phone ?? '');
    _emailController = TextEditingController(text: c?.email ?? '');
    _addressController = TextEditingController(text: c?.address ?? '');
    _isFavorite = c?.isFavorite ?? false;

    // Update avatar preview dynamically on name typing
    _nameController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _saveContact() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    final contact = Contact(
      id: widget.contact?.id,
      name: _nameController.text.trim(),
      phone: _phoneController.text.trim(),
      email: _emailController.text.trim(),
      address: _addressController.text.trim(),
      isFavorite: _isFavorite,
    );

    if (widget.contact == null) {
      await DatabaseHelper.instance.insertContact(contact);
    } else {
      await DatabaseHelper.instance.updateContact(contact);
    }

    if (mounted) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.contact != null;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 12, 20, bottomInset + 20),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Drag Handle
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Title Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isEditing ? 'Edit Contact' : 'New Contact',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B)),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Avatar Preview
              Center(
                child: CircleAvatar(
                  radius: 36,
                  backgroundColor: const Color(0xFF2563EB).withOpacity(0.12),
                  child: Text(
                    _nameController.text.trim().isNotEmpty
                        ? _nameController.text.trim()[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2563EB),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Name Field
              TextFormField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Full Name *',
                  hintText: 'e.g. John Doe',
                  prefixIcon: Icon(Icons.person_rounded),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a contact name';
                  }
                  if (value.trim().length < 2) {
                    return 'Name must be at least 2 characters';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),

              // Phone Field
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone Number *',
                  hintText: 'e.g. +1 555-0199',
                  prefixIcon: Icon(Icons.phone_rounded),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a phone number';
                  }
                  if (value.trim().length < 6) {
                    return 'Enter a valid phone number';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),

              // Email Field
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email Address *',
                  hintText: 'e.g. john@example.com',
                  prefixIcon: Icon(Icons.email_rounded),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter an email address';
                  }
                  final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
                  if (!emailRegex.hasMatch(value.trim())) {
                    return 'Enter a valid email address';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),

              // Address Field
              TextFormField(
                controller: _addressController,
                maxLines: 2,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Address *',
                  hintText: 'e.g. 123 Main St, New York, NY',
                  prefixIcon: Icon(Icons.location_on_rounded),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter an address';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // Bonus: Favorite Switch
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: SwitchListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  title: const Text(
                    'Mark as Favorite',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                  subtitle: const Text(
                    'Quickly access from favorites filter',
                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                  secondary: Icon(
                    _isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: _isFavorite ? const Color(0xFFF59E0B) : const Color(0xFF94A3B8),
                  ),
                  value: _isFavorite,
                  activeColor: const Color(0xFFF59E0B),
                  onChanged: (value) => setState(() => _isFavorite = value),
                ),
              ),
              const SizedBox(height: 20),

              // Submit Button
              FilledButton(
                onPressed: _isSaving ? null : _saveContact,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isSaving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : Text(
                        isEditing ? 'Update Contact' : 'Save Contact',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==========================================
// 6. CONTACT DETAIL VIEW (BOTTOM SHEET)
// ==========================================

class ContactDetailSheet extends StatelessWidget {
  final Contact contact;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggleFavorite;

  const ContactDetailSheet({
    super.key,
    required this.contact,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleFavorite,
  });

  void _copyToClipboard(BuildContext context, String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard!'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag Handle
          Center(
            child: Container(
              width: 44,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header Avatar & Name
          CircleAvatar(
            radius: 40,
            backgroundColor: const Color(0xFF2563EB).withOpacity(0.12),
            child: Text(
              contact.name.isNotEmpty ? contact.name[0].toUpperCase() : '?',
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2563EB),
              ),
            ),
          ),
          const SizedBox(height: 12),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  contact.name,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              if (contact.isFavorite) ...[
                const SizedBox(width: 6),
                const Icon(Icons.star_rounded, color: Color(0xFFF59E0B), size: 24),
              ],
            ],
          ),
          if (contact.id != null)
            Text(
              'Contact ID: #${contact.id}',
              style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
            ),
          const SizedBox(height: 20),

          // Detail Tiles
          _buildInfoTile(
            context,
            icon: Icons.phone_rounded,
            title: 'Phone Number',
            subtitle: contact.phone,
            actionLabel: 'Copy',
            onTapAction: () => _copyToClipboard(context, contact.phone, 'Phone number'),
          ),
          const SizedBox(height: 10),
          _buildInfoTile(
            context,
            icon: Icons.email_rounded,
            title: 'Email Address',
            subtitle: contact.email,
            actionLabel: 'Copy',
            onTapAction: () => _copyToClipboard(context, contact.email, 'Email address'),
          ),
          const SizedBox(height: 10),
          _buildInfoTile(
            context,
            icon: Icons.location_on_rounded,
            title: 'Address',
            subtitle: contact.address,
            actionLabel: 'Copy',
            onTapAction: () => _copyToClipboard(context, contact.address, 'Address'),
          ),
          const SizedBox(height: 24),

          // Quick Action Bar
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onToggleFavorite,
                  icon: Icon(
                    contact.isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: const Color(0xFFF59E0B),
                  ),
                  label: Text(contact.isFavorite ? 'Unfavorite' : 'Favorite'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_rounded, size: 18),
                  label: const Text('Edit'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              IconButton.filledTonal(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444)),
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFFFEE2E2),
                  padding: const EdgeInsets.all(12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                tooltip: 'Delete Contact',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required String actionLabel,
    required VoidCallback onTapAction,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFE2E8F0),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: const Color(0xFF334155), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 14, color: Color(0xFF0F172A), fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onTapAction,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(40, 32),
            ),
            child: Text(
              actionLabel,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
