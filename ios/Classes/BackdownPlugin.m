#import "BackdownPlugin.h"
#import <CommonCrypto/CommonDigest.h>
#import "BackdownRequest.h"

#define DOWNLOAD_URL @"DOWNLOAD_URL"
#define WIFI_ONLY @"WIFI_ONLY"
#define REQUIRES_CHARGING @"REQUIRED_CHARGING"

#define COMPLETE_EVENT @"COMPLETE_EVENT"
#define KEY_SUCCESS @"SUCCESS"
#define KEY_DOWNLOAD_ID @"DOWNLOAD_ID"
#define KEY_FILE_PATH @"FILE_PATH"
#define KEY_ERROR_MESSAGE @"ERROR_MSG"

#define PROGRESS_EVENT @"PROGRESS_EVENT"
#define KEY_PROGRESS @"PROGRESS"
#define KEY_TOTAL @"TOTAL"

#define READY_EVENT @"READY_EVENT"

#define URL_SESSION_KEY_INTERACTIVE @"BACKDOWN_INTERACTIVE"
#define URL_SESSION_KEY_DISCRETIONARY @"BACKDOWN_DISCRETIONARY"

@implementation BackdownPlugin

+(NSString*)sessionKey{
    return @"BACKDOWN_PLUGIN_SESSION_KEY";
}

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
    FlutterMethodChannel* channel = [FlutterMethodChannel
                                     methodChannelWithName:@"backdown"
                                     binaryMessenger:[registrar messenger]];
    BackdownPlugin* instance = [[BackdownPlugin alloc] initWithChannel:channel andRegistrar:registrar];
    [registrar addMethodCallDelegate:instance channel:channel];
}

-(id)initWithChannel:(FlutterMethodChannel*)chan andRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar{
    if ( self = [super init] ) {
        self.methodChannel = chan;
        self.requests = [NSMutableDictionary dictionary];
        [registrar addApplicationDelegate:self];
        
        return self;
    }
    return nil;
}

-(NSString*)getNSURLSessionIdentifier:(BOOL)discretionary {
    NSString* bundleId = [[NSBundle mainBundle] bundleIdentifier];
    
    if ( discretionary ){
         return [NSString stringWithFormat:@"%@-%@", bundleId, @"discretionary"];
    }
    
    return [NSString stringWithFormat:@"%@-%@", bundleId, @"interactive"];
}

-(void)initURLSessions{
    if ( self.interactiveSession == nil && self.discretionarySession == nil ) {
        // create our two NSURLSessions
        // first the interactive Session.
        
        NSString* interactiveId = [self getNSURLSessionIdentifier:NO];
        
        NSURLSessionConfiguration* interactiveConfing = [NSURLSessionConfiguration backgroundSessionConfigurationWithIdentifier:interactiveId];
        [interactiveConfing setDiscretionary:NO];
        [interactiveConfing setSessionSendsLaunchEvents:NO];
        
        self.interactiveSession = [NSURLSession sessionWithConfiguration:interactiveConfing delegate:(id<NSURLSessionDelegate>)self delegateQueue:nil];
        
        // now the discretionary NSURLSession
        NSString* discretionaryId = [self getNSURLSessionIdentifier:YES];
        
        NSURLSessionConfiguration* discretinaryConfig = [NSURLSessionConfiguration backgroundSessionConfigurationWithIdentifier:discretionaryId];
        [discretinaryConfig setDiscretionary:YES];
        [discretinaryConfig setSessionSendsLaunchEvents:YES];
        
        self.discretionarySession = [NSURLSession sessionWithConfiguration:discretinaryConfig delegate:(id<NSURLSessionDelegate>)self delegateQueue:nil];
        
        // Tell our dart code that we're initialised and ready to
        // enqueue downloads, and broadcast events.
        [self.methodChannel invokeMethod:READY_EVENT arguments:nil];
    }
}

-(NSURLSession*)getURLSessionDiscretionary:(bool)isDiscretionary{
    if ( isDiscretionary == YES ) {
        return self.discretionarySession;
    }
    return self.interactiveSession;
}

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
    if ([@"setDefaults" isEqualToString:call.method]) {
        // no op on iOS.
        // this is used to set colors/theme for Android notifications.
    } else if ( [@"createDownload" isEqualToString:call.method]) {
        NSString* url = call.arguments[DOWNLOAD_URL];
        NSString* md5 = [self MD5String:url];
        
        // figure out if this is discretionary
        BOOL wifiOnly = [[call.arguments objectForKey:WIFI_ONLY] boolValue];
        BOOL requiresCharging = [[call.arguments objectForKey:REQUIRES_CHARGING] boolValue];
        
        // create the request.
        BackdownRequest* request = [[BackdownRequest alloc] initWithUrl:url andDownloadId:md5 isDiscretionary:(wifiOnly  || requiresCharging)];
        
        // save it for later.
        [self.requests setObject:request forKey:md5];
        result(md5);
        
    } else if ([@"enqueueDownload" isEqualToString:call.method]) {
        NSString *downloadId = call.arguments[KEY_DOWNLOAD_ID];
        BackdownRequest* request = [self.requests objectForKey:downloadId];
        if ( request == nil ) {
            result(@{KEY_SUCCESS: @NO});
            return;
        }
        // send the request to the system.
        [self enqueueDownload:request.url isDiscretionary:request.isDiscretionary doesSendLaunchEvents:YES];
        result(@{KEY_SUCCESS: @YES});
        
        // remove the reference to the download.
        [self.requests removeObjectForKey:downloadId];
    } else if ([@"cancelDownload" isEqualToString:call.method]) {
        NSString* downloadId = call.arguments[KEY_DOWNLOAD_ID];
        [self cancelDownload:downloadId andFlutterResult:result];
    } else if ([@"ready" isEqualToString:call.method] ) {
        // all the flutter client to tell us when you create the URLSessions
        // to ensure they're ready for events.
        [self initURLSessions];
    } else {
        result(FlutterMethodNotImplemented);
    }
}

-(void)cancelDownload:(NSString*)downloadId andFlutterResult:(FlutterResult)result {
    NSURLSession* session = [self getURLSessionDiscretionary:NO];
    
    [session getTasksWithCompletionHandler:^(NSArray<NSURLSessionDataTask *> * _Nonnull dataTasks, NSArray<NSURLSessionUploadTask *> * _Nonnull uploadTasks, NSArray<NSURLSessionDownloadTask *> * _Nonnull downloadTasks) {
        for (NSURLSessionTask* task in downloadTasks) {
            NSString* md5 = [self MD5String:[task.originalRequest.URL absoluteString]];
            if ( [md5 isEqualToString:downloadId] ) {
                [task cancel];
                result(@{KEY_SUCCESS: @YES});
            }
        }
        result(@{KEY_SUCCESS: @NO});
    }];
}

-(void)enqueueDownload:(NSString*)urlStr
       isDiscretionary:(bool)isDiscretionary
  doesSendLaunchEvents:(bool)doesSendLaunchEvents {
    NSLog(@"Enqueueing %@", urlStr);
    
    NSURLSession* session = [self getURLSessionDiscretionary:isDiscretionary];
    NSURL* url = [NSURL URLWithString:urlStr];
    
    NSURLSessionDownloadTask* task = [session downloadTaskWithURL:url];
    
    NSLog(@"creating task");
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
                NSLog(@"kicking off job");
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
    // If we stored a backgroundCompletionHandler - call it.
    if ( [session.configuration.identifier isEqualToString:[self getNSURLSessionIdentifier:NO]] ) {
        if ( self.backgroundCompletionHandlerForInteractive != nil ) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.backgroundCompletionHandlerForInteractive();
            });
        }
    } else {
        if ( self.backgroundCompletionHandlerForDiscretionary != nil ) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.backgroundCompletionHandlerForDiscretionary();
            });
        }
    }
}


#pragma mark - NSURLSessionDownloadDelegate

- (void)URLSession:(nonnull NSURLSession *)session
      downloadTask:(nonnull NSURLSessionDownloadTask *)downloadTask
didFinishDownloadingToURL:(nonnull NSURL *)location {
    NSLog(@"Complete");
    /// we have to move the file from the temp location before
    /// returning from this method
    NSString* downloadId = [self MD5String:downloadTask.originalRequest.URL.absoluteString];
    
    NSInteger status = [(NSHTTPURLResponse*)downloadTask.response statusCode];
    if (status < 200 || 299 < status ){
        NSString* errMsg = [NSString stringWithFormat:@"HTTP Status was: %ld", (long)status];
        [self sendFlutterEvent:COMPLETE_EVENT withErrorMessage:errMsg forDownloadId:downloadId];
        return;
    }
    
    if( downloadTask.state == NSURLSessionTaskStateCanceling ) {
        //apparently from stackoverflow you can sometimes have this delegate method called
        // when you've asked to cancel a download. Since we've implemented that above,
        // we'll just guard against that.
        return;
    }
    
    NSError* error;
    NSFileManager* fm = [NSFileManager defaultManager];
    NSURL *to = [self applicationDataDirectory];
    to = [to URLByAppendingPathComponent:@"backdown"];
    
    // if the backddown filder doesn't exist... create it.
    [fm createDirectoryAtURL:to withIntermediateDirectories:YES attributes:nil error:&error];
    if ( error != nil ) {
        NSString* errMsg = [error description];
        [self sendFlutterEvent:COMPLETE_EVENT withErrorMessage:errMsg forDownloadId:downloadId];
        return;
    }
    
    // add the filename.
    to = [to URLByAppendingPathComponent:downloadTask.originalRequest.URL.lastPathComponent];
    
    NSLog(@"Path to new file: %@", to.absoluteString);
    
    if ([fm fileExistsAtPath:[to relativePath]]) {
        NSError* removeErr;
        [fm removeItemAtURL:to error:&removeErr];
        if ( removeErr != nil ) {
            return [self sendFlutterEvent:COMPLETE_EVENT withErrorMessage:[removeErr debugDescription] forDownloadId:downloadId];
        }
    }
    
    BOOL moved = [fm moveItemAtURL:location toURL:to error:&error]; 
    
    if ( error != nil || moved == NO){
        // big problem.
        NSString* errMsg = @"Failed to move the file";
        if ( error != nil ){
            errMsg = [error description];
        }
        return [self sendFlutterEvent:COMPLETE_EVENT withErrorMessage:errMsg forDownloadId:downloadId];
    }
    
    
    NSDictionary *args = @{
                           KEY_SUCCESS: @YES,
                           KEY_DOWNLOAD_ID: downloadId,
                           KEY_FILE_PATH: [to absoluteString],
                           };
    
    [self.methodChannel invokeMethod:COMPLETE_EVENT arguments:args];
}

-(void)URLSession:(NSURLSession*)session task:(nonnull NSURLSessionTask *)task didCompleteWithError:(nullable NSError *)error {
    if ( error != nil ){
        NSLog(@"ERROR: %@", error.debugDescription);
        NSLog(@"Localized: %@", error.localizedDescription);
        
        NSString *downloadId = [self MD5String:task.originalRequest.URL.absoluteString];
        [self sendFlutterEvent:COMPLETE_EVENT withErrorMessage:error.localizedDescription forDownloadId:downloadId];
    }
}

- (void)URLSession:(NSURLSession*)session
      downloadTask:(nonnull NSURLSessionDownloadTask*)downloadTask
      didWriteData:(int64_t)bytesWritten
 totalBytesWritten:(int64_t)totalBytesWritten
totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite {
    //NSLog(@"Progress for file");
    /// progress
    NSString* downloadId = [self MD5String:downloadTask.originalRequest.URL.absoluteString];
    
    NSDictionary *args = @{
                           KEY_DOWNLOAD_ID: downloadId,
                           KEY_TOTAL: [NSNumber numberWithLongLong:totalBytesExpectedToWrite],
                           KEY_PROGRESS: [NSNumber numberWithLongLong:totalBytesWritten],
                           };
    [self.methodChannel invokeMethod:PROGRESS_EVENT arguments:args];
}

- (void)URLSession:(nonnull NSURLSession *)session downloadTask:(nonnull NSURLSessionDownloadTask *)downloadTask didResumeAtOffset:(int64_t)fileOffset expectedTotalBytes:(int64_t)expectedTotalBytes {
    // did resume
    NSLog(@"Download did resume for url: %@", downloadTask.originalRequest.URL.absoluteString);
}


#pragma mark - AppDelegate methods
- (BOOL)application:(UIApplication*)application
handleEventsForBackgroundURLSession:(nonnull NSString*)identifier
  completionHandler:(nonnull void (^)(void))completionHandler {
    
    NSString* discretionary = [self getNSURLSessionIdentifier:YES];
    NSString* interactive = [self getNSURLSessionIdentifier:NO];
  
    if ( [discretionary isEqualToString:identifier] ) {
      
      self.backgroundCompletionHandlerForDiscretionary = completionHandler;

    } else if ([interactive isEqualToString:identifier]) {
      
      self.backgroundCompletionHandlerForInteractive = completionHandler;

    } else {
      
      NSException *exception = [NSException exceptionWithName:@"Unknown idenfier" reason:@"Unknown identifier" userInfo:@{@"Localized key": [NSString stringWithFormat:@"Unknown identifier: %@", identifier]}];
      [exception raise];
    }
    
    return YES;
}

#pragma mark - helpers

- (NSURL*)applicationDataDirectory {
    NSFileManager* sharedFM = [NSFileManager defaultManager];
    NSArray* possibleURLs = [sharedFM URLsForDirectory:NSDocumentDirectory
                                             inDomains:NSUserDomainMask];
    NSURL* appDocsDirectory = nil;
    
    if ([possibleURLs count] >= 1) {
        // Use the first directory (if multiple are returned)
        appDocsDirectory = [possibleURLs objectAtIndex:0];
    }
    
    return appDocsDirectory;
}

- (NSString *)MD5String:(NSString*)input {
    const char *cStr = [input UTF8String];
    unsigned char result[CC_MD5_DIGEST_LENGTH];
    CC_MD5( cStr, (CC_LONG)strlen(cStr), result );
    
    return [NSString stringWithFormat:
            @"%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x",
            result[0], result[1], result[2], result[3],
            result[4], result[5], result[6], result[7],
            result[8], result[9], result[10], result[11],
            result[12], result[13], result[14], result[15]
            ];
}



- (void)sendFlutterEvent:(NSString*)event withErrorMessage:(NSString*)errorMessage forDownloadId:(NSString*)downloadId {
    [self.methodChannel invokeMethod:event arguments:@{ KEY_SUCCESS: @NO, KEY_ERROR_MESSAGE:errorMessage, KEY_DOWNLOAD_ID: downloadId}];
}


@end
