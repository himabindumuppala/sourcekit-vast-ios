//
//  VAST2Parser.m
//  VAST
//
//  Created by Jay Tucker on 10/2/13.
//  Copyright (c) 2013 Nexage. All rights reserved.
//

#import "VAST2Parser.h"
#import "VASTXMLUtil.h"
#import "VASTModel.h"
#import "VASTError.h"
#import "VASTSchema.h"
#import "SourceKitLogger.h"

static int kMaxRecursiveDepth = 5;

@interface VAST2Parser ()
{
    VASTModel *vastModel;
}

- (VASTError)parseRecursivelyWithData:(NSData *)vastData depth:(int)depth;

@end

@implementation VAST2Parser

- (id)init
{
    self = [super init];
    if (self) {
        vastModel = [[VASTModel alloc] init];
    }
    return self;
}

#pragma mark - "public" methods

- (void)parseWithUrl:(NSURL *)url completion:(void (^)(VASTModel *, VASTError))block
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSData *vastData = [NSData dataWithContentsOfURL:url];
        VASTError vastError = [self parseRecursivelyWithData:vastData depth:0];
        dispatch_async(dispatch_get_main_queue(), ^{
            block(vastModel, vastError);
        });
    });
}

- (void)parseWithData:(NSData *)vastData completion:(void (^)(VASTModel *, VASTError))block
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        VASTError vastError = [self parseRecursivelyWithData:vastData depth:0];
        dispatch_async(dispatch_get_main_queue(), ^{
            block(vastModel, vastError);
        });
    });
}

#pragma mark - "private" method

- (VASTError)parseRecursivelyWithData:(NSData *)vastData depth:(int)depth
{
    if (depth >= kMaxRecursiveDepth) {
        vastModel = nil;
        return VASTErrorTooManyWrappers;
    }
    
    // sanity check
    NSString *content = [[NSString alloc] initWithData:vastData encoding:NSUTF8StringEncoding];
    [SourceKitLogger debug:[NSString stringWithFormat:@"VAST file\n%@", content]];

    // Validate the basic XML syntax of the VAST document.
    BOOL isValid;
    isValid = validateXMLDocSyntax(vastData);
    if (!isValid) {
        vastModel = nil;
        return VASTErrorXMLParse;
    }

//  Uncomment this section in order to validate the VAST document's schema
//
//    // Using header data
//    NSData *vastSchemaData = [NSData dataWithBytesNoCopy:vast_2_0_1_xsd
//                                               length:vast_2_0_1_xsd_len
//                                         freeWhenDone:NO];
//    isValid = validateXMLDocAgainstSchema(vastData, vastSchemaData);
//    if (!isValid) {
//        vastModel = nil;
//        return VASTErrorSchemaValidation;
//    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"
    [vastModel performSelector:@selector(addVASTDocument:) withObject:vastData];
#pragma clang diagnostic pop
    
    // Check to see whether this is a wrapper ad. If so, process it.
    NSString *query = @"//VASTAdTagURI";
    NSArray *results = performXMLXPathQuery(vastData, query);
    if ([results count] > 0) {
        NSString *url;
        NSDictionary *node = results[0];
        if ([node[@"nodeContent"] length] > 0) {
            // this is for string data
            url =  node[@"nodeContent"];
        } else {
            // this is for CDATA
            NSArray *childArray = node[@"nodeChildArray"];
            if ([childArray count] > 0) {
                // we assume that there's only one element in the array
                url = ((NSDictionary *)childArray[0])[@"nodeContent"];
            }
        }
        vastData = [NSData dataWithContentsOfURL:[NSURL URLWithString:url]];
        return [self parseRecursivelyWithData:vastData depth:(depth + 1)];
    }
    
    return VASTErrorNone;
}

- (NSString *)content:(NSDictionary *)node
{
    // this is for string data
    if ([node[@"nodeContent"] length] > 0) {
        return node[@"nodeContent"];
    }
    
    // this is for CDATA
    NSArray *childArray = node[@"nodeChildArray"];
    if ([childArray count] > 0) {
        // we assume that there's only one element in the array
        return ((NSDictionary *)childArray[0])[@"nodeContent"];
    }
    
    return nil;
}

@end
