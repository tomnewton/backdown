#import <Flutter/Flutter.h>

@interface BackdownPlugin : NSObject<FlutterPlugin, NSURLSessionDelegate, NSURLSessionDownloadDelegate>
@property (nonatomic, copy, nullable) void (^backgroundCompletionHandler)(void);
@end
