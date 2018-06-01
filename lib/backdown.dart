import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

class Backdown {
  static Backdown _singleton;
  static const MethodChannel _channel = const MethodChannel('backdown');

  // Methods supported.
  static const String METHOD_ENQUEUE_DOWNLOAD = "enqueueDownload";
  static const String METHOD_SET_DEFAULTS = "setDefaults";

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

  factory Backdown(Color notificationColor) {
    if (Backdown._singleton != null) {
      return Backdown._singleton;
    }
    _singleton = new Backdown._internal();
    _channel.setMethodCallHandler(_singleton.handler);

    // set the defaults.
    _channel.invokeMethod(METHOD_SET_DEFAULTS,
        <String, Object>{"color": new Color(0xFF00FF00).value});

    return _singleton;
  }

  Future<dynamic> handler(MethodCall call) async {
    switch (call.method) {
      case COMPLETE_EVENT:
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
        }
        break;
      case PROGRESS_EVENT:
        int downloadId = call.arguments[KEY_DOWNLOAD_ID];
        int progress = call.arguments[KEY_PROGRESS];
        int total = call.arguments[KEY_TOTAL];
        print("ProgressEvent: $progress / $total for DownloadId: $downloadId");
        break;
      default:
        break;
    }
  }

  static void downloadFileWithURL() async {
    final String url = "https://traffic.megaphone.fm/GLT8678602522.mp3";
    final String title = "Episode 101 - BBC World at One";
    final String description = "Downloading...";

    BackdownRequest request = new BackdownRequest(url, title, description,
        wifiOnly: true, showNotification: true);

    String id =
        await _channel.invokeMethod(METHOD_ENQUEUE_DOWNLOAD, request.toMap());

    print(id);

    final String url2 =
        "https://rss.art19.com/episodes/eae26461-a482-4d93-a689-914e42f736ec.mp3";
    final String title2 = "Morning Joe";
    final String desc2 = "Downloading..";
    BackdownRequest req2 = new BackdownRequest(url2, title2, desc2);
    String id2 =
        await _channel.invokeMethod(METHOD_ENQUEUE_DOWNLOAD, req2.toMap());

    print(id);
    print(id2);
  }
}

class BackdownRequest {
  final String url;
  final String title;
  final String description;
  final bool wifiOnly;
  final bool showNotification;
  final bool requiresCharging;
  final bool requiresDeviceIdle;

  BackdownRequest(this.url, this.title, this.description,
      {this.wifiOnly: false,
      this.showNotification: false,
      this.requiresCharging: false,
      this.requiresDeviceIdle: false});

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      Backdown.KEY_DOWNLOAD_URL: this.url,
      Backdown.KEY_TITLE: this.title,
      Backdown.KEY_DESCRIPTION: this.description,
      Backdown.KEY_WIFI_ONLY: this.wifiOnly ?? false,
      Backdown.KEY_REQUIRES_CHARGING: this.requiresCharging ?? false,
      Backdown.KEY_REQUIRES_DEVICE_IDLE: this.requiresDeviceIdle ?? false,
    };
  }
}
