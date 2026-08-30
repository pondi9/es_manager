import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'dart:typed_data';

class SignaturePad extends StatefulWidget {
  final Function(Uint8List?) onSave;
  const SignaturePad({super.key, required this.onSave});

  @override
  State<SignaturePad> createState() => _SignaturePadState();
}

class _SignaturePadState extends State<SignaturePad> {
  List<Offset?> _points = [];
  final GlobalKey _paintKey = GlobalKey();

  Future<Uint8List?> _captureSignature() async {
    if (_points.isEmpty) return null;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 400, 200));
    
    // Tło białe dla PDF
    canvas.drawRect(const Rect.fromLTWH(0, 0, 400, 200), Paint()..color = Colors.white);

    final paint = Paint()
      ..color = Colors.black
      ..strokeCap = ui.StrokeCap.round
      ..strokeWidth = 3.0;

    for (int i = 0; i < _points.length - 1; i++) {
      if (_points[i] != null && _points[i + 1] != null) {
        canvas.drawLine(_points[i]!, _points[i + 1]!, paint);
      }
    }

    final picture = recorder.endRecording();
    final img = await picture.toImage(400, 200);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 200,
          width: 400,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.black, width: 2),
            color: Colors.white,
          ),
          child: GestureDetector(
            key: _paintKey,
            onPanUpdate: (details) {
              setState(() {
                final RenderBox renderBox = _paintKey.currentContext!.findRenderObject() as RenderBox;
                final localPosition = renderBox.globalToLocal(details.globalPosition);
                // Ograniczenie rysowania do ramki
                if (localPosition.dx >= 0 && localPosition.dx <= 400 && 
                    localPosition.dy >= 0 && localPosition.dy <= 200) {
                  _points.add(localPosition);
                }
              });
            },
            onPanEnd: (details) => _points.add(null),
            child: CustomPaint(
              painter: SignaturePainter(points: _points),
              size: Size.infinite,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            TextButton.icon(
              onPressed: () => setState(() => _points.clear()),
              icon: const Icon(Icons.delete_sweep, color: Colors.red),
              label: const Text('WYCZYŚĆ', style: TextStyle(color: Colors.red)),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                final bytes = await _captureSignature();
                widget.onSave(bytes);
                Navigator.pop(context);
              },
              icon: const Icon(Icons.check),
              label: const Text('ZATWIERDŹ'),
            ),
          ],
        )
      ],
    );
  }
}

class SignaturePainter extends CustomPainter {
  final List<Offset?> points;
  SignaturePainter({required this.points});

  @override
  void paint(Canvas canvas, Size size) {
    Paint paint = Paint()
      ..color = Colors.black
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3.0;

    for (int i = 0; i < points.length - 1; i++) {
      if (points[i] != null && points[i + 1] != null) {
        canvas.drawLine(points[i]!, points[i + 1]!, paint);
      }
    }
  }

  @override
  bool shouldRepaint(SignaturePainter oldDelegate) => true;
}
