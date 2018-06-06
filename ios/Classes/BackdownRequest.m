//
//  BackdownRequest.m
//  backdown
//
//  Created by Tom Newton on 06/06/2018.
//

#import "BackdownRequest.h"

@implementation BackdownRequest

-(id)initWithUrl:(NSString*)url andDownloadId:(NSString*)downloadId isDiscretionary:(BOOL)discretionary {
    if ( self = [super init] ) {
        self.url = url;
        self.downloadId = downloadId;
        self.isDiscretionary = discretionary;
        return self;
    }
    return nil;
}

@end
