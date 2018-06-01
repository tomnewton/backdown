#import "BackdownPlugin.h"

#define DOWNLOAD_URL @"DOWNLOAD_URL"

#define COMPLETE_EVENT @"COMPLETE_EVENT"
#define KEY_SUCCESS @"SUCCESS"
#define KEY_DOWNLOAD_ID @"DOWNLOAD_ID"
#define KEY_FILE_PATH @"FILE_PATH"
#define KEY_ERROR_MESSAGE @"ERROR_MSG"

#define PROGRESS_EVENT @"PROGRESS_EVENT"
#define KEY_PROGRESS @"PROGRESS"
#define KEY_TOTAL @"TOTAL"

@implementation BackdownPlugin {
    FlutterMethodChannel* methodChannel;
    
}

+(NSString*)sessionKey{
    return @"backdownPluginKey";
}
    
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  FlutterMethodChannel* channel = [FlutterMethodChannel
      methodChannelWithName:@"backdown"
            binaryMessenger:[registrar messenger]];
    BackdownPlugin* instance = [[BackdownPlugin alloc] initWithChannel:channel];
  [registrar addMethodCallDelegate:instance channel:channel];
}
    
    
-(id)initWithChannel:(FlutterMethodChannel*)chan{
    if ( self = [super init] ) {
        methodChannel = chan;
        return self;
    }
    return nil;
}
    
-(NSURLSession*)getURLSessionDiscretionary:(bool)isDiscretionary doesSendLaunchEvents:(bool)sendsLaunchEvents {
    NSURLSessionConfiguration* config = [NSURLSessionConfiguration backgroundSessionConfigurationWithIdentifier:[BackdownPlugin sessionKey]];
    [config setDiscretionary:isDiscretionary];
    [config setSessionSendsLaunchEvents:sendsLaunchEvents];
    return [NSURLSession sessionWithConfiguration:config delegate:(id<NSURLSessionDelegate>)self delegateQueue:nil];
}

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
  if ([@"setDefaults" isEqualToString:call.method]) {
      // no op on iOS.
      // this is used to set colors/theme for Android notifications.
  } else if ([@"enqueueDownload" isEqualToString:call.method]) {
      [self enqueueDownload:call.arguments[DOWNLOAD_URL] isDiscretionary:NO doesSendLaunchEvents:YES];
  } else {
      result(FlutterMethodNotImplemented);
  }
}
    
-(void)enqueueDownload:(NSString*)urlStr
       isDiscretionary:(bool)isDiscretionary
  doesSendLaunchEvents:(bool)doesSendLaunchEvents {
    
    NSURLSession* session = [self getURLSessionDiscretionary:isDiscretionary doesSendLaunchEvents:doesSendLaunchEvents];
    NSURL* url = [NSURL URLWithString:urlStr];
    
    NSURLSessionDownloadTask* task = [session downloadTaskWithURL:url];
    
    if (@available(iOS 11, *)){
        //iOS 11 on we can let the system know how much data to expect.
        
        //Build a URL HEAD request so we can quickly fetch the headers...
        NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url];
        request.HTTPMethod = @"HEAD";
        [request addValue:@"identity" forHTTPHeaderField:@"Accept-Encoding"]; //force apache to send content-length
        
        NSURLSession* sSession = [NSURLSession sharedSession];
        
        [[sSession dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
            // handle response
            if ([response respondsToSelector:@selector(allHeaderFields)]) {
                NSDictionary *dictionary = [(NSHTTPURLResponse*)response allHeaderFields];
                //NSLog([dictionary description]);
                NSLog(@"Content-length: %@", [dictionary objectForKey:@"Content-Length"]);
                
                NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
                formatter.numberStyle = NSNumberFormatterDecimalStyle;
                NSNumber* size = [formatter numberFromString:[dictionary objectForKey:@"Content-Length"]];
                
                [task setCountOfBytesClientExpectsToReceive:[size longLongValue]];
                /// kick it off.
                [task resume];
            }
        }] resume];
    } else {
        [task resume];
    }
}
    
#pragma mark - NSURLSessionDelegate
    
-(void)URLSession:(NSURLSession*)session didBecomeInvalidWithError:(nullable NSError *)error {
    NSLog(@"Session became invalid %@", error.description);
}
    
-(void)URLSessionDidFinishEventsForBackgroundURLSession:(NSURLSession*)session {
    // All done.
}

    
#pragma mark - NSURLSessionDownloadDelegate
    
- (void)URLSession:(nonnull NSURLSession *)session
      downloadTask:(nonnull NSURLSessionDownloadTask *)downloadTask
didFinishDownloadingToURL:(nonnull NSURL *)location {
    /// we have to move the file from the temp location before
    /// returning from this method
    NSError* error;
    NSFileManager* fm = [NSFileManager defaultManager];
    NSURL *to = [self applicationDataDirectory];
    to = [to URLByAppendingPathComponent:@"backdown"];
    
    // if the backddown filder doesn't exist... create it.
    [fm createDirectoryAtURL:to withIntermediateDirectories:YES attributes:nil error:&error];
    if ( error != nil ) {
        NSString* errMsg = [error description];
        [methodChannel invokeMethod:COMPLETE_EVENT arguments:@{ KEY_SUCCESS: @NO, KEY_ERROR_MESSAGE:errMsg}];
        return;
    }
    
    // add the filename.
    to = [to URLByAppendingPathComponent:downloadTask.originalRequest.URL.lastPathComponent];

    
    NSLog(@"Path to new file: %@", to.absoluteString);
    
    BOOL moved = [fm moveItemAtURL:location toURL:to error:&error]; // [fm moveItemAtPath:[location absoluteString] toPath:[to absoluteString] error:&error]; //
    
    if ( error != nil || moved == NO){
        // big problem.
        NSString* errMsg = @"Failed to move the file";
        if ( error != nil ){
            errMsg = [error description];
        }
        [methodChannel invokeMethod:COMPLETE_EVENT arguments:@{ KEY_SUCCESS: @NO, KEY_ERROR_MESSAGE:errMsg}];
        return;
    }
    
    NSDictionary *args = @{
        KEY_SUCCESS: @YES,
        KEY_DOWNLOAD_ID: @0,
        KEY_FILE_PATH: [to relativeString],
    };
    
    [methodChannel invokeMethod:COMPLETE_EVENT arguments:args];
}
    
- (void)URLSession:(NSURLSession*)session
      downloadTask:(nonnull NSURLSessionDownloadTask*)downloadTask
      didWriteData:(int64_t)bytesWritten
 totalBytesWritten:(int64_t)totalBytesWritten
totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite {
    /// progress
    NSDictionary *args = @{
       KEY_DOWNLOAD_ID: @0,
       KEY_TOTAL: [NSNumber numberWithLongLong:totalBytesExpectedToWrite],
       KEY_PROGRESS: [NSNumber numberWithLongLong:totalBytesWritten],
    };
    [methodChannel invokeMethod:PROGRESS_EVENT arguments:args];
}
    
- (void)URLSession:(nonnull NSURLSession *)session downloadTask:(nonnull NSURLSessionDownloadTask *)downloadTask didResumeAtOffset:(int64_t)fileOffset expectedTotalBytes:(int64_t)expectedTotalBytes {
    // did resume
    NSLog(@"Download did resume for url: %@", downloadTask.originalRequest.URL.absoluteString);
}
    
#pragma mark - helpers
    
- (NSURL*)applicationDataDirectory {
    NSFileManager* sharedFM = [NSFileManager defaultManager];
    NSArray* possibleURLs = [sharedFM URLsForDirectory:NSApplicationSupportDirectory
                                             inDomains:NSUserDomainMask];
    NSURL* appSupportDir = nil;
    NSURL* appDirectory = nil;
    
    if ([possibleURLs count] >= 1) {
        // Use the first directory (if multiple are returned)
        appSupportDir = [possibleURLs objectAtIndex:0];
    }
    
    // If a valid app support directory exists, add the
    // app's bundle ID to it to specify the final directory.
    if (appSupportDir) {
        NSString* appBundleID = [[NSBundle mainBundle] bundleIdentifier];
        appDirectory = [appSupportDir URLByAppendingPathComponent:appBundleID];
    }
    
    return appDirectory;
}

    
@end
