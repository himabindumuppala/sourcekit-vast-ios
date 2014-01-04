//
//  VASTViewController.h
//  VAST
//
//  Created by Thomas Poland on 9/30/13.
//  Copyright (c) 2013 Nexage. All rights reserved.
//

// VASTViewController is the main component of the SourceKit VAST Implementation.
//
// This class creates and manages an iOS MPMediaPlayerViewController to playback a video from a VAST 2.0 document.
// The document may be loaded using a URL or directly from an exisitng XML document (as NSData).
//
// See the VASTViewControllerDelegate Protocol for the required vastReady: and other useful methods.
// Screen controls are exposed for play, pause, info, and dismiss, which are handled by the VASTControls class as an overlay toolbar.
//
// VASTEventProcessor handles tracking events and impressions.
// Errors encountered are listed in in VASTError.h
//
// Please note:  Only one video may be played at a time, you must wait for the vastReady: callback before sending the 'play' message.

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import "VASTError.h"

@class VASTViewController;

@protocol VASTViewControllerDelegate <NSObject>

@required

- (void)vastReady:(VASTViewController *)vastVC;  // sent when the video is ready to play - required

@optional

- (void)vastError:(VASTViewController *)vastVC error:(VASTError)error;  // sent when any VASTError occurs - optional

// These optional callbacks are for basic presentation, dismissal, and calling video clickthrough url browser.
- (void)vastWillPresentFullScreen:(VASTViewController *)vastVC;
- (void)vastDidDismissFullScreen:(VASTViewController *)vastVC;
- (void)vastOpenBrowseWithUrl:(NSURL *)url;

@end

@interface VASTViewController : UIViewController

@property (nonatomic, unsafe_unretained) id<VASTViewControllerDelegate>delegate;
@property (nonatomic, strong) NSURL *clickThrough;

- (id)initWithDelegate:(id<VASTViewControllerDelegate>)delegate;  // designated initializer for VASTViewController

- (void)loadVideoWithURL:(NSURL *)url;            // load and prepare to play a VAST video from a URL
- (void)loadVideoWithData:(NSData *)xmlContent;   // load and prepare to play a VAST video from existing XML data
- (void)playVideo;                                // command to play the video, this is only valid after receiving the vastReady: callback

// These actions are called by the VASTControls toolbar; the are exposed to enable an alternative custom VASTControls toolbar
- (void)dismiss;                       // dismisses a video playing on screen
- (void)info;                          // callback to host class for opening a browser to the URL specified in 'clickthrough'
- (void)pausePlay;                     // pauses or plays the video; also used automatically when the app resigns or becomes active

@end
