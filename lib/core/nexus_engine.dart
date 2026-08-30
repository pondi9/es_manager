import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

enum NexusTileSize { small, medium, large, wide }

class NexusTile {
  final String id;
  final String title;
  final IconData icon;
  double width; // 1.0 - 6.0
  double height; // 1.0 - 6.0
  double x; // Pozycja w kolumnach
  double y; // Pozycja w wierszach
  int order;
  bool isHidden;

  NexusTile({
    required this.id,
    required this.title,
    required this.icon,
    this.width = 2.0,
    this.height = 2.0,
    this.x = 0,
    this.y = 0,
    this.order = 0,
    this.isHidden = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id, 'width': width, 'height': height, 'x': x, 'y': y, 'order': order, 'isHidden': isHidden
  };

  factory NexusTile.fromJson(Map<String, dynamic> json, String title, IconData icon) {
    return NexusTile(
      id: json['id'],
      title: title,
      icon: icon,
      width: (json['width'] ?? 2).toDouble(),
      height: (json['height'] ?? 2).toDouble(),
      x: (json['x'] ?? 0).toDouble(),
      y: (json['y'] ?? 0).toDouble(),
      order: json['order'] ?? 0,
      isHidden: json['isHidden'] ?? false,
    );
  }
}

class NexusTileWrapper extends StatelessWidget {
  final NexusTile tile;
  final Widget child;
  final bool isEditMode;
  final VoidCallback? onDelete;
  final VoidCallback? onSettings;
  final Function(DragUpdateDetails)? onDragUpdate;
  final VoidCallback? onDragEnd;
  final Function(DragUpdateDetails)? onResizeUpdate;
  final VoidCallback? onResizeEnd;

  const NexusTileWrapper({
    super.key, 
    required this.tile, 
    required this.child, 
    this.isEditMode = false,
    this.onDelete,
    this.onSettings,
    this.onDragUpdate,
    this.onDragEnd,
    this.onResizeUpdate,
    this.onResizeEnd,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isEditMode ? const Color(0xFF007BFF) : (theme.dividerTheme.color ?? Colors.white10),
          width: isEditMode ? 2 : 1,
        ),
        boxShadow: isDark ? null : [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, 8))
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          child,
          if (isEditMode) ...[
            Positioned.fill(child: Container(color: Colors.black.withOpacity(0.6))),
            
            Positioned(
              top: 12, left: 12, right: 12,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Uchwyt przesuwania ⠿
                  GestureDetector(
                    onPanUpdate: onDragUpdate,
                    onPanEnd: (_) => onDragEnd?.call(),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: const Color(0xFF007BFF), borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.drag_indicator_rounded, color: Colors.white, size: 20),
                    ),
                  ),
                  Row(
                    children: [
                      _controlBtn(Icons.settings_rounded, Colors.white, onSettings),
                      const SizedBox(width: 8),
                      _controlBtn(
                        tile.isHidden ? Icons.visibility_rounded : Icons.visibility_off_rounded, 
                        tile.isHidden ? Colors.greenAccent : Colors.redAccent, 
                        onDelete
                      ),
                    ],
                  )
                ],
              ),
            ),

            // Uchwyt zmiany rozmiaru ↘
            Positioned(
              bottom: 0, right: 0,
              child: GestureDetector(
                onPanUpdate: onResizeUpdate,
                onPanEnd: (_) => onResizeEnd?.call(),
                child: Container(
                  width: 50, height: 50,
                  alignment: Alignment.bottomRight,
                  padding: const EdgeInsets.all(8),
                  child: const Icon(Icons.south_east_rounded, color: Color(0xFF007BFF), size: 24),
                ),
              ),
            ),

            IgnorePointer(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(tile.title, textAlign: TextAlign.center, style: GoogleFonts.montserrat(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 10)),
                    Text("${tile.width.toStringAsFixed(0)}x${tile.height.toStringAsFixed(0)}", style: const TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _controlBtn(IconData icon, Color color, VoidCallback? onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: Colors.black.withOpacity(0.5), borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: color, size: 18),
      ),
    );
  }
}
