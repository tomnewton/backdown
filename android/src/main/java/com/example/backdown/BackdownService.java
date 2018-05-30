package com.example.backdown;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.content.Context;
import android.os.Build;
import android.support.annotation.NonNull;
import android.support.v4.app.JobIntentService;
import android.content.Intent;
import android.support.v4.app.NotificationCompat;
import android.support.v4.app.NotificationManagerCompat;
import android.support.v4.content.LocalBroadcastManager;
import android.util.Log;

import java.io.BufferedInputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.URL;
import java.net.URLConnection;
import java.util.Random;

public class BackdownService extends JobIntentService {

    private static final String CHANNEL_ID = "BackdownServiceChannel";// black default.
    public static final String BROADCAST_ACTION = "BroadcastAction";
    public static final String EXTENDED_DATA_SUCCESS = "Success";
    public static final String EXTENDED_DATA_FILE_LOCATION = "FileLocation";
    public static final String EXTENDED_DATA_DOWNLOAD_URL = "DownloadUrl";
    public static final String EXTENDED_DATA_ERROR_MESSAGE = "ErrorMsg";

    @Override
    protected void onHandleWork(@NonNull Intent intent) {
        // Safe to call multiple times... no-op after creation
        createNotificationChannel();
        int defaultColor = 0xFF000000; //black
        // Unpack the work to do...
        String downloadUrl = intent.getStringExtra(BackdownPlugin.DOWNLOAD_URL);
        String targetFile = intent.getStringExtra(BackdownPlugin.TARGET_FILE);
        String title = intent.getStringExtra(BackdownPlugin.TITLE);
        String text = intent.getStringExtra(BackdownPlugin.TEXT);
        int color = intent.getIntExtra(BackdownPlugin.ACCENT_COLOR, defaultColor);

        download(downloadUrl, targetFile, color, title, text);
    }

    void download(String downloadUrl, String filename, int color, String title, String text) {
        int count;
        Intent completeIntent = new Intent(BROADCAST_ACTION);
        completeIntent.putExtra(EXTENDED_DATA_DOWNLOAD_URL, downloadUrl);

        // create our temp backdown dir
        String dir = this.getFilesDir().getPath();
        File targetDir = new File(dir+"/backdown/");
        targetDir.mkdirs();

        // create a file to write to
        File target = new File(targetDir,  filename);
        try {
           target.createNewFile();
        } catch (IOException e) {
            fail(completeIntent, e.getMessage());
            return;
        }

        try {
            URL url = new URL(downloadUrl);
            URLConnection conn = url.openConnection();
            conn.connect();

            // total length
            int length = conn.getContentLength();

            // download
            InputStream input = new BufferedInputStream(url.openStream(), 8192);

            // output stream to file...
            OutputStream output = new FileOutputStream(target);

            // need a reference to the notification manager
            NotificationManagerCompat notificationManager = NotificationManagerCompat.from(this);
            Random rand = new Random();
            int notificationID = rand.nextInt();

            // buffer for reads
            byte data[] = new byte[1024];
            long total = 0;

            // do work
            while((count = input.read(data)) != -1) {
                total += count;

                output.write(data, 0, count);

                // Notification update
                final Notification note = notify(this, title, text, (int)total, length, color);
                notificationManager.notify(notificationID, note);
            }

            // flush and close.
            output.flush();
            output.close();
            input.close();

            // remove the notification
            notificationManager.cancel(notificationID);

            // fill in the intent that will be broadcast below.
            completeIntent.putExtra(EXTENDED_DATA_SUCCESS, true);
            completeIntent.putExtra(EXTENDED_DATA_FILE_LOCATION, target.getAbsolutePath());

        } catch (Exception e) {

            Log.e("Error during download.", e.getMessage());
            target.delete();
            // we failed... fill in the intent...
            fail(completeIntent, e.getMessage());
            return;
        }

        // tell the plugin you're
        LocalBroadcastManager.getInstance(this).sendBroadcast(completeIntent);
    }

    void fail(Intent intent, String errorMsg) {
        intent.putExtra(EXTENDED_DATA_SUCCESS, false);
        intent.putExtra(EXTENDED_DATA_FILE_LOCATION, "");
        intent.putExtra(EXTENDED_DATA_ERROR_MESSAGE, errorMsg);
        LocalBroadcastManager.getInstance(this).sendBroadcast(intent);
    }

    Notification notify(Context context, String title, String text, int progress, int max, int color) {
        if ( 26 <= Build.VERSION.SDK_INT  ) {
            return new Notification
                    .Builder(context, CHANNEL_ID)
                    .setSmallIcon(R.mipmap.ic_launcher)
                    .setContentTitle(title)
                    .setContentText(text)
                    .setColor(color)
                    .setProgress(max, progress, false)
                    .build();
        } else {
            return new NotificationCompat.Builder(context, CHANNEL_ID)
                    .setSmallIcon(R.mipmap.ic_launcher)
                    .setContentTitle(title)
                    .setContentText(text)
                    .setColor(color)
                    .setProgress(max, progress, false)
                    .build();
        }
    }

    private void createNotificationChannel() {
        // Create the NotificationChannel, but only on API 26+ because
        // the NotificationChannel class is new and not in the support library
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            String name = "backdown";
            int importance = NotificationManager.IMPORTANCE_DEFAULT;
            NotificationChannel channel = new NotificationChannel(CHANNEL_ID, name, importance);
            // Register the channel with the system; you can't change the importance
            // or other notification behaviors after this
            NotificationManager notificationManager = getSystemService(NotificationManager.class);
            notificationManager.createNotificationChannel(channel);
        }
    }
}
