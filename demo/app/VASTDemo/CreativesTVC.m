//
//  CreativesTVC.m
//  VASTDemo
//
//  Created by Muthu on 10/2/13.
//  Copyright (c) 2013 Nexage. All rights reserved.
//

#import "CreativesTVC.h"
#import "SKVASTError.h"
#import "SKVASTViewController.h"
#import "VASTSettings.h"
#import "SKBrowser.h"

@interface CreativesTVC () <SKVASTViewControllerDelegate, SKBrowserDelegate>
{
    SKVASTViewController *vastVC;
}

@end

@implementation CreativesTVC

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:NO];
    
    // Cleanup vastVC if it was used before
    if (vastVC) {
        vastVC.delegate = nil;
        vastVC = nil;
    }
    
    // Load creative
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
    if (cell)
    {
        NSLog(@"Cell contains: %@ - %@", cell.textLabel.text, cell.detailTextLabel.text);
    
        NSString *xmlPath = [[NSBundle mainBundle] pathForResource:cell.detailTextLabel.text ofType:@"xml"];
        NSData *fileContent = [NSData dataWithContentsOfFile:xmlPath];
        vastVC = [[SKVASTViewController alloc] initWithDelegate:self];
        [vastVC loadVideoWithData:fileContent];
    }
}

#pragma mark - VASTViewControllerDelegate

- (void)vastReady:(SKVASTViewController *)vc
{
    NSLog(@"callback %@", NSStringFromSelector(_cmd));
    [vc play];
}

- (void)vastWillPresentFullScreen:(SKVASTViewController *)vc;
{
    NSLog(@"callback %@", NSStringFromSelector(_cmd));
}

- (void)vastDidDismissFullScreen:(SKVASTViewController *)vc;
{
    NSLog(@"callback %@", NSStringFromSelector(_cmd));
}

-(void)vastError:(SKVASTViewController *)vastVC error:(SKVASTError)error
{
    NSLog(@"callback %@ %d", NSStringFromSelector(_cmd), error);
}

-(void)vastOpenBrowseWithUrl:(NSURL *)url
{
    NSLog(@"callback %@", NSStringFromSelector(_cmd));

    if ([vastVC isPlaying])
        [vastVC pause];
    
    SKBrowser *browser = [[SKBrowser alloc] initWithDelegate:nil
                                                              withFeatures:@[kSourceKitBrowserFeatureSupportInlineMediaPlayback,
                                                                             kSourceKitBrowserFeatureDisableStatusBar,
                                                                             kSourceKitBrowserFeatureScalePagesToFit]];
    [browser loadRequest:[NSURLRequest requestWithURL:url]];
}

-(void)vastTrackingEvent:(NSString *)eventName
{
    NSLog(@"callback for event %@", eventName);
}

#pragma mark - SourceKitBrowserDelegate

- (void)sourceKitBrowserClosed:(SKBrowser *)sourceKitBrowser
{
    NSLog(@"SourceKit Browser was closed");
}

- (void)sourceKitBrowserWillExitApp:(SKBrowser *)sourceKitBrowser
{
    NSLog(@"SourceKit Browser will be exiting the app");
}

@end
