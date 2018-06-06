//
//  BackdownRequest.h
//  backdown
//
//  Created by Tom Newton on 06/06/2018.
//

#import <Foundation/Foundation.h>

@interface BackdownRequest : NSObject
@property(nonatomic, assign) BOOL isDiscretionary;
@property(nonatomic, retain, nonnull) NSString* url;
@property(nonatomic, retain, nonnull) NSString* downloadId;

-(id)initWithUrl:(NSString*)url andDownloadId:(NSString*)downloadId isDiscretionary:(BOOL)discretionary;
@end
