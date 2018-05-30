import 'dart:async';

import 'package:flutter/services.dart';

class Backdown {
  static Backdown _singleton;
  static const MethodChannel _channel = const MethodChannel('backdown');

  // Keys
  static const String KEY_DOWNLOAD_URL = "DOWNLOAD_URL";
  static const String KEY_TARGET_FILE = "TARGET_FILE";
  static const String KEY_ACCENT_COLOR = "ACCENT_COLOR";
  static const String KEY_TITLE = "TITLE";
  static const String KEY_TEXT = "TEXT";

  // Response Keys
  static const String KEY_SUCCESS = "SUCCESS";
  static const String KEY_FILE_PATH = "FILE_PATH";
  static const String KEY_ERROR_MSG = "ERROR_MSG"; // if Success == false.

  Backdown._internal();

  factory Backdown() {
    if (Backdown._singleton != null) {
      return Backdown._singleton;
    }
    _singleton = new Backdown._internal();
    _channel.setMethodCallHandler(_singleton.handler);
    return _singleton;
  }

  Future<dynamic> handler(MethodCall call) async {
    switch (call.method) {
      case "event":
        Map<String, dynamic> args = call.arguments;
        bool success = args[KEY_SUCCESS];
        String downloadUrl = args[KEY_DOWNLOAD_URL];
        String filePath = args[KEY_FILE_PATH];
        if (success == true) {
          print("Success");
          print(downloadUrl);
          print(filePath);
        }
        break;
      default:
        break;
    }
  }

  static void downloadFileWithURL() {
    final String filename = "myfile1.mp3";
    final String url = "https://traffic.megaphone.fm/GLT8678602522.mp3";
    var args = <String, dynamic>{
      KEY_DOWNLOAD_URL: url,
      KEY_TARGET_FILE: filename,
      KEY_ACCENT_COLOR: 0xFF00FF00.toInt(),
      KEY_TITLE: "Downloading new content",
      KEY_TEXT: "Episode 5 - This American Life",
    };

    _channel.invokeMethod('downloadFileWithURL', args);
  }
}
