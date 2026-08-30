import 'package:flutter/material.dart';
import '../services/theme_service.dart';
import 'package:google_fonts/google_fonts.dart';

class ThemeSwitcher extends StatelessWidget {
  const ThemeSwitcher({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeService().themeModeNotifier,
      builder: (context, currentMode, _) {
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        
        return PopupMenuButton<ThemeMode>(
          icon: Icon(
            _getIconForMode(currentMode),
            color: isDark ? Colors.white70 : Colors.black54, 
          ),
          tooltip: "Zmień motyw",
          offset: const Offset(0, 45),
          onSelected: (ThemeMode mode) {
            ThemeService().setThemeMode(mode);
          },
          itemBuilder: (BuildContext context) => <PopupMenuEntry<ThemeMode>>[
            PopupMenuItem<ThemeMode>(
              enabled: false,
              child: Text(
                "WYGLĄD",
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface.withOpacity(0.3),
                  letterSpacing: 1.2,
                ),
              ),
            ),
            _buildMenuItem(context, ThemeMode.light, Icons.light_mode_rounded, "Jasny", currentMode),
            _buildMenuItem(context, ThemeMode.dark, Icons.dark_mode_rounded, "Ciemny", currentMode),
            _buildMenuItem(context, ThemeMode.system, Icons.settings_brightness_rounded, "Systemowy", currentMode),
          ],
        );
      },
    );
  }

  PopupMenuItem<ThemeMode> _buildMenuItem(
    BuildContext context, 
    ThemeMode mode, 
    IconData icon, 
    String label, 
    ThemeMode currentMode
  ) {
    final theme = Theme.of(context);
    bool isSelected = mode == currentMode;
    return PopupMenuItem<ThemeMode>(
      value: mode,
      child: Row(
        children: [
          Icon(icon, size: 18, color: isSelected ? const Color(0xFF007BFF) : theme.colorScheme.onSurface.withOpacity(0.5)),
          const SizedBox(width: 12),
          Text(
            label,
            style: GoogleFonts.montserrat(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected ? const Color(0xFF007BFF) : theme.colorScheme.onSurface,
            ),
          ),
          if (isSelected) ...[
            const Spacer(),
            const Icon(Icons.check_rounded, size: 16, color: Color(0xFF007BFF)),
          ]
        ],
      ),
    );
  }

  IconData _getIconForMode(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return Icons.light_mode_rounded;
      case ThemeMode.dark:
        return Icons.dark_mode_rounded;
      case ThemeMode.system:
        return Icons.settings_brightness_rounded;
    }
  }
}
