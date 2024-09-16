import 'dart:developer';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:system_alert_window/system_alert_window.dart';

class CustomOverlay extends StatefulWidget {
  @override
  State<CustomOverlay> createState() => _CustomOverlayState();
}

class _CustomOverlayState extends State<CustomOverlay> {
  static const String _mainAppPort = 'MainApp';
  SendPort? mainAppPort;
  bool update = false;
  @override
  void initState() {
    // TODO: implement initState
    super.initState();

    SystemAlertWindow.overlayListener.listen((event) {
      log("$event in overlay");
      if (event is bool) {
        setState(() {
          update = event;
        });
      }
    });
  }

  Widget overlay() {
    return Padding(
      padding: const EdgeInsets.all(7.0),
      child: Container(
        height: double.infinity,
        width: double.infinity,
        child: Stack(
          children: [
            Image.asset(
              'assets/Glass klein9.png',
              fit: BoxFit.cover,
            ),
            Opacity(
              opacity: 0.5,
              child: Container(
                height: 700,
                width: double.infinity,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.blueAccent, Colors.purpleAccent],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            ),
            Opacity(
              opacity: 0.8,
              child: Image.asset(
                'assets/Glass klein9.png',
                fit: BoxFit.cover,
              ),
            ),
            Positioned(
              top: 10.0, // Adjust the position as needed
              right: 10.0, // Adjust the position as needed
              child: IconButton(
                onPressed: () {
                  mainAppPort ??= IsolateNameServer.lookupPortByName(
                    _mainAppPort,
                  );

                  if (mainAppPort != null) {
                    mainAppPort?.send('Date: ${DateTime.now()}');
                    mainAppPort?.send('Close');
                  } else {
                    print("Error: mainAppPort is null.");
                  }

                  SystemAlertWindow.closeSystemWindow(prefMode: prefMode)
                      .then((value) {
                    print("System window closed: $value");
                  }).catchError((e) {
                    print("Error closing system window: $e");
                  });
                },
                icon: Icon(Icons.close),
              ),
            ),
          ],
        ),
      ),
    );
  }

  SystemWindowPrefMode prefMode = SystemWindowPrefMode.OVERLAY;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: overlay(),
    );
  }
}
