//
//  BrowserDelegate.m
//  Local
//
//  Created by Dan Knapp on 11/19/09.
//  Copyright 2009 Dan Knapp. All rights reserved.
//

#import <stdio.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import "BrowserDelegate.h"


@implementation BrowserDelegate
@synthesize isDone;
extern NSString *nameTable[];


- (id) initNames: (BOOL) useNames
	longMode: (BOOL) useLongMode
   lowLevelNames: (BOOL) useLowLevelNames
     ipAddresses: (BOOL) useIPAddresses
{
    self = [super init];
    if(self) {
	isDone = FALSE;
	outputNames = useNames;
	longMode = useLongMode;
	lowLevelNames = useLowLevelNames;
	ipAddresses = useIPAddresses;
	enumerationMode = notEnumerating;
	
	domains = [[NSMutableArray alloc] initWithCapacity: 10];
	serviceTypes = [[NSMutableArray alloc] initWithCapacity: 10];
	services = [[NSMutableArray alloc] initWithCapacity: 100];
	servicesGroupedByName = [[NSMutableDictionary alloc] initWithCapacity: 100];
	
	browser = [[NSNetServiceBrowser alloc] init];
	[browser setDelegate: self];

	[self enumerateDomains];
    }
    return self;
}


- (void) enumerateDomains {
    enumerationMode = enumeratingDomains;
    
    [browser searchForBrowsableDomains];
}


- (void) enumerateServiceTypes {
    enumerationMode = enumeratingServiceTypes;

    domainIndex = 0;
    [self enumerateServiceTypesForOneDomain];
}


- (void) enumerateServiceTypesForOneDomain {
    if([domains count] > domainIndex) {
	[browser stop];
	[browser searchForServicesOfType: @"_services._dns-sd._udp."
		 inDomain: [domains objectAtIndex: domainIndex]];
    } else {
	[self enumerateServices];
    }
}


- (void) enumerateServices {
    enumerationMode = enumeratingServices;
    
    domainIndex = 0;
    [self enumerateServicesForOneDomain];
}


- (void) enumerateServicesForOneDomain {
    if([domains count] > domainIndex) {
	serviceTypeIndex = 0;
	[self enumerateServicesForOneDomainAndServiceType];
    } else {
	[self resolveServices];
    }
}


- (void) enumerateServicesForOneDomainAndServiceType {
    if([serviceTypes count] > serviceTypeIndex) {
	[browser stop];
	[browser searchForServicesOfType: [serviceTypes objectAtIndex: serviceTypeIndex]
		 inDomain: [domains objectAtIndex: domainIndex]];
    } else {
	domainIndex++;
	[self enumerateServicesForOneDomain];
    }
}


- (void) resolveServices {
    enumerationMode = resolvingServices;

    serviceIndex = 0;
    [self resolveOneService];
}


- (void) resolveOneService {
    if([services count] > serviceIndex) {
	NSNetService *service = [services objectAtIndex: serviceIndex];
	[service setDelegate: self];
	[service resolveWithTimeout: 5.0];
    } else {
	[self printReport];
	isDone = TRUE;
	exit(0);
    }
}


- (void) netServiceBrowser: (NSNetServiceBrowser *) netServiceBrowser
	     didFindDomain: (NSString *) foundDomain
		moreComing: (BOOL) moreDomainsComing
{
    if(enumerationMode == enumeratingDomains) {
	[domains addObject: foundDomain];
	
	if(!moreDomainsComing)
	    [self enumerateServiceTypes];
    }
}


- (void) netServiceBrowser: (NSNetServiceBrowser *) netServiceBrowser
	    didFindService: (NSNetService *) foundService
		moreComing: (BOOL) moreServicesComing
{
    if(enumerationMode == enumeratingServiceTypes) {
	NSString *domain = [domains objectAtIndex: domainIndex];
	NSString *serviceType
	    = [NSString stringWithFormat: @"%@.%@",
			[foundService name],
			[[foundService type]
			    substringToIndex:
				[[foundService type] length] - [domain length] - 1]];
	[serviceTypes addObject: serviceType];
	
	if(!moreServicesComing) {
	    domainIndex++;
	    [self enumerateServiceTypesForOneDomain];
	}
    } else if(enumerationMode == enumeratingServices) {
	[services addObject: foundService];
	
	if(!moreServicesComing) {
	    serviceTypeIndex++;
	    [self enumerateServicesForOneDomainAndServiceType];
	}
    }
}


- (void) netServiceDidResolveAddress: (NSNetService *) sender {
    if(enumerationMode == resolvingServices) {
	serviceIndex++;
	[self resolveOneService];
    }
}


- (void) netService: (NSNetService *) sender
      didNotResolve: (NSDictionary *) errorDict
{
    if(enumerationMode == resolvingServices) {
	serviceIndex++;
	[self resolveOneService];
    }
}


- (void) printReport {
    for(NSNetService *service in services) {
	NSString *name = [NSString stringWithFormat: @"%@.%@",
				   [service name],
				   [service domain]];
	NSMutableArray *serviceGroup = [servicesGroupedByName objectForKey: name];
	if(!serviceGroup) {
	    serviceGroup = [[NSMutableArray alloc] initWithCapacity: 10];
	    [servicesGroupedByName setObject: serviceGroup forKey: name];
	}
	[serviceGroup addObject: service];
    }
    
    NSArray *sortedNames
	= [[servicesGroupedByName allKeys]
	      sortedArrayUsingComparator: ^(id a, id b)
	      {
		  return [(NSString *) a compare: (NSString *) b
				       options: NSCaseInsensitiveSearch];
	      }];
    for(NSString *name in sortedNames) {
	NSMutableArray *serviceGroup = [servicesGroupedByName objectForKey: name];
	
	NSString *friendlyName;
	if([name characterAtIndex: [name length]-1] == '.')
	    friendlyName = [name substringToIndex: [name length]-1];
	else
	    friendlyName = name;
	for(int i = 0; i < [friendlyName length]; i++) {
	    if([friendlyName characterAtIndex: i] == ' ') {
		friendlyName = [NSString stringWithFormat: @"\"%@\"", friendlyName];
		break;
	    }
	}

	NSString *ipAddress = nil;
	if(ipAddresses) {
	    NSNetService *service = [serviceGroup objectAtIndex: 0];
	    for(NSData *address in [service addresses]) {
		struct sockaddr *sockaddr = (struct sockaddr *) [address bytes];
		if(sockaddr->sa_family == AF_INET) {
		    struct sockaddr_in *sockaddr_in = (struct sockaddr_in *) sockaddr;
		    struct in_addr *in_addr = &sockaddr_in->sin_addr;
		    NSString *thisIPAddress
			= [NSString stringWithFormat: @"%i.%i.%i.%i",
				    (ntohl(in_addr->s_addr) >> 24) & 0xFF,
				    (ntohl(in_addr->s_addr) >> 16) & 0xFF,
				    (ntohl(in_addr->s_addr) >> 8) & 0xFF,
				    (ntohl(in_addr->s_addr) >> 0) & 0xFF];
		    if(!ipAddress)
			ipAddress = thisIPAddress;
		    else
			ipAddress = [NSString stringWithFormat: @"%@ %@",
					      ipAddress,
					      thisIPAddress];
		}
	    }
	}
	
	if(longMode) {
	    printf("%s", [friendlyName UTF8String]);
	    if(ipAddresses) {
		if(ipAddress)
		    printf(" %s", [ipAddress UTF8String]);
		else
		    printf(" <no address>");
	    }
	    printf("\n");
	} else {
	    printf("%s", [friendlyName UTF8String]);
	    if(ipAddresses) {
		if(ipAddress)
		    printf(" %s", [ipAddress UTF8String]);
		else
		    printf(" <no address>");
		if(outputNames)
		    printf("\n");
	    }
	}
	
	if(outputNames) {
	    BOOL first = TRUE;
	    for(NSNetService *service in serviceGroup) {
		if(!longMode && ipAddresses && first)
		    printf(" ");
		first = FALSE;
	    
		NSString *typeName = [service type];
	    
		NSString *abbreviatedName = nil;
		{
		    NSUInteger start = 0;
		    if([typeName characterAtIndex: 0] == '_')
			start++;
		
		    NSUInteger end = [typeName length];
		    if([typeName length] > 6 &&
		       ([[typeName substringFromIndex: [typeName length] - 6]
			    isEqualToString: @"._tcp."] ||
			[[typeName substringFromIndex: [typeName length] - 6]
			    isEqualToString: @"._udp."]))
			end -= 6;
		
		    abbreviatedName
			= [typeName substringWithRange: NSMakeRange(start, end-start)];
		}

		NSString *shortName = nil;
		if(lowLevelNames)
		    shortName = typeName;
		else
		    shortName = abbreviatedName;
	    
		NSString *longName = nil;
		for(int i = 0; nameTable[i*2]; i++) {
		    if([abbreviatedName isEqualToString: nameTable[i*2]]) {
			longName = nameTable[i*2+1];
			break;
		    }
		}
		if(!longName)
		    longName = typeName;
	    
		if(longMode)
		    printf("  %s\n", [longName UTF8String]);
		else
		    printf(" %s", [shortName UTF8String]);
	    }
	}
	if(!longMode)
	    printf("\n");
    }
}


NSString *nameTable[] = {
    @"1password",
    @"1Password Password Manager data sharing and synchronization protocol",
    @"abi-instrument",
    @"Applied Biosystems Universal Instrument Framework",
    @"accessdata-f2d",
    @"FTK2 Database Discovery Service",
    @"accessdata-f2w",
    @"FTK2 Backend Processing Agent Service",
    @"accessone",
    @"Strix Systems 5S/AccessOne protocol",
    @"accountedge",
    @"MYOB AccountEdge",
    @"acrobatsrv",
    @"Adobe Acrobat",
    @"actionitems",
    @"ActionItems",
    @"activeraid",
    @"Active Storage Proprietary Device Management Protocol",
    @"activeraid-ssl",
    @"Encrypted transport of Active Storage Proprietary Device Management Protocol",
    @"addressbook",
    @"Address-O-Matic",
    @"adobe-vc",
    @"Adobe Version Cue",
    @"adisk",
    @"Automatic Disk Discovery",
    @"adpro-setup",
    @"ADPRO Security Device Setup",
    @"aecoretech",
    @"Apple Application Engineering Services",
    @"aeroflex",
    @"Aeroflex instrumentation and software",
    @"afpovertcp",
    @"Apple File Sharing",
    @"airport",
    @"AirPort Base Station",
    @"airprojector",
    @"AirProjector",
    @"airsharing",
    @"Air Sharing",
    @"airsharingpro",
    @"Air Sharing Pro",
    @"amiphd-p2p",
    @"P2PTapWar Sample Application from \"iPhone SDK Development\" Book",
    @"animolmd",
    @"Animo License Manager",
    @"animobserver",
    @"Animo Batch Server",
    @"appelezvous",
    @"Appelezvous",
    @"apple-ausend",
    @"Apple Audio Units",
    @"apple-midi",
    @"Apple MIDI",
    @"apple-sasl",
    @"Apple Password Server",
    @"applerdbg",
    @"Apple Remote Debug Services (OpenGL Profiler)",
    @"appletv",
    @"Apple TV",
    @"appletv-itunes",
    @"Apple TV discovery of iTunes",
    @"appletv-pair",
    @"Apple TV Pairing",
    @"aquamon",
    @"AquaMon",
    @"asr",
    @"Apple Software Restore",
    @"astnotify",
    @"Asterisk Caller-ID Notification Service",
    @"astralite",
    @"Astralite",
    @"async",
    @"address-o-sync",
    @"av",
    @"Allen Vanguard Hardware Service",
    @"axis-video",
    @"Axis Video Cameras",
    @"auth",
    @"Authentication Service",
    @"b3d-convince",
    @"3M Unitek Digital Orthodontic System",
    @"bdsk",
    @"BibDesk Sharing",
    @"beamer",
    @"Beamer Data Sharing Protocol",
    @"beatpack",
    @"BeatPack Synchronization Server for BeatMaker",
    @"beep",
    @"Xgrid Technology Preview",
    @"bfagent",
    @"BuildForge Agent",
    @"bigbangchess",
    @"Big Bang Chess",
    @"bigbangmancala",
    @"Big Bang Mancala",
    @"bittorrent",
    @"BitTorrent Zeroconf Peer Discovery Protocol",
    @"blackbook",
    @"Little Black Book Information Exchange Protocol",
    @"bluevertise",
    @"BlueVertise Network Protocol (BNP)",
    @"bookworm",
    @"Bookworm Client Discovery",
    @"bootps",
    @"Bootstrap Protocol Server",
    @"boundaryscan",
    @"Proprietary",
    @"bousg",
    @"Bag Of Unusual Strategy Games",
    @"bri",
    @"RFID Reader Basic Reader Interface",
    @"bsqdea",
    @"Backup Simplicity",
    @"busycal",
    @"BusySync Calendar Synchronization Protocol",
    @"caltalk",
    @"CalTalk",
    @"cardsend",
    @"Card Send Protocol",
    @"cheat",
    @"The Cheat",
    @"chess",
    @"Project Gridlock",
    @"chfts",
    @"Fluid Theme Server",
    @"chili",
    @"The CHILI Radiology System",
    @"clipboard",
    @"Clipboard Sharing",
    @"clique",
    @"Clique Link-Local Multicast Chat Room",
    @"clscts",
    @"Oracle CLS Cluster Topology Service",
    @"collection",
    @"Published Collection Object",
    @"contactserver",
    @"Now Contact",
    @"corroboree",
    @"Corroboree Server",
    @"cpnotebook2",
    @"NoteBook 2",
    @"cvspserver",
    @"CVS PServer",
    @"cw-codetap",
    @"CodeWarrior HTI Xscale PowerTAP",
    @"cw-dpitap",
    @"CodeWarrior HTI DPI PowerTAP",
    @"cw-oncetap",
    @"CodeWarrior HTI OnCE PowerTAP",
    @"cw-powertap",
    @"CodeWarrior HTI COP PowerTAP",
    @"cytv",
    @"CyTV",
    @"daap",
    @"Digital Audio Access Protocol (iTunes)",
    @"dacp",
    @"Digital Audio Control Protocol (iTunes)",
    @"device-info",
    @"Device Info",
    @"difi",
    @"EyeHome",
    @"distcc",
    @"Distributed Compiler",
    @"ditrios",
    @"Ditrios SOA Framework Protocol",
    @"divelogsync",
    @"Dive Log Data Sharing and Synchronization Protocol",
    @"dltimesync",
    @"Local Area Dynamic Time Synchronisation Protocol",
    @"dns-llq",
    @"DNS Long-Lived Queries",
    @"dns-sd",
    @"DNS Service Discovery",
    @"dns-update",
    @"DNS Dynamic Update Service",
    @"domain",
    @"Domain Name Server",
    @"dossier",
    @"Vortimac Dossier Protocol",
    @"dpap",
    @"Digital Photo Access Protocol (iPhoto)",
    @"dropcopy",
    @"DropCopy",
    @"dsl-sync",
    @"Data Synchronization Protocol for Discovery Software products",
    @"dtrmtdesktop",
    @"Desktop Transporter Remote Desktop Protocol",
    @"dvbservdsc",
    @"DVB Service Discovery",
    @"dxtgsync",
    @"Documents To Go Desktop Sync Protocol",
    @"earphoria",
    @"Earphoria",
    @"ebms",
    @"ebXML Messaging",
    @"ecms",
    @"Northrup Grumman/Mission Systems/ESL Data Flow Protocol",
    @"ebreg",
    @"ebXML Registry",
    @"ecbyesfsgksc",
    @"Net Monitor Anti-Piracy Service",
    @"edcp",
    @"LaCie Ethernet Disk Configuration Protocol",
    @"eheap",
    @"Interactive Room Software Infrastructure (Event Sharing)",
    @"embrace",
    @"DataEnvoy",
    @"eppc",
    @"Remote AppleEvents",
    @"esp",
    @"Extensis Server Protocol",
    @"eventserver",
    @"Now Up-to-Date",
    @"ewalletsync",
    @"Synchronization Protocol for Ilium Software's eWallet",
    @"example",
    @"Example Service Type",
    @"exb",
    @"Exbiblio Cascading Service Protocol",
    @"exec",
    @"Remote Process Execution",
    @"extensissn",
    @"Extensis Serial Number",
    @"eyetvsn",
    @"EyeTV Sharing",
    @"facespan",
    @"FaceSpan",
    @"fairview",
    @"Fairview Device Identification",
    @"faxstfx",
    @"FAXstf",
    @"feed-sharing",
    @"NetNewsWire 2.0",
    @"fish",
    @"Fish",
    @"fix",
    @"Financial Information Exchange (FIX) Protocol",
    @"fjork",
    @"Fjork",
    @"fl-purr",
    @"FilmLight Cluster Power Control Service",
    @"fmpro-internal",
    @"FileMaker Pro",
    @"fmserver-admin",
    @"FileMaker Server Administration Communication Service",
    @"fontagentnode",
    @"FontAgent Pro",
    @"foxtrot-serv",
    @"FoxTrot Search Server Discovery Service",
    @"foxtrot-start",
    @"FoxTrot Professional Search Discovery Service",
    @"freehand",
    @"FreeHand MusicPad Pro Interface Protocol",
    @"ftp",
    @"File Transfer",
    @"ftpcroco",
    @"Crocodile FTP Server",
    @"fv-cert",
    @"Fairview Certificate",
    @"fv-key",
    @"Fairview Key",
    @"fv-time",
    @"Fairview Time/Date",
    @"frog",
    @"Frog Navigation Systems",
    @"gbs-smp",
    @"SnapMail",
    @"gbs-stp",
    @"SnapTalk",
    @"gforce-ssmp",
    @"G-Force Control via SoundSpectrum's SSMP TCP Protocol",
    @"glasspad",
    @"GlassPad Data Exchange Protocol",
    @"glasspadserver",
    @"GlassPadServer Data Exchange Protocol",
    @"glrdrvmon",
    @"OpenGL Driver Monitor",
    @"gpnp",
    @"Grid Plug and Play",
    @"grillezvous",
    @"Roxio ToastAnywhere(tm) Recorder Sharing",
    @"growl",
    @"Growl",
    @"guid",
    @"Special service type for resolving by GUID (Globally Unique Identifier)",
    @"h323",
    @"H.323 Real-time audio, video and data communication call setup protocol",
    @"helix",
    @"MultiUser Helix Server",
    @"help",
    @"HELP command",
    @"hg",
    @"Mercurial web-based repository access",
    @"hmcp",
    @"Home Media Control Protocol",
    @"home-sharing",
    @"iTunes Home Sharing",
    @"htsp",
    @"Home Tv Streaming Protocol",
    @"http",
    @"World Wide Web HTML-over-HTTP",
    @"https",
    @"HTTP over SSL/TLS",
    @"homeauto",
    @"iDo Technology Home Automation Protocol",
    @"honeywell-vid",
    @"Honeywell Video Systems",
    @"hotwayd",
    @"Hotwayd",
    @"howdy",
    @"Howdy messaging and notification protocol",
    @"hpr-bldlnx",
    @"HP Remote Build System for Linux-based Systems",
    @"hpr-bldwin",
    @"HP Remote Build System for Microsoft Windows Systems",
    @"hpr-db",
    @"Identifies systems that house databases for the Remote Build System and Remote Test System",
    @"hpr-rep",
    @"HP Remote Repository for Build and Test Results",
    @"hpr-toollnx",
    @"HP Remote System that houses compilers and tools for Linux-based Systems",
    @"hpr-toolwin",
    @"HP Remote System that houses compilers and tools for Microsoft Windows Systems",
    @"hpr-tstlnx",
    @"HP Remote Test System for Linux-based Systems",
    @"hpr-tstwin",
    @"HP Remote Test System for Microsoft Windows Systems",
    @"hs-off",
    @"Hobbyist Software Off Discovery",
    @"hydra",
    @"SubEthaEdit",
    @"hyperstream",
    @"Atempo HyperStream deduplication server",
    @"iax",
    @"Inter Asterisk eXchange, ease-of-use NAT friendly open VoIP protocol",
    @"ibiz",
    @"iBiz Server",
    @"ica-networking",
    @"Image Capture Networking",
    @"ican",
    @"Northrup Grumman/TASC/ICAN Protocol",
    @"ichalkboard",
    @"iChalk",
    @"ichat",
    @"iChat 1.0",
    @"iconquer",
    @"iConquer",
    @"idata",
    @"Generic Data Acquisition and Control Protocol",
    @"idsync",
    @"SplashID Synchronization Service",
    @"ifolder",
    @"Published iFolder",
    @"ihouse",
    @"Idle Hands iHouse Protocol",
    @"ii-drills",
    @"Instant Interactive Drills",
    @"ii-konane",
    @"Instant Interactive Konane",
    @"ilynx",
    @"iLynX",
    @"imap",
    @"Internet Message Access Protocol",
    @"imidi",
    @"iMidi",
    @"inova-ontrack",
    @"Inova Solutions OnTrack Display Protocol",
    @"idcws",
    @"Intermec Device Configuration Web Services",
    @"ipbroadcaster",
    @"IP Broadcaster",
    @"ipp",
    @"IPP (Internet Printing Protocol)",
    @"ipspeaker",
    @"IP Speaker Control Protocol",
    @"irmc",
    @"Intego Remote Management Console",
    @"iscsi",
    @"Internet Small Computer Systems Interface (iSCSI)",
    @"isparx",
    @"iSparx",
    @"ispq-vc",
    @"iSpQ VideoChat",
    @"ishare",
    @"iShare",
    @"isticky",
    @"iSticky",
    @"istorm",
    @"iStorm",
    @"itsrc",
    @"iTunes Socket Remote Control",
    @"iwork",
    @"iWork Server",
    @"jcan",
    @"Northrup Grumman/TASC/JCAN Protocol",
    @"jeditx",
    @"Jedit X",
    @"jini",
    @"Jini Service Discovery",
    @"jtag",
    @"Proprietary",
    @"kerberos",
    @"Kerberos",
    @"kerberos-adm",
    @"Kerberos Administration",
    @"ktp",
    @"Kabira Transaction Platform",
    @"labyrinth",
    @"Labyrinth local multiplayer protocol",
    @"lan2p",
    @"Lan2P Peer-to-Peer Network Protocol",
    @"lapse",
    @"Gawker",
    @"lanrevagent",
    @"LANrev Agent",
    @"lanrevserver",
    @"LANrev Server",
    @"ldap",
    @"Lightweight Directory Access Protocol",
    @"lexicon",
    @"Lexicon Vocabulary Sharing",
    @"liaison",
    @"Liaison",
    @"library",
    @"Delicious Library 2 Collection Data Sharing Protocol",
    @"llrp",
    @"RFID reader Low Level Reader Protocol",
    @"llrp-secure",
    @"RFID reader Low Level Reader Protocol over SSL/TLS",
    @"lobby",
    @"Gobby",
    @"logicnode",
    @"Logic Pro Distributed Audio",
    @"login",
    @"Remote Login a la Telnet",
    @"lontalk",
    @"LonTalk over IP (ANSI 852)",
    @"lonworks",
    @"Echelon LNS Remote Client",
    @"lsys-appserver",
    @"Linksys One Application Server API",
    @"lsys-camera",
    @"Linksys One Camera API",
    @"lsys-ezcfg",
    @"LinkSys EZ Configuration",
    @"lsys-oamp",
    @"LinkSys Operations, Administration, Management, and Provisioning",
    @"lux-dtp",
    @"Lux Solis Data Transport Protocol",
    @"lxi",
    @"LXI",
    @"lyrics",
    @"iPod Lyrics Service",
    @"macfoh",
    @"MacFOH",
    @"macfoh-admin",
    @"MacFOH admin services",
    @"macfoh-audio",
    @"MacFOH audio stream",
    @"macfoh-events",
    @"MacFOH show control events",
    @"macfoh-data",
    @"MacFOH realtime data",
    @"macfoh-db",
    @"MacFOH database",
    @"macfoh-remote",
    @"MacFOH Remote",
    @"macminder",
    @"Mac Minder",
    @"maestro",
    @"Maestro Music Sharing Service",
    @"magicdice",
    @"Magic Dice Game Protocol",
    @"mandos",
    @"Mandos Password Server",
    @"mbconsumer",
    @"MediaBroker++ Consumer",
    @"mbproducer",
    @"MediaBroker++ Producer",
    @"mbserver",
    @"MediaBroker++ Server",
    @"mconnect",
    @"ClairMail Connect",
    @"mcrcp",
    @"MediaCentral",
    @"mesamis",
    @"Mes Amis",
    @"mimer",
    @"Mimer SQL Engine",
    @"mi-raysat",
    @"Mental Ray for Maya",
    @"modolansrv",
    @"modo LAN Services",
    @"moneysync",
    @"SplashMoney Synchronization Service",
    @"moneyworks",
    @"MoneyWorks Gold and MoneyWorks Datacentre network service",
    @"moodring",
    @"Bonjour Mood Ring tutorial program",
    @"mother",
    @"Mother script server protocol",
    @"mp3sushi",
    @"MP3 Sushi",
    @"mqtt",
    @"IBM MQ Telemetry Transport Broker",
    @"mslingshot",
    @"Martian SlingShot",
    @"mumble",
    @"Mumble VoIP communication protocol",
    @"mysync",
    @"MySync Protocol",
    @"mttp",
    @"MenuTunes Sharing",
    @"mxs",
    @"MatrixStore",
    @"ncbroadcast",
    @"Network Clipboard Broadcasts",
    @"ncdirect",
    @"Network Clipboard Direct Transfers",
    @"ncsyncserver",
    @"Network Clipboard Sync Server",
    @"neoriders",
    @"NeoRiders Client Discovery Protocol",
    @"net-assistant",
    @"Apple Remote Desktop",
    @"net2display",
    @"Vesa Net2Display",
    @"netrestore",
    @"NetRestore",
    @"newton-dock",
    @"Escale",
    @"nfs",
    @"Network File System - Sun Microsystems",
    @"nssocketport",
    @"DO over NSSocketPort",
    @"ntlx-arch",
    @"American Dynamics Intellex Archive Management Service",
    @"ntlx-ent",
    @"American Dynamics Intellex Enterprise Management Service",
    @"ntlx-video",
    @"American Dynamics Intellex Video Service",
    @"ntp",
    @"Network Time Protocol",
    @"ntx",
    @"Tenasys",
    @"obf",
    @"Observations Framework",
    @"objective",
    @"Means for clients to locate servers in an Objective (http://www.objective.com) instance.",
    @"oce",
    @"Oce Common Exchange Protocol",
    @"od-master",
    @"OpenDirectory Master",
    @"odabsharing",
    @"OD4Contact",
    @"odisk",
    @"Optical Disk Sharing",
    @"ofocus-conf",
    @"OmniFocus setting configuration",
    @"ofocus-sync",
    @"OmniFocus document synchronization",
    @"olpc-activity1",
    @"One Laptop per Child activity",
    @"omni-bookmark",
    @"OmniWeb",
    @"openbase",
    @"OpenBase SQL",
    @"opencu",
    @"Conferencing Protocol",
    @"oprofile",
    @"oprofile server protocol",
    @"oscit",
    @"Open Sound Control Interface Transfer",
    @"ovready",
    @"ObjectVideo OV Ready Protocol",
    @"owhttpd",
    @"OWFS (1-wire file system) web server",
    @"owserver",
    @"OWFS (1-wire file system) server",
    @"parentcontrol",
    @"Remote Parental Controls",
    @"passwordwallet",
    @"PasswordWallet Data Synchronization Protocol",
    @"pcast",
    @"Mac OS X Podcast Producer Server",
    @"p2pchat",
    @"Peer-to-Peer Chat (Sample Java Bonjour application)",
    @"parliant",
    @"PhoneValet Anywhere",
    @"pdl-datastream",
    @"Printer Page Description Language Data Stream (vendor-specific)",
    @"pgpkey-hkp",
    @"Horowitz Key Protocol (HKP)",
    @"pgpkey-https",
    @"PGP Keyserver using HTTP/1.1",
    @"pgpkey-https",
    @"PGP Keyserver using HTTPS",
    @"pgpkey-ldap",
    @"PGP Keyserver using LDAP",
    @"pgpkey-mailto",
    @"PGP Key submission using SMTP",
    @"photoparata",
    @"Photo Parata Event Photography Software",
    @"pictua",
    @"Pictua Intercommunication Protocol",
    @"piesync",
    @"pieSync Computer to Computer Synchronization",
    @"piu",
    @"Pedestal Interface Unit by RPM-PSI",
    @"poch",
    @"Parallel OperatiOn and Control Heuristic (Pooch)",
    @"pokeeye",
    @"Communication channel for \"Poke Eye\" Elgato EyeTV remote controller",
    @"pop3",
    @"Post Office Protocol - Version 3",
    @"postgresql",
    @"PostgreSQL Server",
    @"powereasy-erp",
    @"PowerEasy ERP",
    @"powereasy-pos",
    @"PowerEasy Point of Sale",
    @"pplayer-ctrl",
    @"Piano Player Remote Control",
    @"presence",
    @"Peer-to-peer messaging / Link-Local Messaging",
    @"print-caps",
    @"Retrieve a description of a device's print capabilities",
    @"printer",
    @"Spooler (more commonly known as \"LPR printing\" or \"LPD printing\")",
    @"profilemac",
    @"Profile for Mac medical practice management software",
    @"prolog",
    @"Prolog",
    @"protonet",
    @"Protonet node and service discovery protocol",
    @"psia",
    @"Physical Security Interoperability Alliance Protocol",
    @"ptnetprosrv2",
    @"PTNetPro Service",
    @"ptp",
    @"Picture Transfer Protocol",
    @"ptp-req",
    @"PTP Initiation Request Protocol",
    @"puzzle",
    @"Protocol used for puzzle games",
    @"qbox",
    @"QBox Appliance Locator",
    @"qttp",
    @"QuickTime Transfer Protocol",
    @"quinn",
    @"Quinn Game Server",
    @"rakket",
    @"Rakket Client Protocol",
    @"radiotag",
    @"RadioTAG: Event tagging for radio services",
    @"radiovis",
    @"RadioVIS: Visualisation for radio services",
    @"radioepg",
    @"RadioEPG: Electronic Programme Guide for radio services",
    @"raop",
    @"Remote Audio Output Protocol (AirTunes)",
    @"rbr",
    @"RBR Instrument Communication",
    @"rce",
    @"PowerCard",
    @"rdp",
    @"Windows Remote Desktop Protocol",
    @"realplayfavs",
    @"RealPlayer Shared Favorites",
    @"recipe",
    @"Recipe Sharing Protocol",
    @"remote",
    @"Remote Device Control Protocol",
    @"remoteburn",
    @"LaCie Remote Burn",
    @"renderpipe",
    @"ARTvps RenderDrive/PURE Renderer Protocol",
    @"rendezvouspong",
    @"RendezvousPong",
    @"resacommunity",
    @"Community Service",
    @"resol-vbus",
    @"RESOL VBus",
    @"retrospect",
    @"Retrospect backup and restore service",
    @"rfb",
    @"Remote Frame Buffer (used by VNC)",
    @"rfbc",
    @"Remote Frame Buffer Client (Used by VNC viewers in listen-mode)",
    @"rfid",
    @"RFID Reader Mach1(tm) Protocol",
    @"riousbprint",
    @"Remote I/O USB Printer Protocol",
    @"roku-rcp",
    @"Roku Control Protocol",
    @"rql",
    @"RemoteQuickLaunch",
    @"rsmp-server",
    @"Remote System Management Protocol (Server Instance)",
    @"rsync",
    @"Rsync",
    @"rtsp",
    @"Real Time Streaming Protocol",
    @"rubygems",
    @"RubyGems GemServer",
    @"safarimenu",
    @"Safari Menu",
    @"sallingbridge",
    @"Salling Clicker Sharing",
    @"sallingclicker",
    @"Salling Clicker Service",
    @"salutafugijms",
    @"Salutafugi Peer-To-Peer Java Message Service Implementation",
    @"sandvox",
    @"Sandvox",
    @"scanner",
    @"Bonjour Scanning",
    @"schick",
    @"Schick",
    @"scone",
    @"Scone",
    @"scpi-raw",
    @"IEEE 488.2 (SCPI) Socket",
    @"scpi-telnet",
    @"IEEE 488.2 (SCPI) Telnet",
    @"sdsharing",
    @"Speed Download",
    @"see",
    @"SubEthaEdit 2",
    @"seeCard",
    @"seeCard",
    @"senteo-http",
    @"Senteo Assessment Software Protocol",
    @"sentillion-vlc",
    @"Sentillion Vault System",
    @"sentillion-vlt",
    @"Sentillion Vault Systems Cluster",
    @"serendipd",
    @"serendiPd Shared Patches for Pure Data",
    @"servereye",
    @"ServerEye AgentContainer Communication Protocol",
    @"servermgr",
    @"Mac OS X Server Admin",
    @"services",
    @"DNS Service Discovery",
    @"sessionfs",
    @"Session File Sharing",
    @"sftp-ssh",
    @"Secure File Transfer Protocol over SSH",
    @"shell",
    @"like exec, but automatic authentication is performed as for login server.",
    @"shipsgm",
    @"Swift Office Ships",
    @"shipsinvit",
    @"Swift Office Ships",
    @"shoppersync",
    @"SplashShopper Synchronization Service",
    @"shoutcast",
    @"Nicecast",
    @"simusoftpong",
    @"simusoftpong iPhone game protocol",
    @"sip",
    @"Session Initiation Protocol, signalling protocol for VoIP",
    @"sipuri",
    @"Session Initiation Protocol Uniform Resource Identifier",
    @"sironaxray",
    @"Sirona Xray Protocol",
    @"skype",
    @"Skype",
    @"sleep-proxy",
    @"Sleep Proxy Server",
    @"slimcli",
    @"SliMP3 Server Command-Line Interface",
    @"slimhttp",
    @"SliMP3 Server Web Interface",
    @"smb",
    @"Server Message Block over TCP/IP",
    @"soap",
    @"Simple Object Access Protocol",
    @"sox",
    @"Simple Object eXchange",
    @"spearcat",
    @"sPearCat Host Discovery",
    @"spike",
    @"Shared Clipboard Protocol",
    @"spincrisis",
    @"Spin Crisis",
    @"spl-itunes",
    @"launchTunes",
    @"spr-itunes",
    @"netTunes",
    @"splashsync",
    @"SplashData Synchronization Service",
    @"ssh",
    @"SSH Remote Login Protocol",
    @"ssscreenshare",
    @"Screen Sharing",
    @"strateges",
    @"Strateges",
    @"sge-exec",
    @"Sun Grid Engine (Execution Host)",
    @"sge-qmaster",
    @"Sun Grid Engine (Master)",
    @"souschef",
    @"SousChef Recipe Sharing Protocol",
    @"sparql",
    @"SPARQL Protocol and RDF Query Language",
    @"stanza",
    @"Lexcycle Stanza service for discovering shared books",
    @"stickynotes",
    @"Sticky Notes",
    @"submission",
    @"Message Submission",
    @"supple",
    @"Supple Service protocol",
    @"surveillus",
    @"Surveillus Networks Discovery Protocol",
    @"svn",
    @"Subversion",
    @"swcards",
    @"Signwave Card Sharing Protocol",
    @"switcher",
    @"Wireless home control remote control protocol",
    @"swordfish",
    @"Swordfish Protocol for Input/Output",
    @"sxqdea",
    @"Synchronize! Pro X",
    @"sybase-tds",
    @"Sybase Server",
    @"syncopation",
    @"Syncopation Synchronization Protocol by Sonzea",
    @"syncqdea",
    @"Synchronize! X Plus 2.0",
    @"taccounting",
    @"Data Transmission and Synchronization",
    @"tapinoma-ecs",
    @"Tapinoma Easycontact receiver",
    @"taskcoachsync",
    @"Task Coach Two-way Synchronization Protocol for iPhone",
    @"tbricks",
    @"tbricks internal protocol",
    @"tcode",
    @"Time Code",
    @"tcu",
    @"Tracking Control Unit by RPM-PSI",
    @"teamlist",
    @"ARTIS Team Task",
    @"teleport",
    @"teleport",
    @"telnet",
    @"Telnet",
    @"tera-mp",
    @"Terascala Maintenance Protocol",
    @"tf-redeye",
    @"ThinkFlood RedEye IR bridge",
    @"tftp",
    @"Trivial File Transfer",
    @"thumbwrestling",
    @"tinkerbuilt Thumb Wrestling game",
    @"ticonnectmgr",
    @"TI Connect Manager Discovery Service",
    @"timbuktu",
    @"Timbuktu",
    @"tinavigator",
    @"TI Navigator Hub 1.0 Discovery Service",
    @"tivo-hme",
    @"TiVo Home Media Engine Protocol",
    @"tivo-music",
    @"TiVo Music Protocol",
    @"tivo-photos",
    @"TiVo Photos Protocol",
    @"tivo-remote",
    @"TiVo Remote Protocol",
    @"tivo-videos",
    @"TiVo Videos Protocol",
    @"tomboy",
    @"Tomboy",
    @"toothpicserver",
    @"ToothPics Dental Office Support Server",
    @"touch-able",
    @"iPhone and iPod touch Remote Controllable",
    @"touch-remote",
    @"iPhone and iPod touch Remote Pairing",
    @"tryst",
    @"Tryst",
    @"tt4inarow",
    @"Trivial Technology's 4 in a Row",
    @"ttcheckers",
    @"Trivial Technology's Checkers",
    @"ttp4daemon",
    @"TechTool Pro 4 Anti-Piracy Service",
    @"tunage",
    @"Tunage Media Control Service",
    @"tuneranger",
    @"TuneRanger",
    @"ubertragen",
    @"Ubertragen",
    @"uddi",
    @"Universal Description, Discovery and Integration",
    @"uddi-inq",
    @"Universal Description, Discovery and Integration Inquiry",
    @"uddi-pub",
    @"Universal Description, Discovery and Integration Publishing",
    @"uddi-sub",
    @"Universal Description, Discovery and Integration Subscription",
    @"uddi-sec",
    @"Universal Description, Discovery and Integration Security",
    @"upnp",
    @"Universal Plug and Play",
    @"uswi",
    @"Universal Switching Corporation products",
    @"utest",
    @"uTest",
    @"ve-decoder",
    @"American Dynamics VideoEdge Decoder Control Service",
    @"ve-encoder",
    @"American Dynamics VideoEdge Encoder Control Service",
    @"ve-recorder",
    @"American Dynamics VideoEdge Recorder Control Service",
    @"visel",
    @"visel Q-System services",
    @"volley",
    @"Volley",
    @"vos",
    @"Virtual Object System (using VOP/TCP)",
    @"vue4rendercow",
    @"VueProRenderCow",
    @"vxi-11",
    @"VXI-11 TCP/IP Instrument Protocol",
    @"webdav",
    @"World Wide Web Distributed Authoring and Versioning (WebDAV)",
    @"webdavs",
    @"WebDAV over SSL/TLS",
    @"webissync",
    @"WebIS Sync Protocol",
    @"whamb",
    @"Whamb",
    @"wired",
    @"Wired Server",
    @"witap",
    @"WiTap Sample Game Protocol",
    @"witapvoice",
    @"witapvoice",
    @"wkgrpsvr",
    @"Workgroup Server Discovery",
    @"workstation",
    @"Workgroup Manager",
    @"wormhole",
    @"Roku Cascade Wormhole Protocol",
    @"workgroup",
    @"Novell collaboration workgroup",
    @"writietalkie",
    @"Writie Talkie Data Sharing",
    @"ws",
    @"Web Services",
    @"wtc-heleos",
    @"Wyatt Technology Corporation HELEOS",
    @"wtc-qels",
    @"Wyatt Technology Corporation QELS",
    @"wtc-rex",
    @"Wyatt Technology Corporation Optilab rEX",
    @"wtc-viscostar",
    @"Wyatt Technology Corporation ViscoStar",
    @"wtc-wpr",
    @"Wyatt Technology Corporation DynaPro Plate Reader",
    @"wwdcpic",
    @"PictureSharing sample code",
    @"x-plane9",
    @"x-plane9",
    @"xcodedistcc",
    @"Xcode Distributed Compiler",
    @"xgate-rmi",
    @"xGate Remote Management Interface",
    @"xgrid",
    @"Xgrid",
    @"xmms2",
    @"XMMS2 IPC Protocol",
    @"xmp",
    @"Xperientia Mobile Protocol",
    @"xmpp-client",
    @"XMPP Client Connection",
    @"xmpp-server",
    @"XMPP Server Connection",
    @"xsanclient",
    @"Xsan Client",
    @"xsanserver",
    @"Xsan Server",
    @"xsansystem",
    @"Xsan System",
    @"xserveraid",
    @"XServe Raid",
    @"xsync",
    @"Xserve RAID Synchronization",
    @"xtimelicence",
    @"xTime License",
    @"xtshapro",
    @"xTime Project",
    @"xul-http",
    @"XUL (XML User Interface Language) transported over HTTP",
    @"yakumo",
    @"Yakumo iPhone OS Device Control Protocol",
    @"bigbangbackgammon",
    @"Big Bang Backgammon",
    @"bigbangcheckers",
    @"Big Bang Checkers",
    @"clipboardsharing",
    @"ClipboardSharing",
    @"gds_db",
    @"InterBase Database Remote Protocol",
    @"netmonitorserver",
    @"Net Monitor Server",
    @"presence_olpc",
    @"OLPC Presence",
    @"pop_2_ambrosia",
    @"Pop-Pop",
    @"profCastLicense",
    @"ProfCast",
    @"WorldBook2004ST",
    @"World Book Encyclopedia",
    nil, nil
};
@end
