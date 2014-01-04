//
//  VASTEventTracker.m
//  VAST
//
//  Created by Thomas Poland on 10/3/13.
//  Copyright (c) 2013 Nexage. All rights reserved.
//

#import "VASTEventProcessor.h"
#import "SourceKitLogger.h"
#import "VASTUrlWithId.h"


@interface VASTEventProcessor()

@property(nonatomic, strong) NSDictionary *trackingEvents;

@end


@implementation VASTEventProcessor

// designated initializer
- (id)initWithTrackingEvents:(NSDictionary *)trackingEvents
{
    self = [super init];
    if (self) {
        self.trackingEvents = trackingEvents;
    }
    return self;
}

- (void)trackEvent:(VASTEvent)vastEvent
{
    switch (vastEvent) {
     
        case VASTEventTrackStart:
            for (NSURL *aURL in [self.trackingEvents objectForKey:@"start"]) {
                [self sendTrackingRequest:aURL];
                [SourceKitLogger debug:[NSString stringWithFormat:@"Sent track start to url: %@", [aURL absoluteString]]];
            }
         break;
            
        case VASTEventTrackFirstQuartile:
            for (NSURL *aURL in [self.trackingEvents objectForKey:@"firstQuartile"]) {
                [self sendTrackingRequest:aURL];
                [SourceKitLogger debug:[NSString stringWithFormat:@"Sent firstQuartile to url: %@", [aURL absoluteString]]];
            }
            break;
            
        case VASTEventTrackMidpoint:
            for (NSURL *aURL in [self.trackingEvents objectForKey:@"midpoint"]) {
                [self sendTrackingRequest:aURL];
                [SourceKitLogger debug:[NSString stringWithFormat:@"Sent midpoint to url: %@", [aURL absoluteString]]];
            }
            break;
            
        case VASTEventTrackThirdQuartile:
            for (NSURL *aURL in [self.trackingEvents objectForKey:@"thirdQuartile"]) {
                [self sendTrackingRequest:aURL];
                [SourceKitLogger debug:[NSString stringWithFormat:@"Sent thirdQuartile to url: %@", [aURL absoluteString]]];
            }
            break;
 
        case VASTEventTrackComplete:
            for( NSURL *aURL in [self.trackingEvents objectForKey:@"complete"]) {
                [self sendTrackingRequest:aURL];
                [SourceKitLogger debug:[NSString stringWithFormat:@"Sent complete to url: %@", [aURL absoluteString]]];
            }
            break;
            
        case VASTEventTrackClose:
            for (NSURL *aURL in [self.trackingEvents objectForKey:@"close"]) {
                [self sendTrackingRequest:aURL];
                [SourceKitLogger debug:[NSString stringWithFormat:@"Sent close to url: %@", [aURL absoluteString]]];
            }
            break;
            
        case VASTEventTrackPause:
            for (NSURL *aURL in [self.trackingEvents objectForKey:@"pause"]) {
                [self sendTrackingRequest:aURL];
                [SourceKitLogger debug:[NSString stringWithFormat:@"Sent pause start to url: %@", [aURL absoluteString]]];
            }
            break;
            
        case VASTEventTrackResume:
            for (NSURL *aURL in [self.trackingEvents objectForKey:@"resume"]) {
                [self sendTrackingRequest:aURL];
                [SourceKitLogger debug:[NSString stringWithFormat:@"Sent resume start to url: %@", [aURL absoluteString]]];
            }
            break;
            
        default:
            break;
    }
}

- (void)sendVASTUrlsWithId:(NSArray *)vastUrls
{
    for (VASTUrlWithId *urlWithId in vastUrls) {
        [self sendTrackingRequest:urlWithId.url];
        if (urlWithId.id_) {
            [SourceKitLogger debug:[NSString stringWithFormat:@"Sent http request %@ to url: %@", urlWithId.id_, urlWithId.url]];
        } else {
            [SourceKitLogger debug:[NSString stringWithFormat:@"Sent http request to url: %@", urlWithId.url]];
        }
    }
}

- (void)sendTrackingRequest:(NSURL *)trackingURL
{
    dispatch_queue_t sendTrackRequestQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_async(sendTrackRequestQueue, ^{
        NSURLRequest* trackingURLrequest = [ NSURLRequest requestWithURL:trackingURL cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:1.0];
        NSOperationQueue *senderQueue = [[NSOperationQueue alloc] init];
        [SourceKitLogger debug:[NSString stringWithFormat:@"Event processor sending request to url: %@", [trackingURL absoluteString]]] ;
        [NSURLConnection sendAsynchronousRequest:trackingURLrequest queue:senderQueue completionHandler:nil];  // Send the request only, no response or errors
    });
}

@end
