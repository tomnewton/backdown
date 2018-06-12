package com.yyztom.backdown;

import android.app.DownloadManager;
import android.app.DownloadManager.Query;
import android.app.DownloadManager.Request;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.database.Cursor;
import android.net.Uri;
import android.os.Build;
import android.os.Handler;
import android.os.ParcelFileDescriptor;
import android.support.v4.app.NotificationCompat;
import android.support.v4.app.NotificationManagerCompat;
import android.util.Log;

import java.io.File;
import java.io.FileDescriptor;
import java.io.FileInputStream;
import java.io.FileNotFoundException;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.channels.FileChannel;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HashMap;

import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.PluginRegistry;
import io.flutter.plugin.common.PluginRegistry.Registrar;
import io.flutter.view.FlutterNativeView;

/**
 * BackdownPlugin
 */
public class BackdownPlugin extends BroadcastReceiver implements MethodCallHandler, PluginRegistry.ViewDestroyListener {
  private static final String TAG = "BackdownPlugin";

  private Registrar mRegistrar;
  private MethodChannel mChannel;
  private DownloadManager mDM;
  private Handler mHandler;
  private boolean isHandlerRunning;
  private MessageDigest mMsgDigest;

  private HashMap<String, DownloadRequest> requests = new HashMap<>();

  private int mNotificationColor = 0xFF000000;

  // Valid methods on the channel.
  private static final String METHOD_CREATE_DOWNLOAD = "createDownload";
  private static final String METHOD_ENQUEUE_DOWNLOAD = "enqueueDownload";
  private static final String METHOD_SET_DEFAULTS = "setDefaults";
  private static final String METHOD_CANCEL_DOWNLOAD = "cancelDownload";

  private static final String CHANNEL_ID = "backdownPluginChannel";
  // event name keys
  private static final String COMPLETE_EVENT = "COMPLETE_EVENT";
  private static final String PROGRESS_EVENT = "PROGRESS_EVENT";

  // args keys
  private static final String DOWNLOAD_URL = "DOWNLOAD_URL";
  private static final String DOWNLOAD_ID = "DOWNLOAD_ID";
  private static final String TITLE = "TITLE";
  private static final String DESCRIPTION = "DESCRIPTION";
  private static final String WIFI_ONLY = "WIFI_ONLY";
  private static final String REQUIRES_CHARGING = "REQUIRED_CHARGING";
  private static final String REQUIRES_DEVICE_IDLE = "REQUIRES_DEVICE_IDLE";
  private static final String SHOW_NOTIFICATION = "SHOW_NOTIFICATION";

  private static final String FILE_PATH = "FILE_PATH";
  private static final String SUCCESS = "SUCCESS";
  private static final String ERROR_MSG = "ERROR_MSG";
  private static final String TOTAL = "TOTAL";
  private static final String PROGRESS = "PROGRESS";

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

    Context ctx = getActiveContext();

    mDM = ( DownloadManager )ctx.getSystemService(Context.DOWNLOAD_SERVICE);
    mHandler = new Handler();
    try {
      mMsgDigest = MessageDigest.getInstance("MD5");
    } catch (NoSuchAlgorithmException e) {
      Log.e(TAG, e.getMessage());
    }

    createNotificationChannel();

    IntentFilter filter = new IntentFilter(
      DownloadManager.ACTION_DOWNLOAD_COMPLETE
    );

    // so we don't leak the receiver that we add below
    registrar.addViewDestroyListener(this);
    // add the receiver.
    ctx.registerReceiver(this, filter);

    if ( countActiveDownloads() > 0 ) {
      startProgressChecking();
    }
  }

  @Override
  public void onMethodCall(MethodCall call, Result result) {
    switch (call.method) {
      case METHOD_CREATE_DOWNLOAD:
        createDownload(call, result);
        break;
      case METHOD_ENQUEUE_DOWNLOAD:
        enqueueDownload(call, result);
        break;
      case METHOD_CANCEL_DOWNLOAD:
        String dId = call.argument(DOWNLOAD_ID);
        cancelDownload(dId, result);
        break;
      case METHOD_SET_DEFAULTS:
        long color = call.argument("color");
        mNotificationColor = (int)color;
        break;
      default:
        result.notImplemented();
    }
  }

  private void createDownload(MethodCall call, Result result ) {
    Uri uri = Uri.parse(call.argument(DOWNLOAD_URL).toString());
    boolean wifiOnly = call.argument(WIFI_ONLY);
    boolean requiresCharging = call.argument(REQUIRES_CHARGING);
    boolean requiresDeviceIdle = call.argument(REQUIRES_DEVICE_IDLE);
    boolean showNotification = call.argument(SHOW_NOTIFICATION);
    String title = call.argument(TITLE);
    String description = call.argument(DESCRIPTION);
    DownloadRequest request = new DownloadRequest(
            uri,
            title,
            description,
            wifiOnly,
            requiresCharging,
            requiresDeviceIdle,
            showNotification);
    this.requests.put(request.getDownloadId(), request);
    result.success(request.getDownloadId());
  }


  private void cancelDownload(String downloadId, Result result) {
    HashMap<String, Object> args = new HashMap<>();
    Query query = new Query();
    Cursor c = mDM.query(query);

    if (c.moveToFirst())
    {
      do {
        String url = c.getString(c.getColumnIndex(DownloadManager.COLUMN_URI));
        if ( getMD5(url).equals(downloadId) ) {
          long id = c.getLong(c.getColumnIndex(DownloadManager.COLUMN_ID));
          int numDeleted = mDM.remove(id);
          if ( numDeleted > 0 ) {
            args.put(SUCCESS, true);
          } else {
            args.put(SUCCESS, false);
          }
          result.success(args);
          return;
        }
      } while(c.moveToNext());
    }

    if( !args.containsKey(SUCCESS) ) {
      args.put(SUCCESS, false);
      result.success(args);
    }
  }


  /**
   * Enqueues a download with the DownloadManager.
   */
  private void enqueueDownload(MethodCall call, Result result) {
    String downloadId = call.argument(DOWNLOAD_ID);
    HashMap<String, Object> args = new HashMap<>();
    if (!requests.containsKey(downloadId)) {
      args.put(SUCCESS, false);
      result.success(args);
      return;
    }

    DownloadRequest r = requests.get(downloadId);
    Request request = new Request(r.uri);
    request.setTitle(r.title);
    request.setDescription(r.description);
    request.setVisibleInDownloadsUi(false);
    request.setNotificationVisibility(Request.VISIBILITY_HIDDEN);

    if (r.wifiOnly) {
      request.setAllowedNetworkTypes(Request.NETWORK_WIFI);
    } else {
      request.setAllowedNetworkTypes(Request.NETWORK_MOBILE|Request.NETWORK_WIFI);
    }

    if (Build.VERSION.SDK_INT >= 24 && r.requiresCharging) {
      request.setRequiresCharging(true);
    }

    if (Build.VERSION.SDK_INT >= 24 && r.requiresDeviceIdle) {
      request.setRequiresDeviceIdle(true);
    }

    mDM.enqueue(request);

    startProgressChecking();

    args.put(SUCCESS, true);
    result.success(args);
  }

  private Context getActiveContext() {
    return (mRegistrar.activity() != null) ? mRegistrar.activity() : mRegistrar.context();
  }

  private int countActiveDownloads() {
    Query query = new Query();
    query.setFilterByStatus(DownloadManager.STATUS_RUNNING);
    Cursor c = mDM.query(query);
    return c.getCount();
  }

  @Override
  public void onReceive(Context context, Intent intent) {
    // handle our broadcast actions.
    // let's see if we were successful...
    final String action = intent.getAction();
    if ( action == null ){
      return;
    }

    NotificationManagerCompat notificationManager = NotificationManagerCompat.from(getActiveContext());

    if ( action.equals(DownloadManager.ACTION_DOWNLOAD_COMPLETE) ) {
      long id = intent.getLongExtra(DownloadManager.EXTRA_DOWNLOAD_ID, 0);


      Query query = new Query();
      query.setFilterById(id);

      Cursor c = mDM.query(query);

      if (c.moveToFirst()) {
        HashMap<String, Object> args = new HashMap<>();

        // We will return the id for consistency.
        // Clients can use this id to keep track of the download
        // jobs requested.
        String originalUrl = c.getString(c.getColumnIndex(DownloadManager.COLUMN_URI));
        String downloadId = getMD5(originalUrl);

        args.put(DOWNLOAD_ID, downloadId);

        // get the downloads status
        int status = c.getInt(c.getColumnIndex(DownloadManager.COLUMN_STATUS));

        if ( DownloadManager.STATUS_SUCCESSFUL == status) {
          // Let the notification finish...
          String title = c.getString(c.getColumnIndex(DownloadManager.COLUMN_TITLE));
          String text = "Processing...";

          // Set the notification
          // this will disappear automatically after 5s
          // but we do clear it in the positive path.
          Notification note = buildIndeterminateNotification(context, title, text);
          notificationManager.notify((int)id, note);

          // Clean it out of our requests objects.
          requests.remove(downloadId);


          // Successfully downloaded by the DownloadManager
          // Now we need to find the file, and move it to where we can
          // use it in the app and ensure it won't be cleared up by the system.
          // by default we move it into the data directory for our app.
          String uri = c.getString(c.getColumnIndex(DownloadManager.COLUMN_LOCAL_URI));
          FileDescriptor fd = getFileDescriptor(uri);
          if ( fd == null ) {
            sendFailure(COMPLETE_EVENT, "Failed to get file descriptor for downloaded file.");
            return;
          }
          /// The DownloadManager puts our files into a cache directory that can
          /// be cleaned up by the system at any point. We need to move this into a
          /// the apps files directory.
          String newPath = getActiveContext().getFilesDir() + File.separator + "backdown";
          File dstDir = new File(newPath); // just the dir.
          Uri downloadUri = Uri.parse(originalUrl);
          try {
            // find the filename from the originally downloaded url
            String filename = downloadUri.getLastPathSegment();

            // Move the file to the new location.
            File newFile = copyFile(new FileInputStream(fd), dstDir, filename);

            // If we fail for some weird reason, we'll get null back.
            // So tell the client we had a failure with this file.
            if ( newFile == null ) {
              sendFailure(COMPLETE_EVENT, "failed copying file.");
              return;
            }

            // set FILE_PATH
            args.put(FILE_PATH, newFile.getAbsolutePath());

          } catch (IOException e) {
            // Something went wrong during the copy... not good.
            Log.e(TAG, e.toString());
            sendFailure(COMPLETE_EVENT, e.getMessage());
            return;
          } finally {
            // This file will eventually get cleaned up anyways
            // but we'll be responsible and remove it explicitly.
            mDM.remove(id);
            c.close();
          }

          // Ready to send if we reach here.
          // successfully downloaded file, and moved to the backdown folder in our apps data
          // directory.
          args.put(SUCCESS, true);

          // send
          mChannel.invokeMethod(COMPLETE_EVENT, args);
          // end
        } else if (DownloadManager.STATUS_FAILED == status) {
          // failed..
          String reason = errorToString(c.getInt(c.getColumnIndex(DownloadManager.COLUMN_REASON)));
          sendFailure(COMPLETE_EVENT, reason);
        }
      }
      // clean up.
      c.close();
      stopProgressChecking();
      notificationManager.cancel((int)id);
    }
  }

  /**
   * Look at Running and Pending Downloads
   * and render notifications for them.
   */
  private void updateNotifications() {
    // We need to query using the id...
    Query query = new Query();
    query.setFilterByStatus(DownloadManager.STATUS_RUNNING|DownloadManager.STATUS_PENDING);
    Cursor c = mDM.query(query);

    if ( c.moveToFirst() ) {
      do {
        int size = c.getInt(c.getColumnIndex(DownloadManager.COLUMN_TOTAL_SIZE_BYTES));
        int progress = c.getInt(c.getColumnIndex(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR));
        String title = c.getString(c.getColumnIndex(DownloadManager.COLUMN_TITLE));
        long id = c.getLong(c.getColumnIndex(DownloadManager.COLUMN_ID));
        String status = c.getInt(c.getColumnIndex(DownloadManager.COLUMN_STATUS)) == DownloadManager.STATUS_PENDING ? "Queued.." : "Downloading..";
        String originalUrl = c.getString(c.getColumnIndex(DownloadManager.COLUMN_URI));
        String downloadId = getMD5(originalUrl);

        if ( requests.containsKey(downloadId) && requests.get(downloadId).showNotification ) {
          // show the notification.
          Notification note = buildNotification(getActiveContext(), title, status, progress, size);
          NotificationManagerCompat notificationManager = NotificationManagerCompat.from(getActiveContext());
          notificationManager.notify(Math.round(id), note);
        }

        HashMap<String, Object> args = new HashMap<>();
        args.put(PROGRESS, progress);
        args.put(TOTAL, size);
        args.put(DOWNLOAD_ID, downloadId);
        mChannel.invokeMethod(PROGRESS_EVENT, args);
      } while (c.moveToNext());
    }

    stopProgressChecking();

    c.close();
  }

  /**
   * Will invoke a method on the MethodChannel.
   * @param method - a supported method on the client.
   * @param errorMsg - the error message.
   */
  private void sendFailure(String method, String errorMsg) {
    stopProgressChecking();
    HashMap<String, Object> args = new HashMap<>();
    args.put(SUCCESS, false);
    args.put(ERROR_MSG, errorMsg);
    mChannel.invokeMethod(method, args);
  }

  /**
   * Get a fileDescriptor from a string path which will be parsed to a Uri.
   * @param uri - String
   * @return a FileDescriptor.
   */
  private FileDescriptor getFileDescriptor(String uri) {
    try {
      ParcelFileDescriptor pfd = getActiveContext().getContentResolver().openFileDescriptor(Uri.parse(uri), "r");
      if (pfd != null) {
        return pfd.getFileDescriptor();
      } else {
        Log.e(TAG, "Couldn't retrieve file descriptor.");
        return null;
      }
    } catch (IOException e) {
      return null;
    }
  }

  /**
   * Copies a file from the given InputStream to the dstDir/filename
   * @param src - the FileInputStream that contains the data for the result file.
   * @param dstDir - the destination directory - will be created if necessary.
   * @param filename - the filename to use for the result file.
   * @return a new file with the contents of src in dstDir/filename
   * @throws IOException
   */
  private File copyFile(FileInputStream src, File dstDir, String filename) throws IOException {
    if (!dstDir.exists()) {
      if (!dstDir.mkdirs()) {
        return null;
      }
    }

    File outputFile = new File(dstDir.getPath() + File.separator + filename);

    FileChannel in = null;
    FileChannel out = null;
    try {
      in = src.getChannel();
      out = new FileOutputStream(outputFile).getChannel();
      in.transferTo(0, in.size(), out);
    } catch(FileNotFoundException e) {
      Log.e(TAG, e.toString());
    } finally {
      if (in != null) {
        in.close();
      }
      if ( out != null ) {
        out.close();
      }
    }
    return outputFile;
  }


  String errorToString(int error) {
    // https://developer.android.com/reference/android/app/DownloadManager#column_reason
    switch(error)  {
      case DownloadManager.ERROR_CANNOT_RESUME:
        return "ERROR_CANNOT_RESUME";
      case DownloadManager.ERROR_DEVICE_NOT_FOUND:
        return "ERROR_DEVICE_NOT_FOUOND";
      case DownloadManager.ERROR_FILE_ERROR:
        return "ERROR_FILE_ERROR";
      case DownloadManager.ERROR_HTTP_DATA_ERROR:
        return "ERROR_HTTP_DATA_ERROR";
      case DownloadManager.ERROR_FILE_ALREADY_EXISTS:
        return "ERROR_FILE_ALREADY_EXISTS";
      case DownloadManager.ERROR_INSUFFICIENT_SPACE:
        return "ERROR_INSUFFICIENT_SPACE";
      case DownloadManager.ERROR_TOO_MANY_REDIRECTS:
        return "ERROR_TOO_MANY_REDIRECTS";
      case DownloadManager.ERROR_UNHANDLED_HTTP_CODE:
        return "ERROR_UNHANDLED_HTTP_CODE";
      case DownloadManager.ERROR_UNKNOWN:
        return "ERROR_UNKNOWN";
      default:
        return "HTTP_STATUS_CODE: " + Integer.toString(error);
    }
  }



  Notification buildNotification(Context context, String title, String text, int progress, int max) {
    return buildNotification(context, title, text, progress, max, false,false, 0);
  }

  Notification buildIndeterminateNotification(Context context, String title, String status) {
    // having these disappear if we haven't canceled them in a reaonable amount of time.
    // just as a precaution.
    return buildNotification(context, title, status, 1, 1, true, true, 5000);
  }

  Notification buildNotification(Context context, String title, String text, int progress, int max, boolean indeterminate, boolean setTimeout, int timeoutMs) {
    if ( 26 <= Build.VERSION.SDK_INT  ) {
      Notification.Builder builder = new Notification.Builder(context, CHANNEL_ID);
      builder.setSmallIcon(R.mipmap.ic_launcher)
      .setContentTitle(title)
      .setContentText(text)
      .setColor(mNotificationColor)
      .setProgress(max, progress, indeterminate);

      if ( setTimeout ) {
        builder.setTimeoutAfter(timeoutMs);
      }
      return builder.build();

    } else {
      NotificationCompat.Builder builder = new NotificationCompat.Builder(context, CHANNEL_ID);
      builder.setSmallIcon(R.mipmap.ic_launcher)
      .setContentTitle(title)
      .setContentText(text)
      .setColor(mNotificationColor)
      .setProgress(max, progress, false)
      .setSound(null);

      if ( setTimeout ) {
        builder.setTimeoutAfter(timeoutMs);
      }
      return builder.build();
    }
  }

  private void createNotificationChannel() {
    // Create the NotificationChannel, but only on API 26+ because
    // the NotificationChannel class is new and not in the support library
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      NotificationChannel channel = new NotificationChannel(CHANNEL_ID, "backdown", NotificationManager.IMPORTANCE_DEFAULT);
      channel.setSound(null, null);
      // Register the channel with the system; you can't change the importance
      // or other notification behaviors after this
      NotificationManager notificationManager = getActiveContext().getSystemService(NotificationManager.class);
      if (notificationManager != null) {
        notificationManager.createNotificationChannel(channel);
      }
    }
  }

  // PROGRESS CHECKING ...
  private void startProgressChecking() {
    if(!isHandlerRunning) {
      progressChecker.run();
      isHandlerRunning = true;
    }
  }

  private void stopProgressChecking() {
    stopProgressChecking(false);
  }

  private void stopProgressChecking(boolean force) {
    // finally check if this was the last active download.
    if ( countActiveDownloads() == 0 || force ) {
      mHandler.removeCallbacks(progressChecker);
      isHandlerRunning = false;
    }
  }

  /**
   * Checks download progress and updates status, then re-schedules itself.
   */
  private Runnable progressChecker = new Runnable() {
    @Override
    public void run() {
      try {
        updateNotifications();
      } finally {
        mHandler.postDelayed(progressChecker, 1000);
      }
    }
  };

  /**
   * Hash
   */
  private String getMD5(String str) {
    mMsgDigest.reset();
    mMsgDigest.update(str.getBytes());
    byte[] digest = mMsgDigest.digest();
    StringBuffer sb = new StringBuffer();
    for (byte b : digest) {
      sb.append(String.format("%02x", b & 0xff));
    }
    return sb.toString();
  }

  @Override
  public boolean onViewDestroy(FlutterNativeView flutterNativeView) {
    getActiveContext().unregisterReceiver(this);
    return false;
  }

  private class DownloadRequest {
    private String _downloadId;
    Uri uri;
    String title;
    String description;
    boolean wifiOnly;
    boolean requiresCharging;
    boolean requiresDeviceIdle;
    boolean showNotification;

    DownloadRequest(Uri uri, String title, String description, boolean wifiOnly, boolean requiresCharging, boolean requiresDeviceIdle, boolean showNotification) {
      this.uri = uri;
      this.title = title;
      this.description = description;
      this.wifiOnly = wifiOnly;
      this.requiresCharging = requiresCharging;
      this.requiresDeviceIdle = requiresDeviceIdle;
      this.showNotification = showNotification;
    }

    private String getDownloadId(){
      if ( _downloadId == null ) {
        _downloadId = getMD5(this.uri.toString());
      }
      return _downloadId;
    }
  }
}


