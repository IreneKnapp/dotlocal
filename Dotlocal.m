#import <Foundation/Foundation.h>
#import "BrowserDelegate.h"

int main (int argc, char *argv[]) {
    BOOL useNames = TRUE;
    BOOL useLongMode = FALSE;
    BOOL useLowLevelNames = FALSE;
    BOOL useIPAddresses = TRUE;
    BOOL outputVersion = FALSE;
    
    for(int i = 1; i < argc; i++) {
	char *arg = argv[i];
	
	if(arg[0] == '-') {
	    if(arg[1] == '-') {
		if(!strcmp(arg, "--version")) {
		    outputVersion = TRUE;
		} else if(!strcmp(arg, "--long-names")) {
		    useNames = TRUE;
		    useLongMode = TRUE;
		    useLowLevelNames = FALSE;
		} else if(!strcmp(arg, "--short-names")) {
		    useNames = TRUE;
		    useLongMode = FALSE;
		    useLowLevelNames = FALSE;
		} else if(!strcmp(arg, "--low-level-names")) {
		    useNames = TRUE;
		    useLongMode = FALSE;
		    useLowLevelNames = TRUE;
		} else if(!strcmp(arg, "--no-names")) {
		    useNames = FALSE;
		    useLongMode = FALSE;
		    useLowLevelNames = FALSE;
		} else if(!strcmp(arg, "--ip-addresses")) {
		    useIPAddresses = TRUE;
		} else if(!strcmp(arg, "--no-ip-addresses")) {
		    useIPAddresses = FALSE;
		} else goto usage;
	    } else {
		for(int j = 1; arg[j]; j++) {
		    switch(arg[j]) {
		    case 'v':
			outputVersion = TRUE;
			break;
		    case 'l':
			useLongMode = TRUE;
			useLowLevelNames = FALSE;
			break;
		    case 's':
			useLongMode = FALSE;
			useLowLevelNames = FALSE;
			break;
		    case 'L':
			useLongMode = FALSE;
			useLowLevelNames = TRUE;
			break;
		    case 'n':
			useNames = FALSE;
			useLongMode = FALSE;
			useLowLevelNames = FALSE;
			break;
		    case 'i':
			useIPAddresses = TRUE;
			break;
		    case 'j':
			useIPAddresses = FALSE;
			break;
		    default:
			goto usage;
		    }
		}
	    }
	} else {
	    goto usage;
	}
    }

    if(outputVersion) {
	printf("local 1.0\n");
	return 0;
    }
    
    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
    
    BrowserDelegate *delegate = [[BrowserDelegate alloc] initNames: useNames
							 longMode: useLongMode
							 lowLevelNames: useLowLevelNames
							 ipAddresses: useIPAddresses];
    
    NSRunLoop *runLoop = [NSRunLoop mainRunLoop];
    while(![delegate isDone] &&
	  [runLoop runMode: NSDefaultRunLoopMode
		   beforeDate: [NSDate distantFuture]]) {
	[pool drain];
	pool = [[NSAutoreleasePool alloc] init];
    }
    
    [pool drain];
    return 0;

 usage:
    printf("Usage:\n"
	   "local [-l|--long-names] [-s|--short-names] [-L|--low-level-names]\n"
	   "      [-n|--no-names] [-i|--ip-addresses] [-j|--no-ip-addresses]\n"
	   "local [-v|--version]\n");
    return 1;
}
