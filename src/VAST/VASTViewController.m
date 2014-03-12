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

#define SYSTEM_VERSION_LESS_THAN(v)     ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] == NSOrderedAscending)

static const float kPlayTimeCounterInterval = 0.25;
static const float kVideoLoadTimeoutInterval = 10.0;
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
    NSArray *impressions;
    NSTimer *playbackTimer;
    NSTimer *controlsTimer;
    NSTimer *videoLoadTimeoutTimer;
    NSTimeInterval movieDuration;
    NSTimeInterval playedSeconds;
    
    VASTControls *controls;
    
    float currentPlayedPercentage;
    BOOL isPlaying;
    BOOL isViewOnScreen;
    BOOL hasPlayerStarted;
    BOOL isLoadCalled;
    BOOL vastReady;
    BOOL statusBarHidden;
    CurrentVASTQuartile currentQuartile;
    UIActivityIndicatorView *loadingIndicator;
    
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

#pragma mark - Init & dealloc

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
        
        [[NSNotificationCenter defaultCenter] addObserver: self
												 selector: @selector(applicationDidBecomeActive:)
													 name: UIApplicationDidBecomeActiveNotification
												   object: nil];
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(movieDuration:)
                                                     name:MPMovieDurationAvailableNotification
                                                   object:nil];
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(moviePlayBackDidFinish:)
                                                     name:MPMoviePlayerPlaybackDidFinishNotification
                                                   object:nil];
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(playbackStateChangeNotification:)
                                                     name:MPMoviePlayerPlaybackStateDidChangeNotification
                                                   object:nil];
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(moviePlayerLoadStateChanged:)
                                                     name:MPMoviePlayerLoadStateDidChangeNotification
                                                   object:nil];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(movieSourceType:)
                                                     name:MPMovieSourceTypeAvailableNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc
{
    [reachabilityForVAST stopNotifier];
    [self removeObservers];
}

#pragma mark - Load methods

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
    [self startVideoLoadTimeoutTimer];
    
    void (^parserCompletionBlock)(VASTModel *vastModel, VASTError vastError) = ^(VASTModel *vastModel, VASTError vastError) {
        [SourceKitLogger debug:@"back from block in loadVideoFromData"];
        if (!vastModel) {
            [SourceKitLogger debug:@"parser error"];
            if ([self.delegate respondsToSelector:@selector(vastError:error:)]) {  // The VAST document was not readable, so no Error urls exist, thus none are sent.
                [self.delegate vastError:self error:vastError];
            }
            return;
        }
        
        self.eventProcessor = [[VASTEventProcessor alloc] initWithTrackingEvents:[vastModel trackingEvents]];
        impressions = [vastModel impressions];
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
            return;
        }
        
        // VAST document parsing OK, player ready to attempt play, so send vastReady
        [self stopVideoLoadTimeoutTimer];
        [SourceKitLogger debug:[NSString stringWithFormat:@"Sending vastReady: callback"]];
        vastReady = YES;
        [self.delegate vastReady:self];
    };
    
    VAST2Parser *parser = [[VAST2Parser alloc] init];
    if ([source isKindOfClass:[NSURL class]]) {
        if (!self.networkCurrentlyReachable) {
            [SourceKitLogger debug:@"No network available - VASTViewcontroller will not be presented"];
            if ([self.delegate respondsToSelector:@selector(vastError:error:)]) {
                [self.delegate vastError:self error:VASTErrorNoInternetConnection];  // There is network so no requests can be sent, we don't queue errors, so no external Error event is sent.
            }
            return;
        }
        [parser parseWithUrl:(NSURL *)source completion:parserCompletionBlock];     // Load the and parse the VAST document at the supplied URL
    } else {
        [parser parseWithData:(NSData *)source completion:parserCompletionBlock];   // Parse a VAST document in supplied data
    }
}

#pragma mark - View lifecycle

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    isViewOnScreen=YES;
    if (!hasPlayerStarted) {
        loadingIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
        loadingIndicator.frame = CGRectMake( (self.view.frame.size.height/2)-25.0, (self.view.frame.size.width/2)-25.0,50,50);
        [loadingIndicator startAnimating];
        [self.view addSubview:loadingIndicator];
    } else {
        // resuming from background or phone call, so resume if was playing, stay paused if manually paused
        [self handleResumeState];
    }
}

-(void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    statusBarHidden = [[UIApplication sharedApplication] isStatusBarHidden];
    if (SYSTEM_VERSION_LESS_THAN(@"7.0")) {
        [[UIApplication sharedApplication] setStatusBarHidden:YES withAnimation:UIStatusBarAnimationNone];
    }
}

-(void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    if (SYSTEM_VERSION_LESS_THAN(@"7.0")) {
        [[UIApplication sharedApplication] setStatusBarHidden:statusBarHidden withAnimation:UIStatusBarAnimationNone];
    }
}

#pragma mark - App lifecycle

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    [SourceKitLogger debug:@"applicationDidBecomeActive"];
    [self handleResumeState];
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
                if (loadingIndicator) {
                    [loadingIndicator stopAnimating];
                    [loadingIndicator removeFromSuperview];
                    loadingIndicator = nil;
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

- (void)moviePlayerLoadStateChanged:(NSNotification *)notification
{
    [SourceKitLogger debug:[NSString stringWithFormat:@"movie player load state is %i", self.moviePlayer.loadState]];
    
    if ((self.moviePlayer.loadState & MPMovieLoadStatePlaythroughOK) == MPMovieLoadStatePlaythroughOK )
    {
        [[NSNotificationCenter defaultCenter] removeObserver:self name:MPMoviePlayerLoadStateDidChangeNotification object:nil];
        [self showAndPlayVideo];
    }
}

- (void)moviePlayBackDidFinish:(NSNotification *)notification
{
    @synchronized(self) {
        [SourceKitLogger debug:@"playback did finish"];
        
        NSDictionary* userInfo=[notification userInfo];
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
            [self close];
        } else {
            // no error, clean finish, so send track complete
            [self.eventProcessor trackEvent:VASTEventTrackComplete];
            [self updatePlayedSeconds];
            [controls showControls];
            [controls toggleToPlayButton:YES];
        }
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
        [self close];
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
    
    [SourceKitLogger debug:[ NSString stringWithFormat:@"movie source type is %i", sourceType]];
}

#pragma mark - Orientation handling

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

#pragma mark - Timers

// playbackTimer - keeps track of currentPlayedPercentage
- (void)startPlaybackTimer
{
    @synchronized (self) {
        [self stopPlaybackTimer];
        [SourceKitLogger debug:@"start playback timer"];
        playbackTimer = [NSTimer scheduledTimerWithTimeInterval:kPlayTimeCounterInterval
                                                         target:self
                                                       selector:@selector(updatePlayedSeconds)
                                                       userInfo:nil
                                                        repeats:YES];
    }
}

- (void)stopPlaybackTimer
{
    [SourceKitLogger debug:@"stop playback timer"];
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
            [self close];
        }
        [self.videoHangTest removeObjectAtIndex:0];   // remove oldest number from start of hang test buffer
    }
    
   	currentPlayedPercentage = (float)100.0*(playedSeconds/movieDuration);
    [controls updateProgressBar: currentPlayedPercentage/100.0 withPlayedSeconds:playedSeconds withTotalDuration:movieDuration];
    
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

// Reports error if vast video document times out while loading
- (void)startVideoLoadTimeoutTimer
{
    [self stopVideoLoadTimeoutTimer];
    videoLoadTimeoutTimer = [NSTimer scheduledTimerWithTimeInterval:kVideoLoadTimeoutInterval
                                                             target:self
                                                           selector:@selector(videoLoadTimeout)
                                                           userInfo:nil
                                                            repeats:NO];
}

- (void)stopVideoLoadTimeoutTimer
{
    [videoLoadTimeoutTimer invalidate];
    videoLoadTimeoutTimer = nil;
}

- (void)videoLoadTimeout
{
    [SourceKitLogger debug:@"Video Load Timeout"];
    if (vastErrors) {
        [SourceKitLogger debug:@"Sending Error requests"];
        [self.eventProcessor sendVASTUrlsWithId:vastErrors];
    }
    if ([self.delegate respondsToSelector:@selector(vastError:error:)]) {
        [self.delegate vastError:self error:VASTErrorLoadTimeout];
    }
}

- (void)killTimers
{
    [self stopPlaybackTimer];
    [self stopVideoLoadTimeoutTimer];
}

#pragma mark - Methods needed to support toolbar buttons

- (void)play
{
    @synchronized (self) {
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
            return;
        }
        
        // Now we are ready to launch the player and start buffering the content
        // It will throw error if the url is invalid for any reason. In this case, we don't even need to open ViewController.
        [SourceKitLogger debug:@"initializing player"];
        
        @try {
            playedSeconds = 0.0;
            currentPlayedPercentage = 0.0;
            
            // Create and prepare the player to confirm the video is playable (or not) as early as possible
            self.moviePlayer = [[MPMoviePlayerController alloc] initWithContentURL: mediaFileURL];
            self.moviePlayer.shouldAutoplay = NO; // YES by default - But we don't want to autoplay
            self.moviePlayer.controlStyle=MPMovieControlStyleNone;  // To use custom control toolbar
            [self.moviePlayer prepareToPlay];
            [self presentPlayer];
        }
        @catch (NSException *e) {
            [SourceKitLogger debug:[NSString stringWithFormat:@"Exception - moviePlayer.prepareToPlay: %@", e]];
            if ([self.delegate respondsToSelector:@selector(vastError:error:)]) {
                [self.delegate vastError:self error:VASTErrorPlaybackError];
            }
            if (vastErrors) {
                [SourceKitLogger debug:@"Sending Error requests"];
                [self.eventProcessor sendVASTUrlsWithId:vastErrors];
            }
            return;
        }
    }
}

- (void)pause
{
    [SourceKitLogger debug:@"pause"];
    [self handlePauseState];
}

- (void)resume
{
    [SourceKitLogger debug:@"resume"];
    [self handleResumeState];
}

- (void)info
{
    if (clickTracking) {
        [SourceKitLogger debug:@"Sending clickTracking requests"];
        [self.eventProcessor sendVASTUrlsWithId:clickTracking];
    }
    if ([self.delegate respondsToSelector:@selector(vastOpenBrowseWithUrl:)]) {
        [self.delegate vastOpenBrowseWithUrl:self.clickThrough];
    }
}

- (void)close
{
    @synchronized (self) {
        [self.moviePlayer stop];
        [self removeObservers];
        [self killTimers];
        
        self.moviePlayer=nil;
        
        if (isViewOnScreen) {
            // send close any time the player has been dismissed
            [self.eventProcessor trackEvent:VASTEventTrackClose];
            [SourceKitLogger debug:@"Dismissing VASTViewController"];
            [self dismissViewControllerAnimated:NO completion:nil];
            
            if ([self.delegate respondsToSelector:@selector(vastDidDismissFullScreen:)]) {
                [self.delegate vastDidDismissFullScreen:self];
            }
        }
    }
}

//
// Handle touches
//
#pragma mark - Gesture setup & delegate

- (void)setUpTapGestureRecognizer
{
    self.touchGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTouches)];
    self.touchGestureRecognizer.delegate = self;
    [self.touchGestureRecognizer setNumberOfTouchesRequired:1];
    self.touchGestureRecognizer.cancelsTouchesInView=NO;  // required to enable controlToolbar buttons to receive touches
    [self.view addGestureRecognizer:self.touchGestureRecognizer];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch
{
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer
{
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

#pragma mark - Other methods

- (BOOL)isPlaying
{
    return isPlaying;
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
    
    [self.moviePlayer play];
    hasPlayerStarted=YES;
    
    if (impressions) {
        [SourceKitLogger debug:@"Sending Impressions requests"];
        [self.eventProcessor sendVASTUrlsWithId:impressions];
    }
    [self.eventProcessor trackEvent:VASTEventTrackStart];
    [self setUpTapGestureRecognizer];
}

- (void)removeObservers
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:MPMoviePlayerPlaybackStateDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:MPMoviePlayerPlaybackDidFinishNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:MPMovieDurationAvailableNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:MPMovieSourceTypeAvailableNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:MPMoviePlayerLoadStateDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidBecomeActiveNotification object:nil];
}

- (void)handlePauseState
{
    @synchronized (self) {
    if (isPlaying) {
        [SourceKitLogger debug:@"handle pausing player"];
        [self.moviePlayer pause];
        isPlaying = NO;
        [self.eventProcessor trackEvent:VASTEventTrackPause];
    }
    [self stopPlaybackTimer];
    }
}

- (void)handleResumeState
{
    @synchronized (self) {
    if (hasPlayerStarted) {
        if (![controls controlsPaused]) {
        // resuming from background or phone call, so resume if was playing, stay paused if manually paused by inspecting controls state
        [SourceKitLogger debug:@"handleResumeState, resuming player"];
        [self.moviePlayer play];
        isPlaying = YES;
        [self.eventProcessor trackEvent:VASTEventTrackResume];
        [self startPlaybackTimer];
        }
    } else if (self.moviePlayer) {
        [self showAndPlayVideo];   // Edge case: loadState is playable but not playThroughOK and had resignedActive, so play immediately on resume
    }
    }
}

- (void)presentPlayer
{
    if ([self.delegate respondsToSelector:@selector(vastWillPresentFullScreen:)]) {
        [self.delegate vastWillPresentFullScreen:self];
    }
    
    id rootViewController = [[UIApplication sharedApplication] keyWindow].rootViewController;
    if ([rootViewController respondsToSelector:@selector(presentViewController:animated:completion:)]) {
        // used if running >= iOS 6
        [rootViewController presentViewController:self animated:NO completion:nil];
    } else {
        // Turn off the warning about using a deprecated method.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [rootViewController presentModalViewController:self animated:NO];
#pragma clang diagnostic pop
    }
}

@end
