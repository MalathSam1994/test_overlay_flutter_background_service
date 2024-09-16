import 'dart:isolate';
import 'dart:async';
import 'dart:developer';
import 'dart:ui';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:system_alert_window/system_alert_window.dart';
import 'package:device_info_plus/device_info_plus.dart';

import 'package:path/path.dart';
import 'package:test_overlay/custom_overlay.dart';
import 'package:unlock_detector/unlock_detector.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(
    const MyApp(),
  );
}

@pragma("vm:entry-point")
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: CustomOverlay(),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key); // Include it in the constructor

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late UnlockDetector _unlockDetector; // Declare _unlockDetector
  UnlockDetectorStatus _status = UnlockDetectorStatus.unknown;
  SendPort? homePort;
  String _platformVersion = 'Unknown';
  bool _isShowingWindow = false;
  bool _isOverlayWindowActive = false;
  bool _isUpdatedWindow = false;
  SystemWindowPrefMode prefMode = SystemWindowPrefMode.OVERLAY;
  final ReceivePort _receivePort = ReceivePort();
  late Stream _broadcastStream;
  String text = "Stop Service";

  @override
  void initState() {
    super.initState();
    log('MyApp: initState - Initializing');
    _unlockDetector = UnlockDetector(); // Initialize UnlockDetector
    _initializeUnlockDetectorAndOverlay();
  }

  void _initializeUnlockDetectorAndOverlay() {
    log('Main: _initializeUnlockDetector - Setting up UnlockDetector');
    UnlockDetector.initialize();
    UnlockDetector.stream?.listen((status) {
      _status = status;
      log('Main: UnlockDetector Status - $_status');
      if (_status == UnlockDetectorStatus.unlocked) {
        log('Main: Screen unlocked detected');
        handleScreenUnlock(); // Usage is now after definition
      }
    });
  }

  Future<void> _initPlatformState() async {
    log('Main: _initPlatformState - Initializing platform state');
    await SystemAlertWindow.enableLogs(true);
    String? platformVersion;
    try {
      platformVersion = await SystemAlertWindow.platformVersion;
      log('Main: _initPlatformState - Platform version: $platformVersion');
    } on PlatformException {
      platformVersion = 'Failed to get platform version.';
      log('Main: _initPlatformState - PlatformException: Failed to get platform version');
    }
    if (platformVersion != null) {
      _platformVersion = platformVersion;
    }
  }

  Future<void> _requestPermissions() async {
    log('Main: _requestPermissions - Requesting system alert window permissions');
    await SystemAlertWindow.requestPermissions(prefMode: prefMode);
  }

  void _showOverlayWindow() async {
    log('Main: _showOverlayWindow - Attempting to show overlay window');
    if (!_isShowingWindow) {
      log('Main: _showOverlayWindow - Showing overlay window');
      await SystemAlertWindow.sendMessageToOverlay('show system window');
      SystemAlertWindow.showSystemWindow(
        height: (PlatformDispatcher.instance.views.first.physicalSize.height
                    .toInt() /
                PlatformDispatcher.instance.views.first.devicePixelRatio)
            .toInt(),
        width: (PlatformDispatcher.instance.views.first.physicalSize.width
                    .toInt() /
                PlatformDispatcher.instance.views.first.devicePixelRatio)
            .toInt(),
        gravity: SystemWindowGravity.CENTER,
        prefMode: prefMode,
      );
      _isShowingWindow = true;
      log('Main: _showOverlayWindow - Overlay window is now showing');
    } else {
      log('Main: _showOverlayWindow - Closing overlay window');
      _isShowingWindow = false;
      _isUpdatedWindow = false;
      SystemAlertWindow.sendMessageToOverlay(_isUpdatedWindow);
      SystemAlertWindow.closeSystemWindow(prefMode: prefMode);
      log('Main: _showOverlayWindow - Overlay window closed');
    }
  }

  void handleScreenUnlock() {
    log('Main: handleScreenUnlock - Handling screen unlock event');
    _initPlatformState();
    _requestPermissions();

    if (homePort == null) {
      log('Main: handleScreenUnlock - Checking if port is already registered');
      SendPort? existingPort = IsolateNameServer.lookupPortByName('MainApp');
      if (existingPort == null) {
        log('Main: handleScreenUnlock - Registering port with IsolateNameServer');
        final res = IsolateNameServer.registerPortWithName(
            _receivePort.sendPort, 'MainApp');
        log("Main: Port Registration Result - $res: OVERLAY");

        // Listen to the broadcast stream instead of the regular stream
        _broadcastStream = _receivePort.asBroadcastStream();
        _broadcastStream.listen((message) {
          log("Main: Message from OVERLAY - $message");
        });
      } else {
        log('Main: handleScreenUnlock - Port already registered');
      }
    }

    log('Main: handleScreenUnlock - Resetting _isShowingWindow flag to false');
    _isShowingWindow = false; // Reset the flag on every unlock event
    _showOverlayWindow(); // Usage is now after definition
  }

  @override
  void dispose() {
    log('MyApp: dispose - Cleaning up resources');
    print('MyApp: dispose - Cleaning up resources');
    // UnlockDetector.dispose(); // Dispose UnlockDetector
    SystemAlertWindow
        .removeOnClickListener(); // Remove alert window click listener
    IsolateNameServer.removePortNameMapping(
        'MainApp'); // Remove port name mapping
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Service App'),
        ),
        body: Column(
          children: [
            StreamBuilder<Map<String, dynamic>?>(
              stream: FlutterBackgroundService().on('update'),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }

                final data = snapshot.data!;
                String? device = data["device"];
                DateTime? date = DateTime.tryParse(data["current_date"]);
                return Column(
                  children: [
                    Text(device ?? 'Unknown'),
                    Text(date.toString()),
                  ],
                );
              },
            ),
            ElevatedButton(
              child: const Text("Foreground Mode"),
              onPressed: () =>
                  FlutterBackgroundService().invoke("setAsForeground"),
            ),
            ElevatedButton(
              child: const Text("Background Mode"),
              onPressed: () =>
                  FlutterBackgroundService().invoke("setAsBackground"),
            ),
            ElevatedButton(
              child: Text(text),
              onPressed: () async {
                final service = FlutterBackgroundService();
                var isRunning = await service.isRunning();
                isRunning
                    ? service.invoke("stopService")
                    : service.startService();

                setState(() {
                  text = isRunning ? 'Start Service' : 'Stop Service';
                });
              },
            ),
            const Expanded(
              child: LogView(),
            ),
          ],
        ),
      ),
    );
  }
}

class LogView extends StatefulWidget {
  const LogView({Key? key}) : super(key: key);

  @override
  State<LogView> createState() => _LogViewState();
}

class _LogViewState extends State<LogView> {
  late final Timer timer;
  List<String> logs = [];

  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      final SharedPreferences sp = await SharedPreferences.getInstance();
      await sp.reload();
      logs = sp.getStringList('log') ?? [];
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: logs.length,
      itemBuilder: (context, index) {
        final log = logs.elementAt(index);
        return Text(log);
      },
    );
  }
}
