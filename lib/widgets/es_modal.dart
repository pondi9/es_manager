import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class EsModal extends StatelessWidget {
  final String title;
  final Widget content;
  final List<Widget>? actions;
  final Widget? footer;
  final double? maxWidth;

  const EsModal({
    super.key,
    required this.title,
    required this.content,
    this.actions,
    this.footer,
    this.maxWidth,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Center(
      child: Container(
        width: screenWidth > 800 ? (maxWidth ?? 600) : screenWidth * 0.95,
        constraints: BoxConstraints(maxHeight: screenHeight * 0.9),
        margin: const EdgeInsets.symmetric(vertical: 24),
        decoration: BoxDecoration(
          color: theme.cardTheme.color,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: theme.dividerTheme.color ?? Colors.white.withOpacity(0.05), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.5 : 0.1),
              blurRadius: 30,
              spreadRadius: 10,
            )
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 16, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        title.toUpperCase(),
                        style: GoogleFonts.montserrat(
                          color: isDark ? Colors.white : Colors.black87,
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.close_rounded, color: isDark ? Colors.white54 : Colors.black38, size: 28),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),

              // Content
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: content,
                ),
              ),

              // Footer / Actions
              if (actions != null || footer != null) ...[
                const Divider(height: 1),
                Container(
                  padding: const EdgeInsets.all(20),
                  child: footer ?? Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: actions!.map((a) => Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: a,
                    )).toList(),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

void showEsModal(BuildContext context, {
  required String title,
  required Widget content,
  List<Widget>? actions,
  Widget? footer,
  double? maxWidth,
}) {
  showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: "EsModal",
    barrierColor: Colors.black.withOpacity(0.85),
    transitionDuration: const Duration(milliseconds: 250),
    pageBuilder: (context, anim1, anim2) => EsModal(
      title: title,
      content: content,
      actions: actions,
      footer: footer,
      maxWidth: maxWidth,
    ),
    transitionBuilder: (context, anim1, anim2, child) {
      return FadeTransition(
        opacity: anim1,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.9, end: 1.0).animate(CurvedAnimation(parent: anim1, curve: Curves.easeOutBack)),
          child: child,
        ),
      );
    },
  );
}
