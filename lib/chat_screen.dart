import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';
import 'core/app_theme.dart';
import 'core/app_constants.dart';

class ChatScreen extends StatefulWidget {
  final String currentUserEmail;
  final String displayName;
  final String? initialTargetEmail;
  final bool isClient;
  final String? initialMessage;
  final bool employeesOnly;

  const ChatScreen({
    super.key, 
    required this.currentUserEmail, 
    required this.displayName,
    this.initialTargetEmail,
    this.isClient = false,
    this.initialMessage,
    this.employeesOnly = false,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  
  String? _selectedUserEmail; 
  String? _selectedUserName;
  String? _selectedCrewName;
  bool _showEmojis = false;
  String _searchQuery = "";
  List<String> _crews = ['Ekipa 1', 'Ekipa 2', 'Stadion', 'Biuro'];

  final List<String> _commonEmojis = ["👍", "👌", "🔥", "⚡", "⚠️", "✅", "🚧", "🛠️", "💪", "😊", "😀", "👋"];

  @override
  void initState() {
    super.initState();
    _loadCrews();
    if (widget.initialTargetEmail != null) {
      _selectedUserEmail = widget.initialTargetEmail;
      _fetchInitialTargetName();
      _markAsRead(_selectedUserEmail!);
    } else if (widget.isClient) {
      _selectedUserEmail = AppConstants.adminEmail;
      _fetchInitialTargetName();
      _markAsRead(_selectedUserEmail!);
    }

    if (widget.initialMessage != null) {
      _messageController.text = widget.initialMessage!;
    }
  }

  Future<void> _fetchInitialTargetName() async {
    if (_selectedUserEmail == null) return;
    if (_selectedUserEmail == AppConstants.adminEmail) {
      setState(() => _selectedUserName = "Marcin Kiczek (Administrator)");
      return;
    }
    try {
      final snap = await FirebaseFirestore.instance.collection('employees').doc(_selectedUserEmail).get();
      if (snap.exists) {
        final d = snap.data();
        setState(() => _selectedUserName = "${d?['firstName'] ?? ''} ${d?['lastName'] ?? ''}".trim());
      }
    } catch (_) {}
  }

  Future<void> _loadCrews() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedCrews = prefs.getStringList('job_groups');
      if (savedCrews != null && savedCrews.isNotEmpty) {
        setState(() => _crews = savedCrews);
      }
    } catch (_) {}
  }

  void _sendMessage({String? text, String? imageUrl, String? fileUrl, String? fileName}) async {
    final msgText = text ?? _messageController.text.trim();
    if (msgText.isEmpty && imageUrl == null && fileUrl == null) return;

    final message = {
      'senderEmail': widget.currentUserEmail,
      'senderName': widget.displayName,
      'receiverEmail': _selectedUserEmail, 
      'crewName': _selectedCrewName,
      'text': msgText,
      'imageUrl': imageUrl,
      'fileUrl': fileUrl,
      'fileName': fileName,
      'timestamp': FieldValue.serverTimestamp(),
      'date': DateFormat('dd.MM HH:mm').format(DateTime.now()),
    };

    String collectionPath = 'internal_chat'; // Default
    if (_selectedCrewName != null) {
      collectionPath = 'crew_chats';
      message['roomId'] = _selectedCrewName;
    } else if (_selectedUserEmail != null) {
      collectionPath = 'private_messages';
      List<String> ids = [widget.currentUserEmail.toLowerCase(), _selectedUserEmail!.toLowerCase()];
      ids.sort();
      message['roomId'] = ids.join('_');
    }

    _messageController.clear();
    setState(() => _showEmojis = false);
    await FirebaseFirestore.instance.collection(collectionPath).add(message);
    
    // AUTOMATYCZNE POWIADOMIENIE (ALERTY)
    String target = _selectedCrewName != null ? 'group:$_selectedCrewName' : (_selectedUserEmail ?? 'all');
    if (target == AppConstants.adminEmail) target = 'admin';

    await FirebaseFirestore.instance.collection('notifications').add({
      'title': _selectedCrewName != null ? 'WIADOMOŚĆ DLA EKIPY' : 'NOWA WIADOMOŚĆ',
      'content': '${widget.displayName}: ${msgText.length > 30 ? msgText.substring(0, 30) + "..." : msgText}',
      'date': DateFormat('dd.MM HH:mm').format(DateTime.now()),
      'target': target,
      'isRead': false,
      'author': widget.displayName,
      'senderEmail': widget.currentUserEmail,
      'timestamp': FieldValue.serverTimestamp(),
    });

    _scrollToBottom();
  }

  Future<void> _pickImage() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    if (result != null && result.files.isNotEmpty) {
      _uploadAndSend(result.files.first, isImage: true);
    }
  }

  Future<void> _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(withData: true);
    if (result != null && result.files.isNotEmpty) {
      _uploadAndSend(result.files.first, isImage: false);
    }
  }

  Future<void> _uploadAndSend(PlatformFile file, {required bool isImage}) async {
    showDialog(context: context, barrierDismissible: false, builder: (c) => const Center(child: CircularProgressIndicator(color: Color(0xFF007BFF))));
    try {
      final bytes = file.bytes;
      if (bytes == null) throw "Błąd odczytu pliku";
      final ref = FirebaseStorage.instance.ref().child('chat/${DateTime.now().millisecondsSinceEpoch}_${file.name}');
      await ref.putData(bytes);
      final url = await ref.getDownloadURL();
      if (mounted) Navigator.pop(context);
      if (isImage) _sendMessage(imageUrl: url); else _sendMessage(fileUrl: url, fileName: file.name);
    } catch (e) {
      if (mounted) {
        if (Navigator.canPop(context)) Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Błąd: $e"), backgroundColor: Colors.red));
      }
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(0.0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isDesktop = MediaQuery.of(context).size.width > 900;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Row(
        children: [
          if (isDesktop && !widget.isClient) _buildSidePanel(),
          Expanded(
            child: Column(
              children: [
                _buildChatHeader(isDesktop),
                Expanded(child: _buildMessagesStream()),
                if (_showEmojis) _buildEmojiPicker(),
                _buildInputArea(),
              ],
            ),
          ),
        ],
      ),
      drawer: (!isDesktop && !widget.isClient) ? Drawer(width: 320, backgroundColor: theme.appBarTheme.backgroundColor, child: _buildSidePanel()) : null,
    );
  }

  Widget _buildChatHeader(bool isDesktop) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: theme.appBarTheme.backgroundColor,
        border: Border(bottom: BorderSide(color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05))),
      ),
      child: Row(
        children: [
          if (!isDesktop && !widget.isClient) 
            IconButton(icon: const Icon(Icons.menu, color: Colors.white70), onPressed: () => _scaffoldKey.currentState?.openDrawer()),
          
          CircleAvatar(
            radius: 18,
            backgroundColor: const Color(0xFF007BFF).withOpacity(0.1),
            child: Icon(
              _selectedCrewName != null 
                ? Icons.group_work_rounded 
                : (_selectedUserEmail == null ? Icons.groups_rounded : Icons.person_rounded), 
              color: const Color(0xFF007BFF), 
              size: 20
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _selectedCrewName != null 
                    ? "CZAT EKIPY: ${_selectedCrewName!.toUpperCase()}" 
                    : (_selectedUserEmail == null ? "CZAT OGÓLNY ZESPOŁU" : (_selectedUserName ?? _selectedUserEmail!)),
                  style: GoogleFonts.montserrat(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14),
                ),
                Text(
                  _selectedCrewName != null 
                    ? "Komunikacja międzyekipowa" 
                    : (_selectedUserEmail == null ? "Wszyscy pracownicy" : "Rozmowa prywatna"),
                  style: GoogleFonts.montserrat(color: Colors.white.withOpacity(0.3), fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                ),
              ],
            ),
          ),
          if (_selectedUserEmail != null || _selectedCrewName != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.green.withOpacity(0.3))),
              child: Row(
                children: [
                  Container(width: 6, height: 6, decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                  const Text("AKTYWNY", style: TextStyle(color: Colors.green, fontSize: 8, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSidePanel() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      width: 320,
      decoration: BoxDecoration(
        color: theme.appBarTheme.backgroundColor,
        border: Border(right: BorderSide(color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05))),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("WIADOMOŚCI", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
                const SizedBox(height: 16),
                TextField(
                  onChanged: (v) => setState(() => _searchQuery = v),
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: "Szukaj osoby...",
                    hintStyle: const TextStyle(color: Colors.white24),
                    prefixIcon: const Icon(Icons.search, color: Colors.white24, size: 18),
                    filled: true, fillColor: Colors.white.withOpacity(0.03),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ),
          _buildPublicChatTile(),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Row(
              children: [
                Text("EKIPY", style: TextStyle(color: Colors.white24, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                Spacer(),
              ],
            ),
          ),
          ..._crews.map((c) => _buildCrewChatTile(c)).toList(),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Row(
              children: [
                Text("KONTAKTY", style: TextStyle(color: Colors.white24, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                Spacer(),
                Icon(Icons.unfold_more_rounded, color: Colors.white24, size: 14),
              ],
            ),
          ),
          Expanded(child: _buildUserList()),
        ],
      ),
    );
  }

  Widget _buildCrewChatTile(String crewName) {
    bool active = _selectedCrewName == crewName;
    return InkWell(
      onTap: () {
        setState(() { _selectedCrewName = crewName; _selectedUserEmail = null; _selectedUserName = null; });
        _markCrewAsRead(crewName);
        if (MediaQuery.of(context).size.width < 900) {
           if (_scaffoldKey.currentState?.isDrawerOpen ?? false) Navigator.pop(context);
        }
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF007BFF).withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: active ? Border.all(color: const Color(0xFF007BFF).withOpacity(0.3)) : null,
        ),
        child: Row(
          children: [
            CircleAvatar(backgroundColor: Colors.blueGrey[800], radius: 14, child: const Icon(Icons.group_work_rounded, color: Colors.white, size: 14)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(crewName, style: TextStyle(color: active ? Colors.white : Colors.white60, fontWeight: active ? FontWeight.bold : FontWeight.normal, fontSize: 12)),
            ),
            if (active) const Icon(Icons.circle, color: Color(0xFF007BFF), size: 6),
          ],
        ),
      ),
    );
  }

  Widget _buildPublicChatTile() {
    bool active = _selectedUserEmail == null && _selectedCrewName == null;
    return InkWell(
      onTap: () {
        setState(() { _selectedUserEmail = null; _selectedUserName = null; _selectedCrewName = null; });
        if (!MediaQuery.of(context).size.width.isFinite || MediaQuery.of(context).size.width < 900) {
           if (_scaffoldKey.currentState?.isDrawerOpen ?? false) Navigator.pop(context);
        }
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF007BFF).withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: active ? Border.all(color: const Color(0xFF007BFF).withOpacity(0.3)) : null,
        ),
        child: Row(
          children: [
            const CircleAvatar(backgroundColor: Colors.orange, radius: 18, child: Icon(Icons.groups_rounded, color: Colors.white, size: 20)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("CZAT OGÓLNY", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                  Text("Komunikacja zespołowa", style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 10)),
                ],
              ),
            ),
            if (active) const Icon(Icons.chevron_right_rounded, color: Color(0xFF007BFF), size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildUserList() {
    String myTarget = widget.currentUserEmail;
    if (myTarget.toLowerCase() == AppConstants.adminEmail.toLowerCase()) myTarget = 'admin';

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('notifications')
        .where('target', isEqualTo: myTarget)
        .where('isRead', isEqualTo: false)
        .where('title', isEqualTo: 'NOWA WIADOMOŚĆ')
        .snapshots(),
      builder: (context, notifSnapshot) {
        Map<String, int> unreadCounts = {};
        if (notifSnapshot.hasData) {
          for (var doc in notifSnapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            String sender = (data['senderEmail'] ?? "").toString().toLowerCase();
            if (sender.isNotEmpty) {
              unreadCounts[sender] = (unreadCounts[sender] ?? 0) + 1;
            }
          }
        }

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('employees').snapshots(),
          builder: (context, employeesSnapshot) {
            if (!employeesSnapshot.hasData) return const SizedBox();
            
            return StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('orders').snapshots(),
              builder: (context, ordersSnapshot) {
                final List<Map<String, dynamic>> rawUsers = employeesSnapshot.data!.docs
                  .map((doc) => doc.data() as Map<String, dynamic>)
                  .toList();

                final List<Map<String, dynamic>> users = rawUsers.where((u) {
                   String mail = (u['email'] ?? "").toString().toLowerCase();
                   String pos = (u['position'] ?? "").toString().toLowerCase();
                   
                   // Filter: Employees only mode
                   if (widget.employeesOnly) {
                     if (mail == AppConstants.adminEmail.toLowerCase() || pos.contains('kierownik')) return false;
                   }

                   bool match = mail.contains(_searchQuery.toLowerCase()) || 
                                "${u['firstName']} ${u['lastName']}".toLowerCase().contains(_searchQuery.toLowerCase());
                   return (mail.isNotEmpty && mail.contains('@') || mail == AppConstants.adminEmail) && match;
                }).toList();

                if (!widget.employeesOnly) {
                  bool adminFound = users.any((u) => u['email'] == AppConstants.adminEmail);
                  if (!adminFound && "Marcin Kiczek".toLowerCase().contains(_searchQuery.toLowerCase())) {
                    users.add({'email': AppConstants.adminEmail, 'firstName': 'Marcin', 'lastName': 'Kiczek', 'isOnline': false});
                  }
                }

                if (ordersSnapshot.hasData && !widget.employeesOnly) {
                  for (var doc in ordersSnapshot.data!.docs) {
                    final data = doc.data() as Map<String, dynamic>;
                    if ((data['name'] ?? "").toString().toLowerCase().contains(_searchQuery.toLowerCase())) {
                       if (!users.any((u) => u['email'] == doc.id)) {
                          users.add({'email': doc.id, 'firstName': 'KLIENT:', 'lastName': data['name'], 'isOnline': false, 'isClient': true});
                       }
                    }
                  }
                }

                users.sort((a, b) {
                  if (a['email'] == AppConstants.adminEmail) return -1;
                  if (b['email'] == AppConstants.adminEmail) return 1;
                  bool aClient = a['isClient'] == true;
                  bool bClient = b['isClient'] == true;
                  if (aClient != bClient) return aClient ? -1 : 1;
                  return (a['isOnline'] == true ? 0 : 1).compareTo(b['isOnline'] == true ? 0 : 1);
                });

                return ListView.builder(
                  itemCount: users.length,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemBuilder: (context, index) {
                    final user = users[index];
                    String email = user['email'].toString().toLowerCase();
                    if (email == widget.currentUserEmail.toLowerCase()) return const SizedBox();
                    
                    bool active = _selectedUserEmail == email;
                    bool isClient = user['isClient'] == true;
                    String displayName = "${user['firstName'] ?? ''} ${user['lastName'] ?? ''}".trim();
                    if (displayName.isEmpty) displayName = email;
                    if (email == AppConstants.adminEmail) displayName = "Marcin Kiczek (Administrator)";

                    int unread = unreadCounts[email] ?? 0;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 4),
                      decoration: BoxDecoration(
                        color: active ? const Color(0xFF007BFF).withOpacity(0.1) : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        onTap: () {
                          setState(() { _selectedUserEmail = email; _selectedUserName = displayName; _selectedCrewName = null; });
                          _markAsRead(email);
                          if (MediaQuery.of(context).size.width < 900) Navigator.pop(context);
                        },
                        dense: true,
                        leading: Stack(
                          children: [
                            CircleAvatar(
                              radius: 16,
                              backgroundColor: isClient ? Colors.blue.withOpacity(0.2) : Colors.white.withOpacity(0.05),
                              child: Icon(isClient ? Icons.apartment_rounded : Icons.person_rounded, size: 16, color: isClient ? Colors.blue : Colors.white38),
                            ),
                            if (unread > 0)
                              Positioned(
                                right: 0, top: 0,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                                  child: Text("$unread", style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
                                ),
                              ),
                          ],
                        ),
                        title: Text(displayName, style: TextStyle(color: active ? Colors.white : Colors.white70, fontWeight: active ? FontWeight.w900 : FontWeight.w600, fontSize: 13)),
                        subtitle: Text(isClient ? "Zlecenie / Klient" : (user['isOnline'] == true ? "Dostępny" : "Niedostępny"), style: TextStyle(color: user['isOnline'] == true ? Colors.green : Colors.white12, fontSize: 9)),
                        trailing: active ? const Icon(Icons.circle, color: Color(0xFF007BFF), size: 8) : null,
                      ),
                    );
                  },
                );
              }
            );
          },
        );
      }
    );
  }

  void _markAsRead(String senderEmail) async {
    String myTarget = widget.currentUserEmail;
    if (myTarget.toLowerCase() == AppConstants.adminEmail.toLowerCase()) myTarget = 'admin';

    final snaps = await FirebaseFirestore.instance.collection('notifications')
      .where('target', isEqualTo: myTarget)
      .where('senderEmail', isEqualTo: senderEmail)
      .where('isRead', isEqualTo: false)
      .get();

    for (var doc in snaps.docs) {
      await doc.reference.update({'isRead': true});
    }
  }

  void _markCrewAsRead(String crewName) async {
    final snaps = await FirebaseFirestore.instance.collection('notifications')
      .where('target', isEqualTo: 'group:$crewName')
      .where('isRead', isEqualTo: false)
      .get();

    for (var doc in snaps.docs) {
      await doc.reference.update({'isRead': true});
    }
  }

  Widget _buildMessagesStream() {
    Query query;
    if (_selectedCrewName != null) {
      query = FirebaseFirestore.instance.collection('crew_chats').where('roomId', isEqualTo: _selectedCrewName);
    } else if (_selectedUserEmail == null) {
      query = FirebaseFirestore.instance.collection('internal_chat').orderBy('timestamp', descending: true).limit(50);
    } else {
      List<String> ids = [widget.currentUserEmail.toLowerCase(), _selectedUserEmail!.toLowerCase()];
      ids.sort();
      query = FirebaseFirestore.instance.collection('private_messages').where('roomId', isEqualTo: ids.join('_'));
    }

    final theme = Theme.of(context);
    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text("Błąd czatu: ${snapshot.error}", style: const TextStyle(color: Colors.red, fontSize: 10)));
        }
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Color(0xFF007BFF)));
        
        final docs = snapshot.data!.docs.toList();
        // Sort manually to avoid requirement for composite indexes in Firestore
        docs.sort((a, b) {
          final d1 = a.data() as Map<String, dynamic>;
          final d2 = b.data() as Map<String, dynamic>;
          Timestamp t1 = d1['timestamp'] ?? Timestamp.now();
          Timestamp t2 = d2['timestamp'] ?? Timestamp.now();
          return t2.compareTo(t1);
        });

        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.chat_bubble_outline_rounded, size: 64, color: theme.colorScheme.onSurface.withOpacity(0.05)),
                const SizedBox(height: 16),
                Text("Brak wiadomości. Rozpocznij rozmowę!", style: GoogleFonts.montserrat(color: theme.colorScheme.onSurface.withOpacity(0.1), fontSize: 14, fontWeight: FontWeight.w600)),
              ],
            ),
          );
        }

        return ListView.builder(
          controller: _scrollController, reverse: true, padding: const EdgeInsets.all(24),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            return _buildMessageBubble(data, data['senderEmail'].toString().toLowerCase() == widget.currentUserEmail.toLowerCase());
          },
        );
      },
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> data, bool isMe) {
    String senderEmail = data['senderEmail']?.toString().toLowerCase() ?? "";
    bool isAdmin = senderEmail == AppConstants.adminEmail.toLowerCase();
    bool isClientSender = data['isClient'] == true || (widget.isClient && isMe);
    
    String role = "PRACOWNIK";
    IconData roleIcon = Icons.engineering_rounded;
    Color roleCol = const Color(0xFF007BFF);

    if (isAdmin) {
      role = "ADMIN / KIEROWNIK";
      roleIcon = Icons.shield_rounded;
      roleCol = Colors.orange;
    } else if (isClientSender) {
      role = "INWESTOR";
      roleIcon = Icons.person_rounded;
      roleCol = Colors.greenAccent;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * (MediaQuery.of(context).size.width > 1200 ? 0.35 : 0.75)),
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Column(
                crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!isMe) Icon(roleIcon, size: 12, color: roleCol),
                      const SizedBox(width: 6),
                      Text(
                        data['senderName'] ?? (isMe ? "Ty" : "Użytkownik"), 
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87, 
                          fontSize: 11, 
                          fontWeight: FontWeight.w900
                        )
                      ),
                      if (isMe) ...[
                        const SizedBox(width: 6),
                        Icon(roleIcon, size: 12, color: roleCol),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: roleCol.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      role, 
                      style: TextStyle(
                        color: roleCol, 
                        fontSize: 7, 
                        fontWeight: FontWeight.w900, 
                        letterSpacing: 1.0
                      )
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isMe ? const Color(0xFF007BFF) : (isDark ? const Color(0xFF001A2C) : Colors.white),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(20), 
                  topRight: const Radius.circular(20), 
                  bottomLeft: Radius.circular(isMe ? 20 : 4), 
                  bottomRight: Radius.circular(isMe ? 4 : 20)
                ),
                border: isMe ? null : Border.all(color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05)),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (data['imageUrl'] != null)
                    GestureDetector(
                      onTap: () => _showPhotoPreview(data['imageUrl']),
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 8), 
                        child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.network(data['imageUrl'], fit: BoxFit.cover))
                      ),
                    ),
                  if (data['fileUrl'] != null)
                    InkWell(
                      onTap: () => launchUrl(Uri.parse(data['fileUrl'])),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(10), 
                        decoration: BoxDecoration(color: Colors.black.withOpacity(isDark ? 0.2 : 0.05), borderRadius: BorderRadius.circular(12)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min, 
                          children: [
                            Icon(Icons.insert_drive_file_rounded, size: 18, color: isDark ? Colors.white70 : Colors.black54), 
                            const SizedBox(width: 10), 
                            Flexible(child: Text(data['fileName'] ?? "Plik", style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 11, fontWeight: FontWeight.bold, decoration: TextDecoration.underline)))
                          ]
                        ),
                      ),
                    ),
                  if (data['text'] != null && data['text'].toString().isNotEmpty)
                    Text(data['text'], style: GoogleFonts.inter(color: isMe ? Colors.white : (isDark ? Colors.white : Colors.black87), fontSize: 13, height: 1.4)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 8, right: 8),
              child: Text(data['date'] ?? "", style: TextStyle(color: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.1), fontSize: 8, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _showPhotoPreview(String url) {
    showDialog(context: context, builder: (c) => Dialog(
      backgroundColor: Colors.transparent, 
      child: Column(
        mainAxisSize: MainAxisSize.min, 
        children: [ 
          ClipRRect(borderRadius: BorderRadius.circular(24), child: Image.network(url)), 
          const SizedBox(height: 12),
          IconButton(onPressed: () => Navigator.pop(c), icon: const Icon(Icons.close_rounded, color: Colors.white, size: 40)) 
        ]
      )
    ));
  }

  Widget _buildEmojiPicker() {
    final theme = Theme.of(context);
    return Container(
      height: 60, 
      color: theme.appBarTheme.backgroundColor,
      child: ListView.builder(
        scrollDirection: Axis.horizontal, 
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _commonEmojis.length,
        itemBuilder: (context, i) => InkWell(
          onTap: () => setState(() => _messageController.text += _commonEmojis[i]),
          child: Padding(padding: const EdgeInsets.all(16), child: Text(_commonEmojis[i], style: const TextStyle(fontSize: 22))),
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      decoration: BoxDecoration(
        color: theme.appBarTheme.backgroundColor,
        border: Border(top: BorderSide(color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05))),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => setState(() => _showEmojis = !_showEmojis), 
            icon: Icon(_showEmojis ? Icons.emoji_emotions : Icons.emoji_emotions_outlined, color: const Color(0xFF007BFF))
          ),
          IconButton(onPressed: _pickImage, icon: Icon(Icons.image_rounded, color: isDark ? Colors.white24 : Colors.black26)),
          IconButton(onPressed: _pickFile, icon: Icon(Icons.attach_file_rounded, color: isDark ? Colors.white24 : Colors.black26)),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _messageController,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: "Napisz wiadomość...", 
                hintStyle: TextStyle(color: isDark ? Colors.white10 : Colors.white30),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none), 
                filled: true, fillColor: Colors.white.withOpacity(0.03), 
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)
              ),
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 12),
          Material(
            color: const Color(0xFF007BFF),
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              onTap: _sendMessage,
              borderRadius: BorderRadius.circular(16),
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Icon(Icons.send_rounded, color: Colors.white, size: 22),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
