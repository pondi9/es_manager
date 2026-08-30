import 'package:flutter/material.dart';
import 'order_tracking_screen.dart';
import 'public_request_screen.dart';
import 'login_screen.dart';

class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> {
  int _logoTaps = 0;

  void _handleLogoTap() {
    setState(() => _logoTaps++);
    if (_logoTaps >= 3) {
      _logoTaps = 0;
      Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
    }
  }

  // --- DOKŁADNE WSPÓŁRZĘDNE W PIKSELACH ORYGINALNYCH PLIKÓW PNG (V12.8.1) ---
  
  // DESKTOP: es_track_desktop.png (1920x1080)
  static const Size _desktopOriginalSize = Size(1920, 1080);
  // Korekta współrzędnych - przesunięcie w górę (SUBTRACT from TOP)
  static const Rect _desktopLogo = Rect.fromLTWH(135, 0, 300, 80); 
  static const Rect _desktopBtn1 = Rect.fromLTWH(1262, 530, 373, 88); // Darmowa wycena
  static const Rect _desktopBtn2 = Rect.fromLTWH(1262, 644, 373, 88); // Śledź zlecenie

  // MOBILE: es_track_mobile.png (1080x1920)
  static const Size _mobileOriginalSize = Size(1080, 1920);
  // Korekta współrzędnych - przesunięcie w górę
  static const Rect _mobileLogo = Rect.fromLTWH(107, 0, 267, 100); 
  static const Rect _mobileBtn1 = Rect.fromLTWH(100, 1250, 880, 160); 
  static const Rect _mobileBtn2 = Rect.fromLTWH(100, 1430, 880, 160);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF030712),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final bool isDesktop = constraints.maxWidth >= 1000;
          final String assetPath = isDesktop ? 'assets/es_track_desktop.png' : 'assets/es_track_mobile.png';
          final Size originalSize = isDesktop ? _desktopOriginalSize : _mobileOriginalSize;

          final FittedSizes fittedSizes = applyBoxFit(
            BoxFit.contain,
            originalSize,
            Size(constraints.maxWidth, constraints.maxHeight),
          );

          final Size destinationSize = fittedSizes.destination;
          final double offsetX = (constraints.maxWidth - destinationSize.width) / 2;
          final double offsetY = (constraints.maxHeight - destinationSize.height) / 2;

          final double scaleX = destinationSize.width / originalSize.width;
          final double scaleY = destinationSize.height / originalSize.height;

          return Stack(
            children: [
              Center(
                child: Image.asset(
                  assetPath,
                  fit: BoxFit.contain,
                ),
              ),

              if (isDesktop) ...[
                _buildHitbox(_desktopLogo, scaleX, scaleY, offsetX, offsetY, _handleLogoTap),
                _buildHitbox(_desktopBtn1, scaleX, scaleY, offsetX, offsetY, () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const PublicRequestScreen()));
                }),
                _buildHitbox(_desktopBtn2, scaleX, scaleY, offsetX, offsetY, () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const OrderTrackingScreen()));
                }),
              ] else ...[
                _buildHitbox(_mobileLogo, scaleX, scaleY, offsetX, offsetY, _handleLogoTap),
                _buildHitbox(_mobileBtn1, scaleX, scaleY, offsetX, offsetY, () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const PublicRequestScreen()));
                }),
                _buildHitbox(_mobileBtn2, scaleX, scaleY, offsetX, offsetY, () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const OrderTrackingScreen()));
                }),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildHitbox(Rect rect, double sx, double sy, double ox, double oy, VoidCallback onTap) {
    return Positioned(
      left: rect.left * sx + ox,
      top: rect.top * sy + oy,
      width: rect.width * sx,
      height: rect.height * sy,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: const SizedBox.expand(),
      ),
    );
  }
}
