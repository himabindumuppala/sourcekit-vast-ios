//
//  AboutVC.m
//  VASTDemo
//
//  Created by Muthu on 11/21/13.
//  Copyright (c) 2013 Nexage, Inc. All rights reserved.
//

#import "AboutVC.h"
#import "VASTSettings.h"

@interface AboutVC ()

@end

@implementation AboutVC

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
	
    // Fill version string
    [self.versionLabel setText:[NSString stringWithFormat:@"VAST SourceKit v%@ & Demo v%@", kVASTKitVersion, [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"]]];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
