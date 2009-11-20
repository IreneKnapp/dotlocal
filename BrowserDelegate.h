//  -*- mode: objc -*-
//  BrowserDelegate.h
//  Local
//
//  Created by Dan Knapp on 11/19/09.
//  Copyright 2009 Dan Knapp. All rights reserved.
//

#import <Foundation/Foundation.h>


enum enumerationMode {
    notEnumerating,
    enumeratingDomains,
    enumeratingServiceTypes,
    enumeratingServices,
    resolvingServices,
};


@interface BrowserDelegate : NSObject
<NSNetServiceDelegate, NSNetServiceBrowserDelegate>
{
    NSNetServiceBrowser *browser;
    BOOL isDone;
    BOOL outputNames;
    BOOL longMode;
    BOOL lowLevelNames;
    BOOL ipAddresses;
    enum enumerationMode enumerationMode;
    NSUInteger domainIndex;
    NSUInteger serviceTypeIndex;
    NSUInteger serviceIndex;
    NSMutableArray *domains;
    NSMutableArray *serviceTypes;
    NSMutableArray *services;
    NSMutableDictionary *servicesGroupedByName;
}
@property (assign) BOOL isDone;

- (id) initNames: (BOOL) useNames
	longMode: (BOOL) useLongMode
   lowLevelNames: (BOOL) useLowLevelNames
     ipAddresses: (BOOL) useIPAddresses;
- (void) enumerateDomains;
- (void) enumerateServiceTypes;
- (void) enumerateServiceTypesForOneDomain;
- (void) enumerateServices;
- (void) enumerateServicesForOneDomain;
- (void) enumerateServicesForOneDomainAndServiceType;
- (void) resolveServices;
- (void) resolveOneService;
- (void) netServiceBrowser: (NSNetServiceBrowser *) netServiceBrowser
	     didFindDomain: (NSString *) foundDomain
		moreComing: (BOOL) moreDomainsComing;
- (void) netServiceBrowser: (NSNetServiceBrowser *) netServiceBrowser
	    didFindService: (NSNetService *) foundService
		moreComing: (BOOL) moreServicesComing;
- (void) netServiceDidResolveAddress: (NSNetService *) sender;
- (void) netService: (NSNetService *) sender
      didNotResolve: (NSDictionary *) errorDict;
- (void) printReport;
@end
