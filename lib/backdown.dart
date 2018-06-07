import 'dart:async';
import 'dart:ui';

import 'package:flutter/services.dart';

class Backdown {
  static Backdown _singleton;
  static const MethodChannel _channel = const MethodChannel("backdown");

  static final StreamController<BackdownEvent> _sc = new StreamController<BackdownEvent>();

  // Methods supported.
  static const String METHOD_CREATE_DOWNLOAD = "createDownload";
  static const String METHOD_ENQUEUE_DOWNLOAD = "enqueueDownload";
  static const String METHOD_SET_DEFAULTS = "setDefaults";
  static const String METHOD_CANCEL_DOWNLOAD = "cancelDownload";

  // Event Keys
  static const String COMPLETE_EVENT = "COMPLETE_EVENT";
  static const String PROGRESS_EVENT = "PROGRESS_EVENT";

  // Keys
  static const String KEY_DOWNLOAD_URL = "DOWNLOAD_URL";
  static const String KEY_ACCENT_COLOR = "ACCENT_COLOR";
  static const String KEY_TITLE = "TITLE";
  static const String KEY_DESCRIPTION = "DESCRIPTION";
  static const String KEY_WIFI_ONLY = "WIFI_ONLY";
  static const String KEY_REQUIRES_CHARGING = "REQUIRED_CHARGING";
  static const String KEY_REQUIRES_DEVICE_IDLE = "REQUIRES_DEVICE_IDLE";

  // Progress Event Keys
  static const String KEY_PROGRESS = "PROGRESS";
  static const String KEY_TOTAL = "TOTAL";

  // Response Keys
  static const String KEY_SUCCESS = "SUCCESS";
  static const String KEY_DOWNLOAD_ID = "DOWNLOAD_ID";
  static const String KEY_FILE_PATH = "FILE_PATH";
  static const String KEY_ERROR_MSG = "ERROR_MSG"; // if Success == false.

  Backdown._internal();

  /// notificationColor needs only be sent at application
  /// startup.
  factory Backdown({Color notificationColor}) {
    if (Backdown._singleton != null) {
      return Backdown._singleton;
    }
    _singleton = new Backdown._internal();
    _channel.setMethodCallHandler(_singleton.handler);

    var color = notificationColor ?? new Color(0xFF000000);

    // set the defaults.
    _channel.invokeMethod(METHOD_SET_DEFAULTS, <String, Object>{"color": color.value});

    return _singleton;
  }

  // Listen to this...
  static Stream<BackdownEvent> get backdownEventStream => _sc.stream;

  Future<dynamic> handler(MethodCall call) async {
    print("Heard handler call...");
    switch (call.method) {
      case COMPLETE_EVENT:
        DownloadCompleteEvent event = new DownloadCompleteEvent.from((call.arguments as Map).cast<String, dynamic>());
        _sc.add(event);
        break;

      case PROGRESS_EVENT:
        DownloadProgressEvent event = new DownloadProgressEvent.from((call.arguments as Map).cast<String, dynamic>());
        _sc.add(event);
        break;
      default:
        break;
    }
  }

  /// Create a download and get an id for it.
  /// Nothing really happens here, except that you had it off to the native code
  /// and it generates a downloadId for you to store in case you want to query
  /// the download, or for understanding the progress and complete events on the
  /// stream.
  static Future<String> createDownload(BackdownRequest request) async {
    String id = await _channel.invokeMethod(METHOD_CREATE_DOWNLOAD, request.toMap());
    return id;
  }

  /// Enqueue a download - schedule it with the system.
  static Future<bool> enqueueDownload(String downloadId) async {
    var result = await _channel.invokeMethod(METHOD_ENQUEUE_DOWNLOAD, <String, dynamic>{KEY_DOWNLOAD_ID: downloadId});
    final bool success = (result as Map).cast<String, bool>()[KEY_SUCCESS];
    return success;
  }

  /// Cancel an enqueued download.
  /// @returns - true for success;
  static Future<bool> cancelDownload(String id) async {
    var result = await _channel.invokeMethod(METHOD_CANCEL_DOWNLOAD, <String, dynamic>{KEY_DOWNLOAD_ID: id});
    return result[KEY_SUCCESS];
  }

  /// debug.
  static void downloadFileWithURL() async {
    //final String url = "https://traffic.megaphone.fm/GLT8678602522.mp3";
    final String url =
        "https://ia800500.us.archive.org/5/items/aesop_fables_volume_one_librivox/fables_01_00_aesop.mp3";
    final String title = "Episode 101 - BBC World at One";
    final String description = "Downloading...";

    BackdownRequest request = new BackdownRequest.asap(url, title, description);
    String id = await Backdown.createDownload(request);
    bool success = await Backdown.enqueueDownload(id);
    print("$id created and enqueued? $success");

    /*final String url2 = "https://rss.art19.com/episodes/eae26461-a482-4d93-a689-914e42f736ec.mp3";
    final String title2 = "Morning Joe";
    final String desc2 = "Downloading..";
    BackdownRequest req2 = new BackdownRequest.asap(url2, title2, desc2);
    String id2 = await _channel.invokeMethod(METHOD_ENQUEUE_DOWNLOAD, req2.toMap());

    print(id);
    print(id2);

    var success = await _channel.invokeMethod("cancelDownload", <String, dynamic>{KEY_DOWNLOAD_ID: id2});

    print("Removed $id2 ? ${success[KEY_SUCCESS]}");*/
  }
}

class BackdownRequest {
  final String url;
  final String title;
  final String description;
  final bool wifiOnly;
  final bool androidRequiresCharging;
  final bool androidRequiresDeviceIdle;

  /// iOS and Android will download this file asap.
  BackdownRequest.asap(this.url, this.title, this.description)
      : this.wifiOnly = false,
        this.androidRequiresCharging = false,
        this.androidRequiresDeviceIdle = false;

  /// iOS - Will force iOS to discretionary, allowing the system to schedule the download
  /// at the optimum time.
  /// Android - wifiOnly = true, requiresCharging = requiresDeviceIdle = false;
  BackdownRequest.discretionaryWithWifi(this.url, this.title, this.description)
      : this.wifiOnly = true,
        this.androidRequiresCharging = false,
        this.androidRequiresDeviceIdle = false;

  /// iOS - Will force iOS to discretionary, allowing the system to schedule the download
  /// at the optimum time.
  /// Android - wifiOnly = true, requiresCharging = true, requiresDeviceIdle = false;
  BackdownRequest.discretionaryWithWifiAndPower(this.url, this.title, this.description)
      : this.wifiOnly = true,
        this.androidRequiresCharging = true,
        this.androidRequiresDeviceIdle = false;

  /// iOS - Will force iOS to discretionary, allowing the system to schedule the download
  /// at the optimum time.
  /// Android - wifiOnly = true, requiresCharging = true, requiresDeviceIdle = true;
  BackdownRequest.discretionaryWithWifiPowerAndIdle(this.url, this.title, this.description)
      : this.wifiOnly = true,
        this.androidRequiresCharging = true,
        this.androidRequiresDeviceIdle = true;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      Backdown.KEY_DOWNLOAD_URL: this.url,
      Backdown.KEY_TITLE: this.title,
      Backdown.KEY_DESCRIPTION: this.description,
      Backdown.KEY_WIFI_ONLY: this.wifiOnly ?? false,
      Backdown.KEY_REQUIRES_CHARGING: this.androidRequiresCharging ?? false,
      Backdown.KEY_REQUIRES_DEVICE_IDLE: this.androidRequiresDeviceIdle ?? false,
    };
  }
}

/// These events are sent to the BackdownPlugin's event Stream.
/// Tells a listener about progress.
class DownloadProgressEvent extends BackdownEvent {
  int progress;
  int expectedBytes;
  DownloadProgressEvent(String downloadId, this.progress, this.expectedBytes) : super(downloadId);

  DownloadProgressEvent.from(Map<String, dynamic> data) : super(data[Backdown.KEY_DOWNLOAD_ID]) {
    this.progress = data[Backdown.KEY_PROGRESS];
    this.expectedBytes = data[Backdown.KEY_TOTAL];
  }
}

/// Broadcast when the Download is complete.
class DownloadCompleteEvent extends BackdownEvent {
  bool success;
  String filePath;
  DownloadCompleteEvent(String downloadId, this.success, this.filePath) : super(downloadId);

  DownloadCompleteEvent.from(Map<String, dynamic> data) : super(data[Backdown.KEY_DOWNLOAD_ID]) {
    this.success = data[Backdown.KEY_SUCCESS];
    this.filePath = data[Backdown.KEY_FILE_PATH];
  }
}

abstract class BackdownEvent {
  String downloadId;

  BackdownEvent(this.downloadId);
}

/*
        bool success = call.arguments[KEY_SUCCESS];
        int downloadId = call.arguments[KEY_DOWNLOAD_ID];
        String filePath = call.arguments[KEY_FILE_PATH];
        if (success == true) {
          print("Success");
          print(downloadId);
          print(filePath);

          Directory p = await getApplicationDocumentsDirectory();
          File file;
          if (filePath.startsWith("file://")) {
            //iOS returns these...
            file = new File.fromUri(Uri.parse(filePath));
          } else {
            file = new File(filePath);
          }
          bool exists = file.existsSync();
          assert(exists);
          print("file exists? " + exists.toString());

          String filename = basename(file.path);
          String newPath = "${p.path}/example/$filename";
          File f = new File(newPath);
          f.createSync(recursive: true);
          file.renameSync(newPath);
          print("Moved to: $newPath");
          break;
        }*/

/*int downloadId = call.arguments[KEY_DOWNLOAD_ID];
        int progress = call.arguments[KEY_PROGRESS];
        int total = call.arguments[KEY_TOTAL];
        print("ProgressEvent: $progress / $total for DownloadId: $downloadId");
        break;*/
