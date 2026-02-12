import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

Future<String?> showQrScannerDialog(BuildContext context) async {
  return showDialog<String>(
    context: context,
    builder: (context) => const _QrScannerDialog(),
  );
}

class _QrScannerDialog extends StatefulWidget {
  const _QrScannerDialog();

  @override
  State<_QrScannerDialog> createState() => _QrScannerDialogState();
}

class _QrScannerDialogState extends State<_QrScannerDialog> {
  final TextEditingController _manualController = TextEditingController();
  bool _handled = false;

  @override
  void dispose() {
    _manualController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canScan = !kIsWeb;
    return AlertDialog(
      title: const Text('Scan QR'),
      content: SizedBox(
        width: 460,
        height: 360,
        child: Column(
          children: [
            if (canScan)
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: MobileScanner(
                    onDetect: (capture) {
                      if (_handled) return;
                      final value = capture.barcodes.isNotEmpty ? capture.barcodes.first.rawValue : null;
                      if (value == null || value.isEmpty) return;
                      _handled = true;
                      Navigator.pop(context, value);
                    },
                  ),
                ),
              )
            else
              const Text('Camera scanner is unavailable in this environment.'),
            const SizedBox(height: 12),
            TextField(
              controller: _manualController,
              decoration: const InputDecoration(
                hintText: 'Paste tg:// or https://t.me/...',
                prefixIcon: Icon(Icons.link),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _manualController.text.trim()),
          child: const Text('Use link'),
        ),
      ],
    );
  }
}
