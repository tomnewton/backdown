#import <Flutter/Flutter.h>

@interface BackdownPlugin : NSObject<FlutterPlugin, NSURLSessionDelegate, NSURLSessionDownloadDelegate>
@property (nonatomic, copy, nullable) void (^backgroundCompletionHandler)(void);
@property (nonatomic, retain, nonnull) FlutterMethodChannel* methodChannel;
@property (nonatomic, retain, nonnull) NSMutableDictionary* requests;
@end
