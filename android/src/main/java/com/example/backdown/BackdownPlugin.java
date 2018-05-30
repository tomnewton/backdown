package com.example.backdown;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.support.v4.content.LocalBroadcastManager;
import android.util.Log;

import java.util.HashMap;

import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.PluginRegistry.Registrar;

/**
 * BackdownPlugin
 */
public class BackdownPlugin extends BroadcastReceiver implements MethodCallHandler {
  private static final int DOWNLOAD_JOB_ID = 8888;
  private static final String TAG = "BackdownPlugin";

  private Registrar mRegistrar;
  private MethodChannel mChannel;

  // keys
  public static final String DOWNLOAD_URL = "DOWNLOAD_URL";
  public static final String TARGET_FILE = "TARGET_FILE";
  public static final String ACCENT_COLOR = "ACCENT_COLOR";
  public static final String TITLE = "TITLE";
  public static final String TEXT = "TEXT";
  public static final String FILE_PATH = "FILE_PATH";
  public static final String SUCCESS = "SUCCESS";
  public static final String ERROR_MSG = "ERROR_MSG";

  /**
   * Plugin registration.
   */
  public static void registerWith(Registrar registrar) {
    final MethodChannel channel = new MethodChannel(registrar.messenger(), "backdown");
    channel.setMethodCallHandler(new BackdownPlugin(registrar, channel));
  }

  private BackdownPlugin(Registrar registrar, MethodChannel channel) {
    mRegistrar = registrar;
    mChannel = channel;

    IntentFilter filter = new IntentFilter(
      BackdownService.BROADCAST_ACTION
    );

    LocalBroadcastManager.getInstance(getActiveContext()).registerReceiver(this, filter);
  }

  @Override
  public void onMethodCall(MethodCall call, Result result) {
    if (call.method.equals("downloadFileWithURL")) {
      String url = call.argument(DOWNLOAD_URL);
      String targetFile = call.argument(TARGET_FILE);
      long color = call.argument(ACCENT_COLOR);
      String title = call.argument(TITLE);
      String text = call.argument(TEXT);

      Log.d(TAG, "Queueing download for url: " + url);

      // Create a new intent.
      Intent intent = new Intent();
      intent.putExtra(DOWNLOAD_URL, url);
      intent.putExtra(TARGET_FILE, targetFile);
      intent.putExtra(TITLE, title);
      intent.putExtra(ACCENT_COLOR, (int) color);
      intent.putExtra(TEXT, text);

      // Enqueue the work
      BackdownService.enqueueWork(getActiveContext(), BackdownService.class, DOWNLOAD_JOB_ID, intent);
    } else {
      result.notImplemented();
    }
  }

  private Context getActiveContext(){
    return (mRegistrar.activity() != null) ? mRegistrar.activity() : mRegistrar.context();
  }

  @Override
  public void onReceive(Context context, Intent intent) {
    // handle our broadcast actions.
    // let's see if we were successful...
    final boolean success = intent.getBooleanExtra(BackdownService.EXTENDED_DATA_SUCCESS, false);
    final String filePath = intent.getStringExtra(BackdownService.EXTENDED_DATA_FILE_LOCATION);
    final String downloadUrl = intent.getStringExtra(BackdownService.EXTENDED_DATA_DOWNLOAD_URL);

    HashMap<String, Object> args = new HashMap<String, Object>(){{
      put(DOWNLOAD_URL, downloadUrl);
      put(FILE_PATH, filePath);
      put(SUCCESS, success);
    }};

    if ( success ) {
      Log.d(TAG, "Download successful. " + downloadUrl + " -> " + filePath);
    } else {
      final String errorMessage = intent.getStringExtra(BackdownService.EXTENDED_DATA_ERROR_MESSAGE);

      Log.e(TAG, "Download failed for file " + downloadUrl + ", Error Message: " + errorMessage);
      args.put(ERROR_MSG, errorMessage);
    }

    // tell the dart client
    mChannel.invokeMethod("event", args);
  }
}
