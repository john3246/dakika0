import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class CourierScannerScreen extends StatefulWidget {
  final Function(String) onScan;
  final String title;

  const CourierScannerScreen({
    Key? key,
    required this.onScan,
    this.title = 'Scan QR Code',
  }) : super(key: key);

  @override
  State<CourierScannerScreen> createState() => _CourierScannerScreenState();
}

class _CourierScannerScreenState extends State<CourierScannerScreen> {
  bool _isProcessing = false;
  late MobileScannerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      torchEnabled: false,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isProcessing) return;
    
    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
      final String code = barcodes.first.rawValue!;
      setState(() {
        _isProcessing = true;
      });
      _controller.stop();
      widget.onScan(code);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: ValueListenableBuilder(
              valueListenable: _controller.torchState,
              builder: (context, state, child) {
                switch (state) {
                  case TorchState.off:
                    return const Icon(Icons.flash_off, color: Colors.grey);
                  case TorchState.on:
                    return const Icon(Icons.flash_on, color: Colors.yellow);
                }
              },
            ),
            onPressed: () => _controller.toggleTorch(),
          ),
          IconButton(
            icon: ValueListenableBuilder(
              valueListenable: _controller.cameraFacingState,
              builder: (context, state, child) {
                switch (state) {
                  case CameraFacing.front:
                    return const Icon(Icons.camera_front);
                  case CameraFacing.back:
                    return const Icon(Icons.camera_rear);
                }
              },
            ),
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        alignment: Alignment.center,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),
          // Scanner Overlay
          Container(
            decoration: ShapeDecoration(
              shape: QrScannerOverlayShape(
                borderColor: Theme.of(context).primaryColor,
                borderRadius: 10,
                borderLength: 30,
                borderWidth: 10,
                cutOutSize: MediaQuery.of(context).size.width * 0.8,
              ),
            ),
          ),
          const Positioned(
            bottom: 50,
            child: Text(
              'Align QR code within the frame',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

class QrScannerOverlayShape extends ShapeBorder {
  final Color borderColor;
  final double borderWidth;
  final double borderLength;
  final double borderRadius;
  final double cutOutSize;

  QrScannerOverlayShape({
    this.borderColor = Colors.red,
    this.borderWidth = 3.0,
    this.borderLength = 20.0,
    this.borderRadius = 0,
    this.cutOutSize = 250,
  });

  @override
  EdgeInsetsGeometry get dimensions => const EdgeInsets.all(10.0);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    return Path()
      ..fillType = PathFillType.evenOdd
      ..addPath(getOuterPath(rect), Offset.zero);
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    Path _getLeftTopPath(Rect rect) {
      return Path()
        ..moveTo(rect.left, rect.bottom)
        ..lineTo(rect.left, rect.top)
        ..lineTo(rect.right, rect.top);
    }
    return _getLeftTopPath(rect)
      ..lineTo(rect.right, rect.bottom)
      ..lineTo(rect.left, rect.bottom)
      ..lineTo(rect.left, rect.top);
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    final double width = rect.width;
    final double height = rect.height;
    
    final Paint paint = Paint()
      ..color = Colors.black54
      ..style = PaintingStyle.fill;

    final double cutOutLeft = (width - cutOutSize) / 2;
    final double cutOutTop = (height - cutOutSize) / 2;
    final double cutOutRight = cutOutLeft + cutOutSize;
    final double cutOutBottom = cutOutTop + cutOutSize;

    // Background
    canvas.drawPath(
      Path()
        ..addRect(rect)
        ..addRRect(RRect.fromLTRBAndCorners(
          cutOutLeft, cutOutTop, cutOutRight, cutOutBottom,
          topLeft: Radius.circular(borderRadius),
          topRight: Radius.circular(borderRadius),
          bottomLeft: Radius.circular(borderRadius),
          bottomRight: Radius.circular(borderRadius),
        ))
        ..fillType = PathFillType.evenOdd,
      paint,
    );

    // Border
    final Paint borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth;

    // Draw borders at corners
    final path = Path();
    
    // Top left
    path.moveTo(cutOutLeft, cutOutTop + borderLength);
    path.lineTo(cutOutLeft, cutOutTop + borderRadius);
    path.arcToPoint(Offset(cutOutLeft + borderRadius, cutOutTop),
        radius: Radius.circular(borderRadius));
    path.lineTo(cutOutLeft + borderLength, cutOutTop);

    // Top right
    path.moveTo(cutOutRight - borderLength, cutOutTop);
    path.lineTo(cutOutRight - borderRadius, cutOutTop);
    path.arcToPoint(Offset(cutOutRight, cutOutTop + borderRadius),
        radius: Radius.circular(borderRadius));
    path.lineTo(cutOutRight, cutOutTop + borderLength);

    // Bottom left
    path.moveTo(cutOutLeft, cutOutBottom - borderLength);
    path.lineTo(cutOutLeft, cutOutBottom - borderRadius);
    path.arcToPoint(Offset(cutOutLeft + borderRadius, cutOutBottom),
        radius: Radius.circular(borderRadius), clockwise: false);
    path.lineTo(cutOutLeft + borderLength, cutOutBottom);

    // Bottom right
    path.moveTo(cutOutRight - borderLength, cutOutBottom);
    path.lineTo(cutOutRight - borderRadius, cutOutBottom);
    path.arcToPoint(Offset(cutOutRight, cutOutBottom - borderRadius),
        radius: Radius.circular(borderRadius), clockwise: false);
    path.lineTo(cutOutRight, cutOutBottom - borderLength);

    canvas.drawPath(path, borderPaint);
  }

  @override
  ShapeBorder scale(double t) {
    return QrScannerOverlayShape(
      borderColor: borderColor,
      borderWidth: borderWidth * t,
      borderLength: borderLength * t,
      borderRadius: borderRadius * t,
      cutOutSize: cutOutSize * t,
    );
  }
}
