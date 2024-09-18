import 'dart:isolate';
import 'dart:async';
import 'dart:developer';
import 'dart:ui';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:system_alert_window/system_alert_window.dart';
import 'package:test_overlay/custom_overlay.dart';
import 'package:unlock_detector/unlock_detector.dart';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

@pragma('vm:entry-point')
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeService();
  runApp(
    const MyApp(),
  );
}

Future<void> initializeService() async {
  WidgetsFlutterBinding.ensureInitialized();
  final service = FlutterBackgroundService();

  /// OPTIONAL, using custom notification channel id
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'my_foreground', // id
    'MY FOREGROUND SERVICE', // title
    description:
        'This channel is used for important notifications.', // description
    importance: Importance.low, // importance must be at low or higher level
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  if (Platform.isAndroid) {
    await flutterLocalNotificationsPlugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('ic_bg_service_small'),
      ),
    );
  }

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: true,
      isForegroundMode: true,
      notificationChannelId: 'my_foreground',
      initialNotificationTitle: 'AWESOME SERVICE',
      initialNotificationContent: 'Initializing',
      foregroundServiceNotificationId: 888,
      foregroundServiceTypes: [AndroidForegroundType.location],
    ),
    iosConfiguration: IosConfiguration(),
  );
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  SharedPreferences preferences = await SharedPreferences.getInstance();
  await preferences.setString("hello", "world");

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  // Listen for messages from the main isolate
  service.on('update').listen((event) {
    String? eventType = event?['event'];
    if (eventType == 'unlocked') {
      log('Background Service: Screen unlocked event received.');
      // Perform your background tasks here
    }
  });

  Timer.periodic(const Duration(seconds: 1), (timer) async {
    if (service is AndroidServiceInstance) {
      if (await service.isForegroundService()) {
        flutterLocalNotificationsPlugin.show(
          888,
          'COOL SERVICE',
          'Awesome ${DateTime.now()}',
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'my_foreground',
              'MY FOREGROUND SERVICE',
              icon: 'ic_bg_service_small',
              ongoing: true,
            ),
          ),
        );

        service.setForegroundNotificationInfo(
          title: "My App Service",
          content: "Updated at ${DateTime.now()}",
        );
      }
    }

    debugPrint('FLUTTER BACKGROUND SERVICE: ${DateTime.now()}');

    final deviceInfo = DeviceInfoPlugin();
    String? device;
    if (Platform.isAndroid) {
      final androidInfo = await deviceInfo.androidInfo;
      device = androidInfo.model;
    }

    service.invoke(
      'update',
      {
        "current_date": DateTime.now().toIso8601String(),
        "device": device,
      },
    );
  });
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
  const MyApp({Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  UnlockDetectorStatus _status = UnlockDetectorStatus.unknown;
  String _platformVersion = 'Unknown';
  bool _isShowingWindow = false;
  SystemWindowPrefMode prefMode = SystemWindowPrefMode.OVERLAY;
  final ReceivePort _receivePort = ReceivePort();
  late Stream _broadcastStream;
  String text = "Stop Service";

  @override
  void initState() {
    super.initState();
    log('MyApp: initState - Initializing');

    // Initialize UnlockDetector on the main isolate
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
        handleScreenUnlock();
      }
    });
  }

  void handleScreenUnlock() {
    log('Main: handleScreenUnlock - Handling screen unlock event');

    // Send a message to the background service
    FlutterBackgroundService().invoke('update', {
      "event": "unlocked",
      "current_date": DateTime.now().toIso8601String(),
    });

    _initPlatformState();
    _requestPermissions();
    _showOverlayWindow();
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
      SystemAlertWindow.sendMessageToOverlay(false);
      SystemAlertWindow.closeSystemWindow(prefMode: prefMode);
      log('Main: _showOverlayWindow - Overlay window closed');
    }
  }

  @override
  void dispose() {
    log('MyApp: dispose - Cleaning up resources');
    SystemAlertWindow.removeOnClickListener();
    IsolateNameServer.removePortNameMapping('MainApp');
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
