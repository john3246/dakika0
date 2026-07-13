import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Full-featured QR / barcode camera scanner for couriers.
///
/// [title]  — shown in the AppBar (e.g. "Scan QR to Pickup")
/// [onScan] — called exactly once with the raw barcode string when a valid
///            code is detected. The caller is responsible for closing the
///            scanner (Navigator.pop) before or after calling onScan.
class CourierScannerScreen extends StatefulWidget {
  final String title;
  final void Function(String) onScan;

  const CourierScannerScreen({
    super.key,
    required this.title,
    required this.onScan,
  });

  @override
  State<CourierScannerScreen> createState() => _CourierScannerScreenState();
}

class _CourierScannerScreenState extends State<CourierScannerScreen> {
  late final MobileScannerController _controller;
  bool _scanned = false; // guard so onScan fires at most once per session
  bool _torchOn = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
      torchEnabled: false,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleDetection(BarcodeCapture capture) {
    if (_scanned) return; // ignore subsequent detections after first valid scan

    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final rawValue = barcodes.first.rawValue;
    if (rawValue == null || rawValue.isEmpty) return;

    _scanned = true;
    widget.onScan(rawValue);
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final cutoutSize  = screenSize.width * 0.68;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.title, style: const TextStyle(color: Colors.white)),
        centerTitle: true,
        actions: [
          // Torch toggle
          IconButton(
            icon: Icon(
              _torchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
              color: _torchOn ? Colors.amber : Colors.white54,
            ),
            tooltip: 'Toggle torch',
            onPressed: () {
              setState(() => _torchOn = !_torchOn);
              _controller.toggleTorch();
            },
          ),
          // Flip camera
          IconButton(
            icon: const Icon(Icons.cameraswitch_rounded, color: Colors.white54),
            tooltip: 'Switch camera',
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Live camera feed ────────────────────────────────────────────────
          MobileScanner(
            controller: _controller,
            onDetect: _handleDetection,
          ),

          // ── Darkened overlay with transparent cutout ─────────────────────────
          ColorFiltered(
            colorFilter: ColorFilter.mode(
              Colors.black.withOpacity(0.60),
              BlendMode.srcOut,
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(
                  decoration: const BoxDecoration(
                    color: Colors.black,
                    backgroundBlendMode: BlendMode.dstOut,
                  ),
                ),
                Align(
                  alignment: Alignment.center,
                  child: Container(
                    width:  cutoutSize,
                    height: cutoutSize,
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Cutout border / corner guides ───────────────────────────────────
          Center(
            child: SizedBox(
              width:  cutoutSize,
              height: cutoutSize,
              child: _ScannerCornerBorder(size: cutoutSize),
            ),
          ),

          // ── Instruction text ────────────────────────────────────────────────
          Positioned(
            bottom: 80,
            left: 24,
            right: 24,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Text(
                    'Align the QR code inside the frame',
                    style: TextStyle(color: Colors.white, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Corner-bracket overlay ───────────────────────────────────────────────────
class _ScannerCornerBorder extends StatelessWidget {
  final double size;
  const _ScannerCornerBorder({required this.size});

  @override
  Widget build(BuildContext context) {
    const cornerLen = 28.0;
    const thickness = 3.5;
    const color     = Colors.white;
    const radius    = Radius.circular(6);

    return Stack(
      children: [
        // Top-left
        Positioned(top: 0, left: 0, child: _Corner(cornerLen, thickness, color, [radius, Radius.zero, Radius.zero, Radius.zero])),
        // Top-right
        Positioned(top: 0, right: 0, child: _Corner(cornerLen, thickness, color, [Radius.zero, radius, Radius.zero, Radius.zero])),
        // Bottom-left
        Positioned(bottom: 0, left: 0, child: _Corner(cornerLen, thickness, color, [Radius.zero, Radius.zero, Radius.zero, radius])),
        // Bottom-right
        Positioned(bottom: 0, right: 0, child: _Corner(cornerLen, thickness, color, [Radius.zero, Radius.zero, radius, Radius.zero])),
      ],
    );
  }
}

class _Corner extends StatelessWidget {
  final double len;
  final double thickness;
  final Color color;
  final List<Radius> radii; // TL, TR, BR, BL

  const _Corner(this.len, this.thickness, this.color, this.radii);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: len,
      height: len,
      decoration: BoxDecoration(
        border: Border(
          top:    BorderSide(color: color, width: thickness),
          left:   BorderSide(color: color, width: thickness),
          right:  BorderSide.none,
          bottom: BorderSide.none,
        ),
        borderRadius: BorderRadius.only(
          topLeft:     radii[0],
          topRight:    radii[1],
          bottomRight: radii[2],
          bottomLeft:  radii[3],
        ),
      ),
    );
  }
}
