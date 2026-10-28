import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:go_router/go_router.dart';

import '../../../core/deep_link/deep_link.dart';
import '../../../core/theme/app_theme.dart';

/// Yalnızca kameraya odaklı tarayıcı. Tanınan karekod, hiçbir şeye dokunmadan
/// bakım kaydına (veya cihaz detayına) geçer.
class QRScannerScreen extends StatefulWidget {
  const QRScannerScreen({super.key});

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  static const _defaultHint = 'Cihazın üzerindeki karekodu okutun';
  static const _unknownHint = 'Bu karekod Homecare\'a ait değil';

  final MobileScannerController controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );
  Timer? _hintResetTimer;
  bool _isScanned = false;
  String _hint = _defaultHint;

  void _onDetect(BarcodeCapture capture) {
    if (_isScanned) return;

    var sawCode = false;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null) continue;
      sawCode = true;

      final link = DeepLink.parse(raw);
      if (link != null) {
        _isScanned = true;
        context.pushReplacement(link.location);
        return;
      }
    }

    if (sawCode) _showUnknownHint();
  }

  void _showUnknownHint() {
    if (_hint == _unknownHint) return;
    setState(() => _hint = _unknownHint);
    _hintResetTimer?.cancel();
    _hintResetTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _hint = _defaultHint);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => _ScannerError(error: error),
          ),
          IgnorePointer(child: CustomPaint(painter: _ViewfinderPainter())),
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: IconButton(
                tooltip: 'Kapat',
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => context.pop(),
              ),
            ),
          ),
          Align(
            alignment: const Alignment(0, 0.62),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _hint,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: _hint == _unknownHint ? AppTheme.statusUpcoming : Colors.white,
                    ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _hintResetTimer?.cancel();
    controller.dispose();
    super.dispose();
  }
}

class _ScannerError extends StatelessWidget {
  final MobileScannerException error;

  const _ScannerError({required this.error});

  @override
  Widget build(BuildContext context) {
    final message = switch (error.errorCode) {
      MobileScannerErrorCode.permissionDenied =>
        'Kamera izni verilmedi. Karekod okutmak için ayarlardan kamera iznini açın.',
      MobileScannerErrorCode.unsupported => 'Bu cihazda karekod okuma desteklenmiyor.',
      _ => 'Kamera başlatılamadı.',
    };

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam_off_outlined, size: 56, color: AppTheme.textSecondary),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }
}

/// Ekranı karartır; ortada karekod için kare bir pencere bırakır.
class _ViewfinderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide * 0.66;
    final window = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(size.width / 2, size.height * 0.42), width: side, height: side),
      const Radius.circular(24),
    );

    final dim = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addRRect(window),
    );
    canvas.drawPath(dim, Paint()..color = Colors.black.withValues(alpha: 0.55));
    canvas.drawRRect(
      window,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_ViewfinderPainter oldDelegate) => false;
}
