//
//  VASTControls.m
//  VAST
//
//  Created by Thomas Poland on 11/13/13.
//  Copyright (c) 2013 Nexage. All rights reserved.
//

#import "VASTControls.h"
#import "VASTViewController.h"
#import "SourceKitLogger.h"
#import <MediaPlayer/MediaPlayer.h>

static const float kControlTimerInterval = 2.0;
static const float kControlsToolbarHeight = 44.0;

#define SYSTEM_VERSION_LESS_THAN(v)     ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] == NSOrderedAscending)

@interface VASTControls ()
{
    NSTimer* controlsTimer;
    
    IBOutlet UIToolbar *controlToolbar;
    IBOutlet UIBarButtonItem *playButton;
    IBOutlet UIBarButtonItem *pauseButton;
    IBOutlet UIBarButtonItem *playbackTimeLabel;
    IBOutlet UIBarButtonItem *infoButton;
    
    UIProgressView *progressBar;
}

@property (nonatomic, unsafe_unretained) VASTViewController *player;

- (IBAction)pausePlay:(id)sender;
- (IBAction)info:(id)sender;
- (IBAction)dimiss:(id)sender;

@end

@implementation VASTControls

- (id)initWithVASTPlayer:(VASTViewController *)vastPlayer
{
    NSURL *resourceUrl = [[NSBundle mainBundle] URLForResource:@"VASTResources" withExtension:@"bundle"];
    
    NSBundle *bundle = [NSBundle bundleWithURL:resourceUrl];

    self = [super initWithNibName:@"VASTControlsView" bundle:bundle];
    
    if (self) {
        // Custom initialization
        _player = vastPlayer;
        self.view.frame = controlToolbar.frame;
        [self.view addSubview:controlToolbar];
        [self toggleToPlayButton:NO]; // initialize to pause, because the player starts playing immediately
        self.view.frame = CGRectMake(0, vastPlayer.view.bounds.size.height-self.view.frame.size.height, vastPlayer.view.bounds.size.width, self.view.frame.size.height);
        
        if (!vastPlayer.clickThrough) {
            NSMutableArray *toolbarButtons = [controlToolbar.items mutableCopy];
            [toolbarButtons removeObject:infoButton];
            [controlToolbar setItems:toolbarButtons animated:NO];
        }
        
        // Hide progress bar + time display in iOS 6.1 and below
        if (SYSTEM_VERSION_LESS_THAN(@"7.0")) {
            NSMutableArray *toolbarButtons = [controlToolbar.items mutableCopy];
            [toolbarButtons removeObject:playbackTimeLabel];
            [controlToolbar setItems:toolbarButtons animated:NO];
            
            // Set toolbar color
            [controlToolbar setTintColor:[UIColor blackColor]];
        } else {
            progressBar = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleBar];
            progressBar.frame = CGRectMake(0,0, self.view.frame.size.width, 10);
            progressBar.trackTintColor = [UIColor lightGrayColor];
            [self updateProgressBar:0 withPlayedSeconds:0 withTotalDuration:0];
            [self.view addSubview:progressBar];
        }
        
    }
    return self;
}


- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view.
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (IBAction)pausePlay:(id)sender
{
    [self.player pausePlay];
}

- (IBAction)info:(id)sender
{
    [self.player info];
}

- (IBAction)dimiss:(id)sender
{
    [self.player dismiss];
}

-(void)toggleToPlayButton:(BOOL)toggleToPlay
{
    @synchronized (self) {
        NSMutableArray *toolbarButtons = [controlToolbar.items mutableCopy];
        if (toggleToPlay) {  // show play button
            [toolbarButtons removeObject:pauseButton];
            if( [toolbarButtons containsObject: playButton ]) {
                [toolbarButtons removeObject: playButton];    // handle initial case
            }
            [toolbarButtons insertObject:playButton atIndex:1];
            [self stopControlsTimer];
            self.view.hidden = NO;  // always show the controls toobar when paused
            [SourceKitLogger debug:[NSString stringWithFormat:@"Toggle to playButton visible"]];
        } else {             // show pause button
            [toolbarButtons removeObject:playButton];
            if ([toolbarButtons containsObject: pauseButton]) {
                [toolbarButtons removeObject: pauseButton];    // handle initial case
            }
            [toolbarButtons insertObject:pauseButton atIndex:1];
            [self startControlsTimer];
            [SourceKitLogger debug:[NSString stringWithFormat:@"Toggle to pauseButton visible"]];
        }
        [controlToolbar setItems:toolbarButtons animated:NO];
    }
}

// controlsTimer - removes controls toolbar after the defined interval
- (void)startControlsTimer
{
    [self stopControlsTimer];

    controlsTimer = [NSTimer scheduledTimerWithTimeInterval:kControlTimerInterval
                                                     target:self
                                                   selector:@selector(hideControls)
                                                   userInfo:nil
                                                    repeats:NO];
}

- (void)showControls
{
    self.view.hidden = NO;
    [self startControlsTimer];
}

- (void)hideControls
{
    self.view.hidden = YES;
}

- (void)stopControlsTimer
{
    [controlsTimer invalidate];
    controlsTimer = nil;
}

- (void)updateProgressBar:(float)progress withPlayedSeconds:(float)playerSeconds withTotalDuration:(float)totalDuration
{
    [progressBar setProgress:progress animated:YES];
    int totalSeconds =  (int)totalDuration % 60;
    int totalMinutes = ((int)totalDuration / 60) % 60;
    int playedSeconds =  (int)playerSeconds % 60;
    int playedMinutes = (int)(playerSeconds / 60) % 60;
    playbackTimeLabel.title = [NSString stringWithFormat:@"%02d:%02d / %02d:%02d",playedMinutes, playedSeconds, totalMinutes, totalSeconds];
}

- (void)dealloc
{
    [self stopControlsTimer];
}

@end
