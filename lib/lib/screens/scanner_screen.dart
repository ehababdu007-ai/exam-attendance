import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:vibration/vibration.dart';
import '../providers/attendance_provider.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  bool isProcessing = false;

  void _onDetect(BarcodeCapture capture, AttendanceProvider provider) async {
    if (isProcessing) return;
    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final String? rawCode = barcodes.first.rawValue;
    if (rawCode == null || rawCode.isEmpty) return;

    setState(() => isProcessing = true);

    try {
      if (await Vibration.hasVibrator() ?? false) {
        Vibration.vibrate(duration: 100);
      }
    } catch (_) {}

    final String result = await provider.markAttendance(rawCode);

    if (!mounted) return;

    if (result.startsWith("SUCCESS:")) {
      final String name = result.split(":")[1];
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم تحضير: $name بنجاح ✅', style: const TextStyle(fontSize: 16)),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result, style: const TextStyle(fontSize: 16)),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
    }

    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => isProcessing = false);
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AttendanceProvider>(context, listen: false);

    return Scaffold(
      appBar: AppBar(title: const Text('مسح الباركود')),
      body: Stack(
        children: [
          MobileScanner(
            onDetect: (capture) => _onDetect(capture, provider),
          ),
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.green, width: 3),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          if (isProcessing)
            Container(
              color: Colors.black26,
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}
