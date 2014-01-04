//
//  CreativesTVC.m
//  VASTDemo
//
//  Created by Muthu on 10/2/13.
//  Copyright (c) 2013 Nexage. All rights reserved.
//

#import "CreativesTVC.h"

#import "VAST.h"
#import "SourceKitLogger.h"

@interface CreativesTVC () <VASTViewControllerDelegate>
{
    VASTViewController *vastVC;
}

@end

@implementation CreativesTVC

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
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
        vastVC = [[VASTViewController alloc] initWithDelegate:self];
        [vastVC loadVideoWithData:fileContent];
    }
}

#pragma mark - VASTViewControllerDelegate

- (void)vastReady:(VASTViewController *)vc
{
    NSLog(@"callback %@", NSStringFromSelector(_cmd));
    [vc playVideo];
}

- (void)vastWillPresentFullScreen:(VASTViewController *)vc;
{
    NSLog(@"callback %@", NSStringFromSelector(_cmd));
}

- (void)vastDidDismissFullScreen:(VASTViewController *)vc;
{
    NSLog(@"callback %@", NSStringFromSelector(_cmd));
}

-(void)vastError:(VASTViewController *)vastVC error:(VASTError)error
{
    NSLog(@"callback %@ %d", NSStringFromSelector(_cmd), error);
}

-(void)vastOpenBrowseWithUrl:(NSURL *)url
{
    NSLog(@"callback %@", NSStringFromSelector(_cmd));
    [[UIApplication sharedApplication] openURL:url];
}

@end
