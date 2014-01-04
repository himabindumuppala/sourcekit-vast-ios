//
//  VAST_Tests.m
//  VAST Tests
//
//  Created by Muthu on 11/19/13.
//  Copyright (c) 2013 Nexage. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "VAST2Parser.h"
#import "VASTMediaFile.h"
#import "VASTMediaFilePicker.h"
#import "SourceKitLogger.h"

@interface VAST_Tests : XCTestCase

@end

@implementation VAST_Tests

- (void)setUp
{
    [super setUp];
    
    // Enable logging
    [SourceKitLogger setLogLevel:SourceKitLogLevelDebug];
}

- (void)tearDown
{
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

- (void)testPaserWithSimpleVAST
{
    NSURL *url = [NSURL URLWithString:@"http://adserver.adtechus.com/?advideo/3.0/5326.1/2344925/0//cc=2;vidAS=pre_roll;ip=;key=_Non-Mobile;kvip=;kvcarrier=;vidRTV=2.0;vidRT=VAST;misc=1381260694027;target=_self;"];
    
    [[VAST2Parser new] parseWithUrl:url completion:^(VASTModel *vastModel, VASTError error) {
        XCTAssertNil(vastModel, @"Failed to get model back");
    }];
}

- (void)testPaserReturningNil
{
    NSURL *url = [NSURL URLWithString:@"http://vast.tubemogul.com/vast/placement/ipyMwaO9IKkr7ljUG4Jx?rand=3940583"];
    
    [[VAST2Parser new] parseWithUrl:url completion:^(VASTModel *vastModel, VASTError vastError) {
        XCTAssertNotNil(vastModel, @"Expected a nil model but got something else");
    }];
}


- (void)testMediaFilePickerSelectMimeMP4
{
    NSMutableArray *mediaFileArray = [ NSMutableArray arrayWithCapacity:0];
    VASTMediaFile *mediaFile1 = [[VASTMediaFile alloc]
                                initWithId:             @"testMediaFile1"
                                delivery:               @"progressive"
                                type:       @"video/mp4"
                                bitrate:                @"500"
                                width:                  @"300"
                                height:                 @"400"
                                scalable:               @"true"
                                maintainAspectRatio:    @"false"
                                apiFramework:           @"aFrameworkName"
                                url:                    @"theMediaFileUrl"];
    
    VASTMediaFile *mediaFile2 = [[VASTMediaFile alloc]
                                 initWithId:             @"testMediaFile1"
                                 delivery:               @"progressive"
                                 type:     @"video/x-flv"
                                 bitrate:                @"500"
                                 width:                  @"300"
                                 height:                 @"400"
                                 scalable:               @"true"
                                 maintainAspectRatio:    @"false"
                                 apiFramework:           @"aFrameworkName"
                                 url:                    @"theMediaFileUrl"];

    VASTMediaFile *mediaFile3 = [[VASTMediaFile alloc]
                                 initWithId:             @"testMediaFile1"
                                 delivery:               @"progressive"
                                 type: @"video/x-msvideo"
                                 bitrate:                @"500"
                                 width:                  @"300"
                                 height:                 @"400"
                                 scalable:               @"true"
                                 maintainAspectRatio:    @"false"
                                 apiFramework:           @"aFrameworkName"
                                 url:                    @"theMediaFileUrl"];

    [mediaFileArray addObject:mediaFile1];
    [mediaFileArray addObject:mediaFile2];
    [mediaFileArray addObject:mediaFile3];
    
    XCTAssertEqualObjects(mediaFile1,  [VASTMediaFilePicker pick:mediaFileArray], @"Expected but did not pick the video/mp4 mime type media file");
}

- (void)testMediaFilePickerNonVideoMimeType
{
    NSMutableArray *mediaFileArray = [ NSMutableArray arrayWithCapacity:0];
    VASTMediaFile *mediaFile1 = [[VASTMediaFile alloc]
                                 initWithId:             @"testMediaFile1"
                                 delivery:               @"progressive"
                                 type: @"text/javascript"
                                 bitrate:                @"500"
                                 width:                  @"300"
                                 height:                 @"400"
                                 scalable:               @"true"
                                 maintainAspectRatio:    @"false"
                                 apiFramework:           @"aFrameworkName"
                                 url:                    @"theMediaFileUrl"];
    
    [mediaFileArray addObject:mediaFile1];
    
    XCTAssertNil([VASTMediaFilePicker pick:mediaFileArray], @"Expected nil for unsupported mime type, but got something else");
}

- (void)testMediaFilePickerInvalidMimeType
{
    NSMutableArray *mediaFileArray = [ NSMutableArray arrayWithCapacity:0];
    VASTMediaFile *mediaFile1 = [[VASTMediaFile alloc]
                                 initWithId:             @"testMediaFile1"
                                 delivery:               @"progressive"
                                 type: @"not a mime type"
                                 bitrate:                @"500"
                                 width:                  @"300"
                                 height:                 @"400"
                                 scalable:               @"true"
                                 maintainAspectRatio:    @"false"
                                 apiFramework:           @"aFrameworkName"
                                 url:                    @"theMediaFileUrl"];
    
    [mediaFileArray addObject:mediaFile1];
    
    XCTAssertNil([VASTMediaFilePicker pick:mediaFileArray], @"Expected nil for unsupported mime type, but got something else");
}

- (void)testMediaFilePickerSizedForPhoneVSiPad
{
    NSMutableArray *mediaFileArray = [ NSMutableArray arrayWithCapacity:0];
    VASTMediaFile *mediaFile1 = [[VASTMediaFile alloc]
                                 initWithId:             @"testMediaFile1"
                                 delivery:               @"progressive"
                                 type:                   @"video/mp4"
                                 bitrate:                @"500"
                                 width:            @"320"
                                 height:           @"480"
                                 scalable:               @"true"
                                 maintainAspectRatio:    @"false"
                                 apiFramework:           @"aFrameworkName"
                                 url:                    @"theMediaFileUrl"];
    
    VASTMediaFile *mediaFile2 = [[VASTMediaFile alloc]
                                 initWithId:             @"testMediaFile2"
                                 delivery:               @"progressive"
                                 type:                   @"video/mp4"
                                 bitrate:                @"500"
                                 width:           @"640"
                                 height:          @"360"
                                 scalable:               @"true"
                                 maintainAspectRatio:    @"false"
                                 apiFramework:           @"aFrameworkName"
                                 url:                    @"theMediaFileUrl"];
    
    VASTMediaFile *mediaFile3 = [[VASTMediaFile alloc]
                                 initWithId:             @"testMediaFile3"
                                 delivery:               @"progressive"
                                 type:                   @"video/mp4"
                                 bitrate:                @"500"
                                 width:            @"176"
                                 height:           @"244"
                                 scalable:               @"true"
                                 maintainAspectRatio:    @"false"
                                 apiFramework:           @"aFrameworkName"
                                 url:                    @"theMediaFileUrl"];
    
    [mediaFileArray addObject:mediaFile1];
    [mediaFileArray addObject:mediaFile2];
    [mediaFileArray addObject:mediaFile3];
    
    if ( UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad )
    {
        XCTAssertEqualObjects(mediaFile2, [VASTMediaFilePicker pick:mediaFileArray], @"Expected but did not pick the media file sized 640x360 for iPad");
    } else {
        XCTAssertEqualObjects(mediaFile1, [VASTMediaFilePicker pick:mediaFileArray], @"Expected but did not pick the media file sized 320x480 for phone");
    }
}

- (void)testMediaFilePickerOfEqualDimension
{
    NSMutableArray *mediaFileArray = [ NSMutableArray arrayWithCapacity:0];
    VASTMediaFile *mediaFile1 = [[VASTMediaFile alloc]
                                 initWithId:             @"testMediaFile1"
                                 delivery:               @"progressive"
                                 type:                   @"video/mp4"
                                 bitrate:                @"500"
                                 width:            @"320"
                                 height:           @"480"
                                 scalable:               @"true"
                                 maintainAspectRatio:    @"false"
                                 apiFramework:           @"aFrameworkName"
                                 url:                    @"theMediaFileUrl1"];
    
    VASTMediaFile *mediaFile2 = [[VASTMediaFile alloc]
                                 initWithId:             @"testMediaFile2"
                                 delivery:               @"progressive"
                                 type:                   @"video/mp4"
                                 bitrate:                @"500"
                                 width:            @"320"
                                 height:           @"480"
                                 scalable:               @"true"
                                 maintainAspectRatio:    @"false"
                                 apiFramework:           @"aFrameworkName"
                                 url:                    @"theMediaFileUrl2"];
    
    VASTMediaFile *mediaFile3 = [[VASTMediaFile alloc]
                                 initWithId:             @"testMediaFile3"
                                 delivery:               @"progressive"
                                 type:                   @"video/mp4"
                                 bitrate:                @"500"
                                 width:            @"320"
                                 height:           @"480"
                                 scalable:               @"true"
                                 maintainAspectRatio:    @"false"
                                 apiFramework:           @"aFrameworkName"
                                 url:                    @"theMediaFileUrl3"];
    
    [mediaFileArray addObject:mediaFile1];
    [mediaFileArray addObject:mediaFile2];
    [mediaFileArray addObject:mediaFile3];
    
    VASTMediaFile *mediaFilePickerPickedFile = [VASTMediaFilePicker pick:mediaFileArray];
    XCTAssertEqualObjects(mediaFile1, mediaFilePickerPickedFile, @"Expected but did not pick the media file sized 320x480");
}

- (void)testMediaFilePickerOnlyOneFile
{
    NSMutableArray *mediaFileArray = [ NSMutableArray arrayWithCapacity:0];
    VASTMediaFile *mediaFile1 = [[VASTMediaFile alloc]
                                 initWithId:             @"testMediaFile1"
                                 delivery:               @"progressive"
                                 type:                   @"video/mp4"
                                 bitrate:                @"500"
                                 width:            @"320"
                                 height:           @"480"
                                 scalable:               @"true"
                                 maintainAspectRatio:    @"false"
                                 apiFramework:           @"aFrameworkName"
                                 url:                    @"theMediaFileUrl"];
   
    
    [mediaFileArray addObject:mediaFile1];
    
    XCTAssertEqualObjects(mediaFile1, [VASTMediaFilePicker pick:mediaFileArray], @"Expected but did not pick the media file sized 320x480 for phone");
}

- (void)testMediaFilePickerTakeFirstNotSecondEqualSizedFiles
{
    NSMutableArray *mediaFileArray = [ NSMutableArray arrayWithCapacity:0];
    VASTMediaFile *mediaFile1 = [[VASTMediaFile alloc]
                                 initWithId:             @"testMediaFile1"
                                 delivery:               @"progressive"
                                 type:                   @"video/mp4"
                                 bitrate:                @"500"
                                 width:            @"320"
                                 height:           @"480"
                                 scalable:               @"true"
                                 maintainAspectRatio:    @"false"
                                 apiFramework:           @"aFrameworkName"
                                 url:                    @"theMediaFileUrl"];
    
    VASTMediaFile *mediaFile2 = [[VASTMediaFile alloc]
                                 initWithId:             @"testMediaFile2"
                                 delivery:               @"progressive"
                                 type:                   @"video/mp4"
                                 bitrate:                @"500"
                                 width:           @"480"
                                 height:          @"320"
                                 scalable:               @"true"
                                 maintainAspectRatio:    @"false"
                                 apiFramework:           @"aFrameworkName"
                                 url:                    @"theMediaFileUrl"];
    
    VASTMediaFile *mediaFile3 = [[VASTMediaFile alloc]
                                 initWithId:             @"testMediaFile3"
                                 delivery:               @"progressive"
                                 type:                   @"video/mp4"
                                 bitrate:                @"500"
                                 width:            @"176"
                                 height:           @"244"
                                 scalable:               @"true"
                                 maintainAspectRatio:    @"false"
                                 apiFramework:           @"aFrameworkName"
                                 url:                    @"theMediaFileUrl"];
    
    [mediaFileArray addObject:mediaFile1];
    [mediaFileArray addObject:mediaFile2];
    [mediaFileArray addObject:mediaFile3];
    
    XCTAssertEqualObjects(mediaFile1, [VASTMediaFilePicker pick:mediaFileArray], @"Expected but did not pick the first media file sized 320x480 for phone");
}

- (void)testMediaFilePickerSizedForPhone3r5vs4inch
{
    NSMutableArray *mediaFileArray = [ NSMutableArray arrayWithCapacity:0];
    VASTMediaFile *mediaFile1 = [[VASTMediaFile alloc]
                                 initWithId:             @"testMediaFile1"
                                 delivery:               @"progressive"
                                 type:                   @"video/mp4"
                                 bitrate:                @"500"
                                 width:            @"300"    // N.B. 300x400 is a not a valid aspect ratio; it is contrived for this test of the FilePicker
                                 height:           @"400"
                                 scalable:               @"true"
                                 maintainAspectRatio:    @"false"
                                 apiFramework:           @"aFrameworkName"
                                 url:                    @"theMediaFileUrl"];
    
    VASTMediaFile *mediaFile2 = [[VASTMediaFile alloc]
                                 initWithId:             @"testMediaFile2"
                                 delivery:               @"progressive"
                                 type:                   @"video/mp4"
                                 bitrate:                @"500"
                                 width:           @"640"
                                 height:          @"360"
                                 scalable:               @"true"
                                 maintainAspectRatio:    @"false"
                                 apiFramework:           @"aFrameworkName"
                                 url:                    @"theMediaFileUrl"];
    
    VASTMediaFile *mediaFile3 = [[VASTMediaFile alloc]
                                 initWithId:             @"testMediaFile3"
                                 delivery:               @"progressive"
                                 type:                   @"video/mp4"
                                 bitrate:                @"500"
                                 width:            @"176"
                                 height:           @"244"
                                 scalable:               @"true"
                                 maintainAspectRatio:    @"false"
                                 apiFramework:           @"aFrameworkName"
                                 url:                    @"theMediaFileUrl"];
    
    [mediaFileArray addObject:mediaFile1];
    [mediaFileArray addObject:mediaFile2];
    [mediaFileArray addObject:mediaFile3];
    
    CGSize screenSize = [[UIScreen mainScreen] bounds].size;
    
    if (screenSize.height>480) {
        // 4" device
        XCTAssertEqualObjects(mediaFile2, [VASTMediaFilePicker pick:mediaFileArray], @"Expected but did not pick the media file sized 640 x 360 for 4\" phone");
    } else {
        // 3.5" device
        XCTAssertEqualObjects(mediaFile1, [VASTMediaFilePicker pick:mediaFileArray], @"Expected but did not pick the media file sized 300x400 3.5\" for phone");
    }
}

@end
