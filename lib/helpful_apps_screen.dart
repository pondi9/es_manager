import 'package:flutter/material.dart';
import 'tools/flashlight_screen.dart';
import 'tools/lux_meter_screen.dart';
import 'tools/cable_calculator_screen.dart';
import 'tools/db_labels_screen.dart';
import 'tools/schematic_creator_screen.dart';
import 'tools/nfc_tag_screen.dart';
import 'tools/switchboard_visualizer_screen.dart';
import 'tools/lan_labels_screen.dart';
import 'tools/label_designer_screen.dart';
import 'tools/installation_documentation_screen.dart';

class HelpfulAppsScreen extends StatelessWidget {
  const HelpfulAppsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('POMOCNE NARZĘDZIA'),
        backgroundColor: const Color(0xFF001A2C),
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: GridView.count(
          crossAxisCount: MediaQuery.of(context).size.width > 1200 ? 6 : (MediaQuery.of(context).size.width > 800 ? 4 : 2),
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          children: [
            _buildToolTile(
              context,
              title: 'LATARKA',
              icon: Icons.flashlight_on,
              color: Colors.amber[700]!,
              screen: const FlashlightScreen(),
            ),
            _buildToolTile(
              context,
              title: 'LUKSOMIERZ',
              icon: Icons.light_mode,
              color: Colors.blue[700]!,
              screen: const LuxMeterScreen(),
            ),
            _buildToolTile(
              context,
              title: 'DOBÓR PRZEWODU',
              icon: Icons.electrical_services,
              color: Colors.deepOrange[700]!,
              screen: const CableCalculatorScreen(),
            ),
            _buildToolTile(
              context,
              title: 'OPISY ROZDZIELNI',
              icon: Icons.label_important_outline,
              color: Colors.blueGrey[700]!,
              screen: const DbLabelsScreen(),
            ),
            _buildToolTile(
              context,
              title: 'KREATOR SCHEMATÓW',
              icon: Icons.schema_outlined,
              color: Colors.indigo[700]!,
              screen: const SchematicCreatorScreen(),
            ),
            _buildToolTile(
              context,
              title: 'CZYTNIK NFC / TAGI',
              icon: Icons.nfc,
              color: Colors.teal[700]!,
              screen: const NfcTagScreen(),
            ),
            _buildToolTile(
              context,
              title: 'WIZUALIZACJA ROZDZIELNI',
              icon: Icons.view_quilt_outlined,
              color: Colors.deepPurple[700]!,
              screen: const SwitchboardVisualizerScreen(),
            ),
            _buildToolTile(
              context,
              title: 'OPISY LAN',
              icon: Icons.lan,
              color: Colors.teal[800]!,
              screen: const LanLabelsScreen(),
            ),
            _buildToolTile(
              context,
              title: 'DRUKARKA ETYKIET',
              icon: Icons.print_outlined,
              color: Colors.blueGrey[800]!,
              screen: const LabelDesignerScreen(),
            ),
            _buildToolTile(
              context,
              title: 'ZDJĘCIA PODTYNKOWE',
              icon: Icons.photo_library_outlined,
              color: Colors.teal[600]!,
              screen: const InstallationDocumentationScreen(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolTile(BuildContext context, {required String title, required IconData icon, required Color color, required Widget screen}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => screen)),
      child: Container(
        decoration: BoxDecoration(
          color: theme.cardTheme.color,
          borderRadius: BorderRadius.circular(25),
          boxShadow: isDark ? null : [
            BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4)),
          ],
          border: Border.all(color: theme.colorScheme.outline.withOpacity(0.1)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 30, color: color),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 11,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
