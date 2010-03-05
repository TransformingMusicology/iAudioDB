//
//  AppController.h
//  iAudioDB
//
//  Created by Mike Jewell on 27/01/2010.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#include <audioDB_API.h>


@interface AppController : NSObject {
	adb_t *db;
	NSModalSession session;
	
	NSString* dbName;
	NSString* dbFilename;
	NSString* plistFilename;
	NSString* selectedKey;
	NSString* selectedFilename;
	
	IBOutlet NSTextField *statusField;
	IBOutlet NSTableView *tracksView;
	IBOutlet id mainWindow;

	// Querying
	IBOutlet NSTextField* queryKey;
	IBOutlet NSButton* playBothButton;
	IBOutlet NSButton* playResultButton;
	IBOutlet NSButton* stopButton;
	IBOutlet NSButton* chooseButton;
	
	NSMutableArray* results;
	NSDictionary* trackMap;
	
	// Extracting
	IBOutlet id importSheet;
	IBOutlet NSBox* extractingBox;
	IBOutlet NSMatrix* extractorOptions;
	IBOutlet NSProgressIndicator* indicator;
	
	// Playback
	NSSound* queryTrack;
	NSSound* resultTrack;
	
	// Query param fields
	
	/* To Come
	 IBOutlet id queryType;	
	 IBOutlet NSTextField* queryStartField;
	 IBOutlet id queryTypeOptions;
	 IBOutlet NSTextField* queryLengthField;
	 IBOutlet NSTextField* queryRadiusField;
	 IBOutlet NSButtonCell* exhaustiveField;*/
	
}

//  Menus
-(IBAction)newDatabase:(id)sender;
-(IBAction)openDatabase:(id)sender;
-(IBAction)selectFiles:(id)sender;

// Import
-(IBAction)importAudio:(id)sender;
-(IBAction)cancelImport:(id)sender;

// Buttons
-(IBAction)playBoth:(id)sender;
-(IBAction)playResult:(id)sender;
-(IBAction)stopPlay:(id)sender;
-(IBAction)chooseQuery:(id)sender;
-(IBAction)selectedChanged:(id)sender;


-(void)performQuery;
-(void)updateStatus;
- (BOOL)validateUserInterfaceItem:(id <NSValidatedUserInterfaceItem>)anItem;
- (void)sound:(NSSound *)sound didFinishPlaying:(BOOL)playbackSuccessful;

@end
