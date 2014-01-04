//
//  VASTEventTracker.h
//  VAST
//
//  Created by Thomas Poland on 10/3/13.
//  Copyright (c) 2013 Nexage. All rights reserved.
//
//  VASTEventTracker wraps NSURLRequest to handle sending tracking and impressions events defined in the VAST 2.0 document and stored in VASTModel.

#import <Foundation/Foundation.h>

typedef enum {
    VASTEventTrackStart,
    VASTEventTrackFirstQuartile,
    VASTEventTrackMidpoint,
    VASTEventTrackThirdQuartile,
    VASTEventTrackComplete,
    VASTEventTrackClose,
    VASTEventTrackPause,
    VASTEventTrackResume
} VASTEvent;

@interface VASTEventProcessor : NSObject

- (id)initWithTrackingEvents:(NSDictionary *)trackingEvents;    // designated initializer, uses tracking events stored in VASTModel
- (void)trackEvent:(VASTEvent)vastEvent;                       // sends the given VASTEvent
- (void)sendVASTUrlsWithId:(NSArray *)vastUrls;                // sends the set of http requests to supplied URLs, used for Impressions, ClickTracking, and Errors.

@end
