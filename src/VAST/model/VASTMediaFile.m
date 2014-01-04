//
//  VASTMediaFile.m
//  VAST
//
//  Created by Jay Tucker on 10/15/13.
//  Copyright (c) 2013 Nexage. All rights reserved.
//

#import "VASTMediaFile.h"

@implementation VASTMediaFile

- (id)initWithId:(NSString *)id_
        delivery:(NSString *)delivery
            type:(NSString *)type
         bitrate:(NSString *)bitrate
           width:(NSString *)width
          height:(NSString *)height
        scalable:(NSString *)scalable
maintainAspectRatio:(NSString *)maintainAspectRatio
    apiFramework:(NSString *)apiFramework
             url:(NSString *)url

{
    self = [super init];
    if (self) {
        _id_ = id_;
        _delivery = delivery;
        _type = type;
        _bitrate = bitrate ? [bitrate intValue] : 0;
        _width = width ? [width intValue] : 0;
        _height = height ? [height intValue] : 0;
        _scalable = scalable ? [scalable boolValue] : YES;
        _maintainAspectRatio = maintainAspectRatio ? [maintainAspectRatio boolValue] : NO;
        _apiFramework = apiFramework;
        _url = [NSURL URLWithString:url];
    }
    return self;
}

@end
