import 'package:flutter/material.dart';
import 'package:nfc_manager/nfc_manager.dart';

class NfcTagScreen extends StatefulWidget {
  const NfcTagScreen({super.key});

  @override
  State<NfcTagScreen> createState() => _NfcTagScreenState();
}

class _NfcTagScreenState extends State<NfcTagScreen> {
  ValueNotifier<dynamic> result = ValueNotifier(null);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('CZYTNIK NFC / TAGI'),
        backgroundColor: const Color(0xFF455A64),
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: FutureBuilder<bool>(
          future: NfcManager.instance.isAvailable(),
          builder: (context, ss) {
            if (ss.data != true) {
              return Center(child: Text('NFC nie jest dostępne na tym urządzeniu: ${ss.data}'));
            }

            return Flex(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              direction: Axis.vertical,
              children: [
                Flexible(
                  flex: 2,
                  child: Container(
                    margin: const EdgeInsets.all(4),
                    constraints: const BoxConstraints.expand(),
                    decoration: BoxDecoration(border: Border.all()),
                    child: SingleChildScrollView(
                      child: ValueListenableBuilder<dynamic>(
                        valueListenable: result,
                        builder: (context, value, _) => Text('${value ?? ''}'),
                      ),
                    ),
                  ),
                ),
                Flexible(
                  flex: 3,
                  child: GridView.count(
                    padding: const EdgeInsets.all(4),
                    crossAxisCount: 2,
                    childAspectRatio: 4,
                    crossAxisSpacing: 4,
                    mainAxisSpacing: 4,
                    children: [
                      ElevatedButton(onPressed: _tagRead, child: const Text('SKANUJ TAG')),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _tagRead() {
    NfcManager.instance.startSession(
      pollingOptions: {
        NfcPollingOption.iso14443,
        NfcPollingOption.iso15693,
      },
      onDiscovered: (NfcTag tag) async {
        result.value = tag.data;
        NfcManager.instance.stopSession();
      },
    );
  }
}
