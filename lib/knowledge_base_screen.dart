import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'core/app_utils.dart';
import 'services/cloud_sync_service.dart';

class KnowledgeBaseScreen extends StatefulWidget {
  final bool isAdmin;
  const KnowledgeBaseScreen({super.key, required this.isAdmin});

  @override
  State<KnowledgeBaseScreen> createState() => _KnowledgeBaseScreenState();
}

class _KnowledgeBaseScreenState extends State<KnowledgeBaseScreen> {
  Map<String, dynamic> _data = {
    'standards': [
      {
        'title': 'Wysokości osprzętu (standard)',
        'content': '• Włączniki: 90 cm od gotowej podłogi\n• Gniazda (pokoje): 30 cm\n• Gniazda (kuchnia): 110 cm\n• Gniazda ( łazienka): 120 cm',
        'icon': 'straighten',
        'color': 'blue'
      },
      {
        'title': 'Oznakowanie przewodów',
        'content': '• Faza (L1/L2/L3): Brązowy, Czarny, Szary\n• Neutralny (N): Niebieski\n• Ochronny (PE): Żółto-zielony',
        'icon': 'palette_outlined',
        'color': 'orange'
      }
    ],
    'checklists': [
      {
        'title': 'Odbiór instalacji podtynkowej',
        'items': [
          'Brak wystających przewodów ze ścian',
          'Puszki obsadzone prosto i na odpowiedniej głębokości',
          'Przewody w peszlach w miejscach narażonych',
          'Wykonano dokumentację zdjęciową przed tynkami',
          'Ciągłość przewodów sprawdzona miernikiem'
        ],
        'color': 'green'
      },
      {
        'title': 'Montaż Rozdzielni (Finalny)',
        'items': [
          'Wszystkie obwody opisane w rozdzielni',
          'Zastosowano odpowiednie momenty dokręcania (2.5Nm)',
          'Wykonano pomiar pętli zwarcia i RCD',
          'Pozostawiono schemat wewnątrz rozdzielni',
          'Porządek wewnątrz i na zewnątrz szafy'
        ],
        'color': 'indigo'
      }
    ],
    'info_cards': [
      {
        'title': 'Norma PN-HD 60364-6',
        'subtitle': 'Wymagania dotyczące sprawdzania odbiorczego i okresowego instalacji elektrycznych.',
        'icon': 'menu_book'
      }
    ]
  };

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    await CloudSyncService().downloadKnowledgeBase();
    final String? stored = prefs.getString('knowledge_base_data_v1');
    if (stored != null) {
      setState(() {
        _data = json.decode(stored);
        _isLoading = false;
      });
    } else {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('knowledge_base_data_v1', AppUtils.safeJsonEncode(_data));
    if (widget.isAdmin) {
      await CloudSyncService().uploadKnowledgeBase();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('STANDARD FIRMOWY'),
        backgroundColor: const Color(0xFF001A2C),
        foregroundColor: Colors.white,
        actions: [
          if (widget.isAdmin) IconButton(icon: const Icon(Icons.sync), onPressed: _loadData)
        ],
      ),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF007BFF))) 
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionHeader('📌 STANDARDY MONTAŻU'),
                  ...(_data['standards'] as List).asMap().entries.map((e) => _buildStandardTile(
                    context, 
                    e.value['title'], 
                    e.value['content'], 
                    _getIcon(e.value['icon']), 
                    _getColor(e.value['color']),
                    index: e.key
                  )),
                  if (widget.isAdmin) _addButton(() => _editStandard(null)),
                  
                  const SizedBox(height: 20),
                  _buildSectionHeader('✅ CHECKLISTY'),
                  ...(_data['checklists'] as List).asMap().entries.map((e) => _buildChecklistTile(
                    context, 
                    e.value['title'], 
                    List<String>.from(e.value['items']), 
                    _getColor(e.value['color']),
                    index: e.key
                  )),
                  if (widget.isAdmin) _addButton(() => _editChecklist(null)),

                  const SizedBox(height: 20),
                  _buildSectionHeader('📖 DOKUMENTACJA PN-EN'),
                  ...(_data['info_cards'] as List).asMap().entries.map((e) => _buildInfoCard(
                    e.value['title'], 
                    e.value['subtitle'], 
                    _getIcon(e.value['icon']),
                    index: e.key
                  )),
                  if (widget.isAdmin) _addButton(() => _editInfoCard(null)),
                ],
              ),
            ),
    );
  }

  Widget _addButton(VoidCallback onTap) {
    return Center(
      child: TextButton.icon(onPressed: onTap, icon: const Icon(Icons.add), label: const Text('DODAJ NOWY ELEMENT')),
    );
  }

  Widget _buildSectionHeader(String title) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Text(
        title,
        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 1, color: theme.colorScheme.onSurface.withOpacity(0.4)),
      ),
    );
  }

  Widget _buildStandardTile(BuildContext context, String title, String content, IconData icon, Color color, {required int index}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(20),
        boxShadow: isDark ? null : [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10)],
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: theme.colorScheme.onSurface)),
                    if (widget.isAdmin) Row(children: [
                      IconButton(icon: Icon(Icons.edit, size: 16, color: theme.colorScheme.onSurface.withOpacity(0.3)), onPressed: () => _editStandard(index)),
                      IconButton(icon: const Icon(Icons.delete, size: 16, color: Colors.redAccent), onPressed: () => _delete('standards', index)),
                    ])
                  ],
                ),
                const SizedBox(height: 8),
                Text(content, style: TextStyle(fontSize: 12, height: 1.5, color: theme.colorScheme.onSurface.withOpacity(0.7))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChecklistTile(BuildContext context, String title, List<String> items, Color color, {required int index}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: theme.cardTheme.color,
          borderRadius: BorderRadius.circular(20),
          boxShadow: isDark ? null : [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10)],
          border: Border.all(color: theme.dividerTheme.color ?? Colors.white10),
        ),
        child: ExpansionTile(
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: theme.colorScheme.onSurface)),
              if (widget.isAdmin) Row(children: [
                IconButton(icon: Icon(Icons.edit, size: 16, color: theme.colorScheme.onSurface.withOpacity(0.3)), onPressed: () => _editChecklist(index)),
                IconButton(icon: const Icon(Icons.delete, size: 16, color: Colors.redAccent), onPressed: () => _delete('checklists', index)),
              ])
            ],
          ),
          leading: Icon(Icons.check_circle_outline, color: color),
          children: items.map((item) => ListTile(
            leading: const Icon(Icons.check, size: 16, color: Colors.green),
            title: Text(item, style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.7))),
            dense: true,
          )).toList(),
        ),
      ),
    );
  }

  Widget _buildInfoCard(String title, String subtitle, IconData icon, {required int index}) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [const Color(0xFF001A2C), theme.colorScheme.primary.withOpacity(0.8)]),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 30),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    if (widget.isAdmin) Row(children: [
                      IconButton(icon: const Icon(Icons.edit, size: 16, color: Colors.white), onPressed: () => _editInfoCard(index)),
                      IconButton(icon: const Icon(Icons.delete, size: 16, color: Colors.redAccent), onPressed: () => _delete('info_cards', index)),
                    ])
                  ],
                ),
                Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _delete(String key, int index) {
    setState(() {
      _data[key].removeAt(index);
    });
    _saveData();
  }

  void _editStandard(int? index) {
    final tC = TextEditingController(text: index != null ? _data['standards'][index]['title'] : '');
    final cC = TextEditingController(text: index != null ? _data['standards'][index]['content'] : '');
    showDialog(context: context, builder: (c) => AlertDialog(
      title: Text(index == null ? 'DODAJ STANDARD' : 'EDYTUJ STANDARD'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: tC, decoration: const InputDecoration(labelText: 'Tytuł')),
        TextField(controller: cC, decoration: const InputDecoration(labelText: 'Treść'), maxLines: 5),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('ANULUJ')),
        ElevatedButton(onPressed: () {
          setState(() {
            final item = {'title': tC.text, 'content': cC.text, 'icon': 'straighten', 'color': 'blue'};
            if (index == null) _data['standards'].add(item); else _data['standards'][index] = item;
          });
          _saveData(); Navigator.pop(c);
        }, child: const Text('ZAPISZ'))
      ],
    ));
  }

  void _editChecklist(int? index) {
    final tC = TextEditingController(text: index != null ? _data['checklists'][index]['title'] : '');
    List<String> items = index != null ? List<String>.from(_data['checklists'][index]['items']) : [];
    showDialog(context: context, builder: (c) => StatefulBuilder(builder: (c, setDS) => AlertDialog(
      title: Text(index == null ? 'DODAJ CHECKLISTĘ' : 'EDYTUJ CHECKLISTĘ'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: tC, decoration: const InputDecoration(labelText: 'Tytuł')),
        const Divider(),
        ...items.asMap().entries.map((e) => Row(children: [
          Expanded(child: TextField(
            controller: TextEditingController(text: e.value)..selection = TextSelection.collapsed(offset: e.value.length),
            onChanged: (v) => items[e.key] = v,
            decoration: const InputDecoration(hintText: 'Punkt listy'),
          )),
          IconButton(icon: const Icon(Icons.remove_circle, color: Colors.red), onPressed: () => setDS(() => items.removeAt(e.key)))
        ])),
        TextButton.icon(onPressed: () => setDS(() => items.add('')), icon: const Icon(Icons.add), label: const Text('DODAJ PUNKT'))
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('ANULUJ')),
        ElevatedButton(onPressed: () {
          setState(() {
            final item = {'title': tC.text, 'items': items, 'color': 'indigo'};
            if (index == null) _data['checklists'].add(item); else _data['checklists'][index] = item;
          });
          _saveData(); Navigator.pop(c);
        }, child: const Text('ZAPISZ'))
      ],
    )));
  }

  void _editInfoCard(int? index) {
    final tC = TextEditingController(text: index != null ? _data['info_cards'][index]['title'] : '');
    final sC = TextEditingController(text: index != null ? _data['info_cards'][index]['subtitle'] : '');
    showDialog(context: context, builder: (c) => AlertDialog(
      title: Text(index == null ? 'DODAJ KARTĘ' : 'EDYTUJ KARTĘ'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: tC, decoration: const InputDecoration(labelText: 'Tytuł')),
        TextField(controller: sC, decoration: const InputDecoration(labelText: 'Podtytuł'), maxLines: 3),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('ANULUJ')),
        ElevatedButton(onPressed: () {
          setState(() {
            final item = {'title': tC.text, 'subtitle': sC.text, 'icon': 'menu_book'};
            if (index == null) _data['info_cards'].add(item); else _data['info_cards'][index] = item;
          });
          _saveData(); Navigator.pop(c);
        }, child: const Text('ZAPISZ'))
      ],
    ));
  }

  IconData _getIcon(String key) {
    switch (key) {
      case 'straighten': return Icons.straighten;
      case 'palette_outlined': return Icons.palette_outlined;
      case 'menu_book': return Icons.menu_book;
      default: return Icons.info_outline;
    }
  }

  Color _getColor(String key) {
    switch (key) {
      case 'blue': return Colors.blue;
      case 'orange': return Colors.orange;
      case 'green': return Colors.green;
      case 'indigo': return Colors.indigo;
      default: return Colors.blueGrey;
    }
  }
}
