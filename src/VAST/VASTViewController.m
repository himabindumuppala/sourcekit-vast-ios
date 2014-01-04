//
//  VASTViewController.m
//  VAST
//
//  Created by Thomas Poland on 9/30/13.
//  Copyright (c) 2013 Nexage. All rights reserved.
//

#import "VASTViewController.h"
#import <MediaPlayer/MediaPlayer.h>
#import <netdb.h>
#import "SourceKitLogger.h"
#import "VAST2Parser.h"
#import "VASTModel.h"
#import "VASTEventProcessor.h"
#import "VASTUrlWithId.h"
#import "VASTMediaFile.h"
#import "VASTControls.h"
#import "VASTMediaFilePicker.h"
#import "Reachability.h"

#define kKitVersion 0.1
#define SYSTEM_VERSION_LESS_THAN(v)     ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] == NSOrderedAscending)

static const float kPlayTimeCounterInterval = 0.25;
static const float kVideoTimoutInterval = 10.0;
static const NSString* kPlaybackFinishedUserInfoErrorKey=@"error";
static const float kControlsToolbarHeight=44.0;

typedef enum {
    VASTFirstQuartile,
    VASTSecondQuartile,
    VASTThirdQuartile,
    VASTFourtQuartile,
} CurrentVASTQuartile;

@interface VASTViewController() <UIGestureRecognizerDelegate>
{
    NSURL *mediaFileURL;
    NSArray *clickTracking;
    NSArray *vastErrors;
    NSTimer *playbackTimer;
    NSTimer *controlsTimer;
    NSTimer *videoTimeoutTimer;
    NSTimeInterval movieDuration;
    NSTimeInterval playedSeconds;
    
    VASTControls *controls;
    
    float currentPlayedPercentage;
    BOOL isPlaying;
    BOOL isViewOnScreen;
    BOOL hasPlayerStarted;
    BOOL isLoadCalled;
    BOOL backGroundPlayingStateAutoPaused;
    BOOL hasResignedActive;
    BOOL vastReady;
    BOOL statusBarHidden;
    CurrentVASTQuartile currentQuartile;
    
    Reachability *reachabilityForVAST;
    NetworkReachable networkReachableBlock;
    NetworkUnreachable networkUnreachableBlock;
}

@property(nonatomic, strong) MPMoviePlayerController *moviePlayer;
@property(nonatomic, strong) UITapGestureRecognizer *touchGestureRecognizer;
@property(nonatomic, strong) VASTEventProcessor *eventProcessor;
@property(nonatomic, strong) NSMutableArray *videoHangTest;
@property(nonatomic, assign) BOOL networkCurrentlyReachable;

@end

@implementation VASTViewController

- (id)init
{
    return [self initWithDelegate:nil];
}

// designated initializer
- (id)initWithDelegate:(id<VASTViewControllerDelegate>)delegate;
{
    self = [super init];
    if (self) {
        _delegate = delegate;
        currentQuartile=VASTFirstQuartile;
        self.videoHangTest=[NSMutableArray arrayWithCapacity:20];
        
        [self setupReachability];
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playbackStateChangeNotification:)
                                                     name:MPMoviePlayerPlaybackStateDidChangeNotification
                                                   object:nil];
 
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(moviePlayBackDidFinish:)
                                                     name:MPMoviePlayerPlaybackDidFinishNotification
                                                   object:nil];
  
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(movieDuration:)
                                                     name:MPMovieDurationAvailableNotification
                                                   object:nil];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(movieSourceType:)
                                                     name:MPMovieSourceTypeAvailableNotification
                                                   object:nil];
        
        [[NSNotificationCenter defaultCenter] addObserver: self
												 selector: @selector(applicationWillResignActive:)
													 name: UIApplicationWillResignActiveNotification
												   object: nil];
    
        [[NSNotificationCenter defaultCenter] addObserver: self
												 selector: @selector(applicationDidBecomeActive:)
													 name: UIApplicationDidBecomeActiveNotification
												   object: nil];
        }
    return self;
}

-(void)viewWillAppear:(BOOL)animated{
    statusBarHidden = [[UIApplication sharedApplication] isStatusBarHidden];
    if (SYSTEM_VERSION_LESS_THAN(@"7.0")) {
        [[UIApplication sharedApplication] setStatusBarHidden:YES withAnimation:UIStatusBarAnimationFade];
    }
}

-(void)viewWillDisappear:(BOOL)animated{
    if (SYSTEM_VERSION_LESS_THAN(@"7.0")) {
        [[UIApplication sharedApplication] setStatusBarHidden:statusBarHidden withAnimation:UIStatusBarAnimationFade];
    }
}

- (void)viewDidAppear:(BOOL)animated
{
    [SourceKitLogger debug:[NSString stringWithFormat:@"%@", NSStringFromSelector(_cmd)]];
    isViewOnScreen=YES;
    if (!hasPlayerStarted) {
        [self showAndPlayVideo];
    } else {
        // resuming from background or phone call, so resume if was playing, stay paused if manually paused
        if (backGroundPlayingStateAutoPaused) {
            [self pausePlay];  // we were paused, so resume, otherwise do nothing
        }
    }
}

- (void)initializeAndPreparePlayer
{
    [SourceKitLogger debug:@"initializing player"];

    if (!self.networkCurrentlyReachable) {   // Reachability may have changed, so we need to test again just before loading the video itself
        [SourceKitLogger debug:@"No network available - VASTViewcontroller will not be presented"];
        if ([self.delegate respondsToSelector:@selector(vastError:error:)]) {
            [self.delegate vastError:self error:VASTErrorNoInternetConnection];  // There is network so no requests can be sent, we don't queue errors, so no external Error event is sent.
        }
        return;
    }

    @try {
        self.moviePlayer = [[MPMoviePlayerController alloc] initWithContentURL:mediaFileURL];
        playedSeconds = 0.0;
        currentPlayedPercentage = 0.0;
        self.moviePlayer.controlStyle=MPMovieControlStyleNone;  // see 'showControls' for custom control toolbar set up
        [self.moviePlayer prepareToPlay];
    }
    @catch (NSException *e) {
        [SourceKitLogger debug:[NSString stringWithFormat:@"Exception - [self.moviePlayer prepareToPlay: %@", e]];
        if ([self.delegate respondsToSelector:@selector(vastError:error:)]) {
            [self.delegate vastError:self error:VASTErrorPlaybackError];
        }
        if (vastErrors) {
            [SourceKitLogger debug:@"Sending Error requests"];
            [self.eventProcessor sendVASTUrlsWithId:vastErrors];
        }
        [self dismiss];
        return;
    }
}

- (void)dealloc
{
    [reachabilityForVAST stopNotifier];
    [self removeObservers];
    [SourceKitLogger debug:[NSString stringWithFormat:@"%@", NSStringFromSelector(_cmd)]];
}

- (void)removeObservers
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:MPMoviePlayerPlaybackStateDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:MPMoviePlayerPlaybackDidFinishNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:MPMovieDurationAvailableNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:MPMovieSourceTypeAvailableNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationWillResignActiveNotification object:nil];
    [SourceKitLogger debug:[NSString stringWithFormat:@"%@", NSStringFromSelector(_cmd)]];
}

- (void)viewDidDisappear:(BOOL)animated
{
    [SourceKitLogger debug:  [NSString stringWithFormat:@"%@", NSStringFromSelector(_cmd)]];
    if ([self.delegate respondsToSelector:@selector(vastDidDismissFullScreen:)]) {
        [self.delegate vastDidDismissFullScreen:self];
    }
}

- (void)applicationWillResignActive:(UIApplication *)application
{
    if (isPlaying) {
        [SourceKitLogger debug:@"applicationWillResignActive, pausing player"];
        [self pausePlay];  // pause if playing
        backGroundPlayingStateAutoPaused=YES;
    }
    hasResignedActive=YES;
    [self stopPlaybackTimer];
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    [SourceKitLogger debug:  [NSString stringWithFormat:@"%@", NSStringFromSelector(_cmd)]];
    if (hasPlayerStarted) {
        // resuming from background or phone call, so resume if was playing, stay paused if manually paused
        if (backGroundPlayingStateAutoPaused) {
            [self pausePlay];  // we were paused, so resume, otherwise do nothing
            [self startPlaybackTimer];
            [SourceKitLogger debug:@"applicationDidBecomeActive, resuming player from auto pause"];
        } else {
            [SourceKitLogger debug:@"applicationDidBecomeActive, resuming app, currently manually paused"];
        }
    }
    backGroundPlayingStateAutoPaused=NO;
}

#pragma mark - rotation/orientation

// force to always play in Landscape
- (BOOL)shouldAutorotate
{
    NSArray *supportedOrientationsInPlist = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"UISupportedInterfaceOrientations"];
    BOOL isLandscapeLeftSupported = [supportedOrientationsInPlist containsObject:@"UIInterfaceOrientationLandscapeLeft"];
    BOOL isLandscapeRightSupported = [supportedOrientationsInPlist containsObject:@"UIInterfaceOrientationLandscapeRight"];
    return isLandscapeLeftSupported && isLandscapeRightSupported;
}

- (NSUInteger)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskLandscape;
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation
{
    UIInterfaceOrientation currentInterfaceOrientation = [[UIApplication sharedApplication] statusBarOrientation];
    return UIInterfaceOrientationIsLandscape(currentInterfaceOrientation) ? currentInterfaceOrientation : UIInterfaceOrientationLandscapeRight;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation
{
    return UIInterfaceOrientationIsLandscape(toInterfaceOrientation);
}

- (BOOL)prefersStatusBarHidden{
    return YES;
}

#pragma mark - VAST Delegate callbacks

- (void)loadVideoWithURL:(NSURL *)url
{
    [self loadVideoUsingSource:url];
}

- (void)loadVideoWithData:(NSData *)xmlContent
{
    [self loadVideoUsingSource:xmlContent];
}

- (void)loadVideoUsingSource:(id)source
{
    [SourceKitLogger debug:([source isKindOfClass:[NSURL class]]?@"Starting loadVideoWithURL":@"Starting loadVideoWithData")];
    
    if (isLoadCalled) {
        [SourceKitLogger debug:@"Ignoring loadVideo because a load is in progress."];
        return;
    }
    isLoadCalled = YES;
    [self startVideoTimeoutTimer];
    
    void (^parserCompletionBlock)(VASTModel *vastModel, VASTError vastError) = ^(VASTModel *vastModel, VASTError vastError) {
        [SourceKitLogger debug:@"back from block in loadVideoFromData"];
        if (!vastModel) {
            [SourceKitLogger debug:@"parser error"];
            if ([self.delegate respondsToSelector:@selector(vastError:error:)]) {  // The VAST document was not readable, so no Error urls exist, thus none are sent.
                [self.delegate vastError:self error:vastError];
            }
            [self dismiss];
            return;
        }
        
        self.eventProcessor = [[VASTEventProcessor alloc] initWithTrackingEvents:[vastModel trackingEvents]];
        NSArray *impresssions = [vastModel impressions];
        if (impresssions) {
            [SourceKitLogger debug:@"Sending Impresssions requests"];
            [self.eventProcessor sendVASTUrlsWithId:[vastModel impressions]];
        }
        vastErrors = [vastModel errors];
        self.clickThrough = [[vastModel clickThrough] url];
        clickTracking = [vastModel clickTracking];
        mediaFileURL = [VASTMediaFilePicker pick:[vastModel mediaFiles]].url;
        if(!mediaFileURL) {
        [SourceKitLogger debug:[NSString stringWithFormat:@"Error - VASTMediaFilePicker did not find a compatible mediaFile - VASTViewcontroller will not be presented"]];
            if ([self.delegate respondsToSelector:@selector(vastError:error:)]) {
                [self.delegate vastError:self error:VASTErrorNoCompatibleMediaFile];
            }
            if (vastErrors) {
                [SourceKitLogger debug:@"Sending Error requests"];
                [self.eventProcessor sendVASTUrlsWithId:vastErrors];
            }
            [self dismiss];
            return;
        }
        [self initializeAndPreparePlayer];
    };
    
    VAST2Parser *parser = [[VAST2Parser alloc] init];
     if ([source isKindOfClass:[NSURL class]]) {
        if (!self.networkCurrentlyReachable) {
            [SourceKitLogger debug:@"No network available - VASTViewcontroller will not be presented"];
            if ([self.delegate respondsToSelector:@selector(vastError:error:)]) {
                [self.delegate vastError:self error:VASTErrorNoInternetConnection];  // There is network so no requests can be sent, we don't queue errors, so no external Error event is sent.
            }
            [self dismiss];
            return;
        }
        [parser parseWithUrl:(NSURL *)source completion:parserCompletionBlock];     // Load the and parse the VAST document at the supplied URL
    } else {
        [parser parseWithData:(NSData *)source completion:parserCompletionBlock];   // Parse a VAST document in supplied data
    }
}

- (void)playVideo
{
    [SourceKitLogger debug:@"playVideo"];
    
    if (!vastReady) {
        if ([self.delegate respondsToSelector:@selector(vastError:error:)]) {
            [self.delegate vastError:self error:VASTErrorPlayerNotReady];                  // This is not a VAST player error, so no external Error event is sent.
            [SourceKitLogger debug:@"Ignoring call to playVideo before the player has sent vastReady."];
            return;
        }
    }
    
    if (isViewOnScreen) {
        if ([self.delegate respondsToSelector:@selector(vastError:error:)]) {
            [self.delegate vastError:self error:VASTErrorPlaybackAlreadyInProgress];       // This is not a VAST player error, so no external Error event is sent.
            [SourceKitLogger debug:@"Ignoring call to playVideo while playback is already in progress"];
            return;
        }
    }
    
    if (!self.networkCurrentlyReachable) {
        [SourceKitLogger debug:@"No network available - VASTViewcontroller will not be presented"];
        if ([self.delegate respondsToSelector:@selector(vastError:error:)]) {
            [self.delegate vastError:self error:VASTErrorNoInternetConnection];   // There is network so no requests can be sent, we don't queue errors, so no external Error event is sent.
        }
        [self dismiss];
        return;
    } else {
        [SourceKitLogger debug:@"Network available - presenting VASTViewcontroller"];
    }
    
    if ([self.delegate respondsToSelector:@selector(vastWillPresentFullScreen:)]) {
        [self.delegate vastWillPresentFullScreen:self];
    }
    
    id rootViewController = [[UIApplication sharedApplication] keyWindow].rootViewController;
    if ([rootViewController respondsToSelector:@selector(presentViewController:animated:completion:)]) {
        // used if running >= iOS 6
        [rootViewController presentViewController:self animated:YES completion:nil];
    } else {
        // Turn off the warning about using a deprecated method.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [rootViewController presentModalViewController:self animated:YES];
#pragma clang diagnostic pop
    }
}

- (void)showAndPlayVideo
{
    [SourceKitLogger debug:[NSString stringWithFormat:@"adding player to on screen view and starting play sequence"]];
    
    self.moviePlayer.view.frame=self.view.bounds;
    [self.view addSubview:self.moviePlayer.view];
    
    // N.B. The player has to be ready to play before controls may be added to the player's view
    [SourceKitLogger debug:@"initializing player controls"];
    controls = [[VASTControls alloc] initWithVASTPlayer:self];
    [self.moviePlayer.view addSubview: controls.view];
    [controls showControls];

    hasPlayerStarted=YES;
    
    @try {
        [SourceKitLogger debug:[NSString stringWithFormat:@"Playing aspect fit full screen video (natural size %4.0fw x %4.0fh)",self.moviePlayer.naturalSize.width, self.moviePlayer.naturalSize.height]];
        [self.moviePlayer play];
    }
    @catch (NSException *e) {
        [SourceKitLogger debug:[NSString stringWithFormat:@"Exception - [self.moviePlayer play]: %@", e]];
        if ([self.delegate respondsToSelector:@selector(vastError:error:)]) {
            [self.delegate vastError:self error:VASTErrorPlaybackError];
        }
        if (vastErrors) {
            [SourceKitLogger debug:@"Sending Error requests"];
            [self.eventProcessor sendVASTUrlsWithId:vastErrors];
        }
        [self dismiss];
        return;
    }
    
    [self startPlaybackTimer];
    [self.eventProcessor trackEvent:VASTEventTrackStart];
    [self setUpTapGestureRecognizer];
}

#pragma mark - MPMoviePlayerController notifications

- (void)playbackStateChangeNotification:(NSNotification *)notification
{
    @synchronized (self) {
        MPMoviePlaybackState state = [self.moviePlayer playbackState];
        [SourceKitLogger debug:[ NSString stringWithFormat:@"playback state change to %i", state]];
        
        switch (state) {
            case MPMoviePlaybackStateStopped:  // 0
                [SourceKitLogger debug:@"video stopped"];
                break;
            case MPMoviePlaybackStatePlaying:  // 1
                isPlaying=YES;
                [controls toggleToPlayButton:NO];
                if (!hasResignedActive && !isViewOnScreen) {
                    [self stopVideoTimeoutTimer];
                    [SourceKitLogger debug:[NSString stringWithFormat:@"Sending vastReady: callback"]];
                    vastReady = YES;
                    [self.delegate vastReady:self];
                }
                if (isViewOnScreen) {
                    [SourceKitLogger debug:@"video is playing"];
                    [self startPlaybackTimer];
                }
                break;
            case MPMoviePlaybackStatePaused:  // 2
                [self stopPlaybackTimer];
                [SourceKitLogger debug:@"video paused"];
                isPlaying=NO;
                [controls toggleToPlayButton:YES];
                break;
            case MPMoviePlaybackStateInterrupted:  // 3
                [SourceKitLogger debug:@"video interrupt"];
                break;
            case MPMoviePlaybackStateSeekingForward:  // 4
                [SourceKitLogger debug:@"video seeking forward"];
                break;
            case MPMoviePlaybackStateSeekingBackward:  // 5
                [SourceKitLogger debug:@"video seeking backward"];
                break;
            default:
                [SourceKitLogger warning:@"undefined state change"];
                break;
        }
    }
}

- (void) moviePlayBackDidFinish:(NSNotification *)notification
{
    [SourceKitLogger debug:@"playback did finish"];
    
    NSDictionary* userInfo=[notification userInfo];
    [SourceKitLogger debug:[ NSString stringWithFormat:@"user info:  %@", userInfo]];
    
    NSString* error=[userInfo objectForKey:kPlaybackFinishedUserInfoErrorKey];
    
    if (error) {
        [SourceKitLogger debug:[ NSString stringWithFormat:@"playback error:  %@", error]];
        if ([self.delegate respondsToSelector:@selector(vastError:error:)]) {
            [self.delegate vastError:self error:VASTErrorPlaybackError];
        }
        if (vastErrors) {
            [SourceKitLogger debug:@"Sending Error requests"];
            [self.eventProcessor sendVASTUrlsWithId:vastErrors];
        }
        [self dismiss];
    } else {
        // no error, clean finish, so send track complete
        [self.eventProcessor trackEvent:VASTEventTrackComplete];
        [self updatePlayedSeconds];
        [controls showControls];
        [controls toggleToPlayButton:YES];
    }
}

- (void)movieDuration:(NSNotification *)notification
{
    @try {
        movieDuration = self.moviePlayer.duration;
    }
    @catch (NSException *e) {
        [SourceKitLogger debug:[NSString stringWithFormat:@"Exception - movieDuration: %@", e]];
        // The movie too short error will fire if movieDuration is < 0.5 or is a NaN value, so no need for further action here.
    }
    
    [SourceKitLogger debug:[ NSString stringWithFormat:@"playback duration is %f", movieDuration]];
    
    if (movieDuration < 0.5 || isnan(movieDuration)) {
        // movie too short - ignore it
        [SourceKitLogger debug:@"Movie too short - will dismiss player"];
        if ([self.delegate respondsToSelector:@selector(vastError:error:)]) {
            [self.delegate vastError:self error:VASTErrorMovieTooShort];
        }
        if (vastErrors) {
            [SourceKitLogger debug:@"Sending Error requests"];
            [self.eventProcessor sendVASTUrlsWithId:vastErrors];
        }
        [self dismiss];
    }
}

- (void)movieSourceType:(NSNotification *)notification
{
    MPMovieSourceType sourceType;
    @try {
        sourceType = self.moviePlayer.movieSourceType;
    }
    @catch (NSException *e) {
        [SourceKitLogger debug:[NSString stringWithFormat:@"Exception - movieSourceType: %@", e]];
        // sourceType is used for info only - any player related error will be handled otherwise, ultimately by videoTimeout, so no other action needed here.
    }
    
    [SourceKitLogger debug:[ NSString stringWithFormat:@"move source type is %i", sourceType]];
}

#pragma mark - timers

// playbackTimer - keeps track of currentPlayedPercentage
- (void)startPlaybackTimer
{
    @synchronized (self) {
        [self stopPlaybackTimer];
        playbackTimer = [NSTimer scheduledTimerWithTimeInterval:kPlayTimeCounterInterval
                                                         target:self
                                                       selector:@selector(updatePlayedSeconds)
                                                       userInfo:nil
                                                        repeats:YES];
    }
}

- (void)stopPlaybackTimer
{
    [playbackTimer invalidate];
    playbackTimer = nil;
}

- (void)updatePlayedSeconds
{
    @try {
        playedSeconds = self.moviePlayer.currentPlaybackTime;
    }
    @catch (NSException *e) {
        [SourceKitLogger debug:[NSString stringWithFormat:@"Exception - updatePlayedSeconds: %@", e]];
        // The hang test below will fire if playedSeconds doesn't update (including a NaN value), so no need for further action here.
    }
    
    [self.videoHangTest addObject:[NSNumber numberWithInteger:(int)(playedSeconds*10.0)]];     // add new number to end of hang test buffer
    
    if ([self.videoHangTest count]>20) {  // only check for hang if we have at least 20 elements or about 5 seconds of played video, to prevent false positives
        if ([[self.videoHangTest firstObject] integerValue]==[[self.videoHangTest lastObject] integerValue]) {
            [SourceKitLogger debug:[NSString stringWithFormat:@"Video error - video player hung at playedSeconds: %f", playedSeconds]];
            if ([self.delegate respondsToSelector:@selector(vastError:error:)]) {
                [self.delegate vastError:self error:VASTErrorPlayerHung];
            }
            if (vastErrors) {
                [SourceKitLogger debug:@"Sending Error requests"];
                [self.eventProcessor sendVASTUrlsWithId:vastErrors];
            }
            [self dismiss];
        }
        [self.videoHangTest removeObjectAtIndex:0];   // remove oldest number from start of hang test buffer
    }
    
   	currentPlayedPercentage = (float)100.0*(playedSeconds/movieDuration);
    [controls updateProgressBar: currentPlayedPercentage/100.0 withPlayedSeconds:playedSeconds withTotalDuration:movieDuration];
//    [SourceKitLogger debug: [ NSString stringWithFormat:@"movie has played %.1f%%", currentPlayedPercentage]];
    
    switch (currentQuartile) {
 
        case VASTFirstQuartile:
            if (currentPlayedPercentage>25.0) {
                [self.eventProcessor trackEvent:VASTEventTrackFirstQuartile];
                currentQuartile=VASTSecondQuartile;
            }
            break;
        
        case VASTSecondQuartile:
            if (currentPlayedPercentage>50.0) {
                [self.eventProcessor trackEvent:VASTEventTrackMidpoint];
                currentQuartile=VASTThirdQuartile;
            }
            break;
            
        case VASTThirdQuartile:
            if (currentPlayedPercentage>75.0) {
                [self.eventProcessor trackEvent:VASTEventTrackThirdQuartile];
                currentQuartile=VASTFourtQuartile;
            }
            break;
  
        default:
            break;
    }
}

// videoTimeoutTimer - dimisses VASTViewController if video times out while loading
- (void)startVideoTimeoutTimer
{
    [self stopVideoTimeoutTimer];
    videoTimeoutTimer = [NSTimer scheduledTimerWithTimeInterval:kVideoTimoutInterval
                                                     target:self
                                                   selector:@selector(videoTimeout)
                                                   userInfo:nil
                                                    repeats:NO];
}

- (void)stopVideoTimeoutTimer
{
    [videoTimeoutTimer invalidate];
    videoTimeoutTimer = nil;
}

- (void)videoTimeout
{
    [SourceKitLogger debug:@"Video Timeout"];
    if (vastErrors) {
        [SourceKitLogger debug:@"Sending Error requests"];
        [self.eventProcessor sendVASTUrlsWithId:vastErrors];
    }
    if ([self.delegate respondsToSelector:@selector(vastError:error:)]) {
        [self.delegate vastError:self error:VASTErrorLoadTimeout];
    }
    [self dismiss];
}

- (void)killTimers {
    [self stopPlaybackTimer];
    [self stopVideoTimeoutTimer];
}

- (void)info
{
    [SourceKitLogger debug:  [NSString stringWithFormat:@"%@", NSStringFromSelector(_cmd)]];
    if (clickTracking) {
        [SourceKitLogger debug:@"Sending clickTracking requests"];
        [self.eventProcessor sendVASTUrlsWithId:clickTracking];
    }
    if ([self.delegate respondsToSelector:@selector(vastOpenBrowseWithUrl:)]) {
        [self.delegate vastOpenBrowseWithUrl:self.clickThrough];
    }
}

- (void)pausePlay
{
    [SourceKitLogger debug:  [NSString stringWithFormat:@"%@", NSStringFromSelector(_cmd)]];
    if (isPlaying) {
        [self.moviePlayer pause];
        [SourceKitLogger debug:@"Pausing video playback"];
        isPlaying = NO;
        [self.eventProcessor trackEvent:VASTEventTrackPause];
    } else {
        [self.moviePlayer play];
        [SourceKitLogger debug:@"Resuming video playback"];
        isPlaying = YES;
        [self.eventProcessor trackEvent:VASTEventTrackResume];
    }
}

- (void)dismiss
{
    @synchronized (self) {
        [self removeObservers];
        [self killTimers];
        self.moviePlayer=nil;
        
        [SourceKitLogger debug:  [NSString stringWithFormat:@"%@", NSStringFromSelector(_cmd)]];
        
        if (isViewOnScreen) {
            // send close any time the player has been dismissed
            [self.eventProcessor trackEvent:VASTEventTrackClose];
            [SourceKitLogger debug:@"Dismissing VASTViewController"];
            [self dismissViewControllerAnimated:YES completion:nil];
        }
    }
}

//
// handle touches
//
#pragma mark - gesture delegate

- (void)setUpTapGestureRecognizer
{
    self.touchGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTouches)];
    self.touchGestureRecognizer.delegate = self;
    [self.touchGestureRecognizer setNumberOfTouchesRequired:1];
    self.touchGestureRecognizer.cancelsTouchesInView=NO;  // required to enable controlToolbar buttons to receive touches
    [self.view addGestureRecognizer:self.touchGestureRecognizer];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return YES;
}

- (void)handleTouches{
    [SourceKitLogger debug:@"observed a touch"];
    [controls showControls];
}

#pragma mark - Reachability

- (void)setupReachability
{
    reachabilityForVAST = [Reachability reachabilityForInternetConnection];
    reachabilityForVAST.reachableOnWWAN = YES;            // Do allow 3G/WWAN for reachablity
 
    __unsafe_unretained VASTViewController *self_ = self; // avoid block retain cycle
    
    networkReachableBlock  = ^(Reachability*reachabilityForVAST){
        [SourceKitLogger debug:@"Network reachable"];
        self_.networkCurrentlyReachable = YES;
    };
    
    networkUnreachableBlock = ^(Reachability*reachabilityForVAST){
        [SourceKitLogger debug:@"Network not reachable"];
        self_.networkCurrentlyReachable = NO;
    };
    
    reachabilityForVAST.reachableBlock = networkReachableBlock;
    reachabilityForVAST.unreachableBlock = networkUnreachableBlock;
    
    [reachabilityForVAST startNotifier];
    self.networkCurrentlyReachable = [reachabilityForVAST isReachable];
    [SourceKitLogger debug:[NSString stringWithFormat:@"Network is reachable %d", self.networkCurrentlyReachable]];
}

@end
