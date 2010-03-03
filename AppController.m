//
//  AppController.m
//  iAudioDB
//
//  Created by Mike Jewell on 27/01/2010.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import "AppController.h"


@implementation AppController

-(id)init
{
	[super init];
	
	// A max of 100 results.
	results = [[NSMutableArray alloc] initWithCapacity: 100];
	
	
	return self;
}


/**
 * Create a new database, given the selected filename.
 */
-(IBAction)newDatabase:(id)sender
{
	NSSavePanel* panel = [NSSavePanel savePanel];
	NSInteger response = [panel runModalForDirectory:NSHomeDirectory() file:@""];
	
	[results removeAllObjects];
	[tracksView reloadData];
	
	if(response == NSFileHandlingPanelOKButton)
	{
		// TODO: Refactor this into a 'tidy' method.
		// Tidy any existing references up.
		if(db)
		{
			audiodb_close(db);
		}
		
		if(dbFilename)
		{
			[dbFilename release];
			[dbName release];
			[plistFilename release];
		}
		
		// Create new db, and set flags.
		db = audiodb_create([[panel filename] cStringUsingEncoding:NSUTF8StringEncoding], 0, 0, 0);
		audiodb_l2norm(db);
		audiodb_power(db);
		
		// Store useful paths.
		dbName = [[[panel URL] relativePath] retain];
		dbFilename = [[panel filename] retain];
		plistFilename = [[NSString stringWithFormat:@"%@.plist", [dbFilename stringByDeletingPathExtension]] retain];
		
		// Create the plist file (contains mapping from filename to key).
		trackMap = [[NSMutableDictionary alloc] init];
		[trackMap writeToFile:plistFilename atomically:YES];
		
		[queryKey setStringValue:@"None Selected"];
		[self updateStatus];
	}
}

/**
 * Open an existing adb (which must have a plist)
 */
-(IBAction)openDatabase:(id)sender
{	
	NSArray *fileTypes = [NSArray arrayWithObject:@"adb"];
	NSOpenPanel* panel = [NSOpenPanel openPanel];
	NSInteger response = [panel runModalForDirectory:NSHomeDirectory() file:@"" types:fileTypes];
	if(response == NSFileHandlingPanelOKButton)
	{
		// Tidy any existing references up.
		if(db)
		{
			audiodb_close(db);
		}
		
		if(dbFilename)
		{
			[dbFilename release];
			[dbName release];
			[plistFilename release];
		}
		
		// Store useful paths.
		db = audiodb_open([[panel filename] cStringUsingEncoding:NSUTF8StringEncoding], O_RDWR);
		dbName = [[[panel URL] relativePath] retain];
		dbFilename = [[panel filename] retain];
		
		// TODO: Verify this exists!
		plistFilename = [[NSString stringWithFormat:@"%@.plist", [dbFilename stringByDeletingPathExtension]] retain];
		
		// Clear out any old results.
		[results removeAllObjects];
		[tracksView reloadData];
		
		[queryKey setStringValue:@"None Selected"];
		[self updateStatus];
		
		adb_liszt_results_t* liszt_results = audiodb_liszt(db);
		
		for(int k=0; k<liszt_results->nresults; k++)
		{
			NSMutableString *trackVal = [[NSMutableString alloc] init];
			[trackVal appendFormat:@"%s", liszt_results->entries[k].key];
		}
		
		audiodb_liszt_free_results(db, liszt_results);
		trackMap = [[[NSMutableDictionary alloc] initWithContentsOfFile:plistFilename] retain];
		NSLog(@"Size: %d", [trackMap count]);
	}
}

/**
 * Update button states and status field based on current state.
 */
-(void)updateStatus
{
	if(db)
	{
		adb_status_ptr status = (adb_status_ptr)malloc(sizeof(struct adbstatus));
		int flags;
		flags = audiodb_status(db, status);
		[statusField setStringValue: [NSString stringWithFormat:@"Database: %@ Dimensions: %d Files: %d", dbName, status->dim, status->numFiles]];
		[chooseButton setEnabled:YES];
	}
	else
	{
		[chooseButton setEnabled:NO];
		[playBothButton setEnabled:FALSE];
		[playResultButton setEnabled:FALSE];
	}
}

/**
 * Get user's import choices.
 */
-(IBAction)importAudio:(id)sender
{
	[NSApp beginSheet:importSheet modalForWindow:mainWindow modalDelegate:self didEndSelector:NULL contextInfo:nil];
	session = [NSApp beginModalSessionForWindow: importSheet];
	[NSApp runModalSession:session];
}

/**
 * Cancel the import (at configuration time).
 */
-(IBAction)cancelImport:(id)sender;
{
	[NSApp endModalSession:session];
	[importSheet orderOut:nil];
	[NSApp endSheet:importSheet];
}

/**
 * Choose the file(s) to be imported.
 * TODO: Currently handles the import process too - split this off.
 */
-(IBAction)selectFiles:(id)sender
{
	[tracksView reloadData];
	
	NSArray *fileTypes = [NSArray arrayWithObject:@"wav"];
	NSOpenPanel* panel = [NSOpenPanel openPanel];
	[panel setAllowsMultipleSelection:TRUE];
	NSInteger response = [panel runModalForDirectory:NSHomeDirectory() file:@"" types:fileTypes];
	if(response == NSFileHandlingPanelOKButton)
	{
		NSRect newFrame;
		
		[extractingBox setHidden:FALSE];
		newFrame.origin.x = [importSheet frame].origin.x;
		newFrame.origin.y = [importSheet frame].origin.y - [extractingBox frame].size.height;
		newFrame.size.width = [importSheet frame].size.width;
		newFrame.size.height = [importSheet frame].size.height + [extractingBox frame].size.height;
		
		[indicator startAnimation:self];
		[importSheet setFrame:newFrame display:YES animate:YES];
		
		NSArray *filesToOpen = [panel filenames];
		
		NSLog(@"Begin import");
		
		// Work out which extractor to use
		NSString* extractor = @"chromagram";
		switch([extractorOptions selectedTag])
		{
			case 0:
				extractor = @"mfcc";
				break;
			case 1:
				extractor = @"chromagram";
				break;
		}
		
		for(int i=0; i<[filesToOpen count]; i++)
		{
			// First extract powers
			
			NSString *tempFileTemplate = [NSTemporaryDirectory() stringByAppendingPathComponent:@"powers.XXXXXX"];
			const char *tempFileTemplateCString = [tempFileTemplate fileSystemRepresentation];
			char *tempFileNameCString = (char *)malloc(strlen(tempFileTemplateCString) + 1);
			strcpy(tempFileNameCString, tempFileTemplateCString);
			mktemp(tempFileNameCString);
			
			NSString* powersFileName = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:tempFileNameCString length:strlen(tempFileNameCString)];
			free(tempFileNameCString);
			
			NSTask *task = [[NSTask alloc] init];
			[task setLaunchPath:@"/usr/local/bin/fftExtract2"];
			NSArray *args = [NSArray arrayWithObjects:@"-P", @"-h", @"11025", @"-w", @"16384", @"-n", @"32768", @"-i", @"1000", [filesToOpen objectAtIndex:i], powersFileName, nil];
			[task setArguments:args];
			[task launch];
			[task waitUntilExit];
			[task release];
			
			// Then features
			
			tempFileTemplate = [NSTemporaryDirectory() stringByAppendingPathComponent:@"features.XXXXXX"];
			tempFileTemplateCString = [tempFileTemplate fileSystemRepresentation];
			tempFileNameCString = (char *)malloc(strlen(tempFileTemplateCString) + 1);
			strcpy(tempFileNameCString, tempFileTemplateCString);
			mktemp(tempFileNameCString);

			NSString* featuresFileName = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:tempFileNameCString length:strlen(tempFileNameCString)];
			free(tempFileNameCString);
			
			task = [[NSTask alloc] init];
			
			[task setLaunchPath:@"/usr/local/bin/fftExtract2"];
			
			NSArray *args2;
			
			// Choose the args (TODO: This should use sonic annotator eventually)
			if([extractor isEqualToString:@"chromagram"])
			{
				args2 = [NSArray arrayWithObjects:@"-p",@"/Users/moj/planfile",@"-c", @"36", @"-h", @"11025", @"-w", @"16384", @"-n", @"32768", @"-i", @"1000", [filesToOpen objectAtIndex:i], featuresFileName, nil];
			}
			else
			{
				args2 = [NSArray arrayWithObjects:@"-p",@"/Users/moj/planfile",@"-m", @"13", @"-h", @"11025", @"-w", @"16384", @"-n ", @"32768", @"-i", @"1000", [filesToOpen objectAtIndex:i], featuresFileName, nil];
			}
			[task setArguments:args2];
			[task launch];
			[task waitUntilExit];
			[task release];
			
			NSString* val = [[filesToOpen objectAtIndex:i] retain];
			NSString* key = [[[filesToOpen objectAtIndex:i] lastPathComponent] retain]; 
			
			adb_insert_t insert;
			insert.features = [featuresFileName cStringUsingEncoding:NSUTF8StringEncoding];
			insert.power = [powersFileName cStringUsingEncoding:NSUTF8StringEncoding];
			insert.times = NULL;
			insert.key = [key cStringUsingEncoding:NSUTF8StringEncoding];
			
			// Insert into db.
			if(audiodb_insert(db, &insert))
			{
				// TODO: Show an error message.
				NSLog(@"Weep: %@ %@ %@", featuresFileName, powersFileName, key);
				continue;
			}
			
			// Update the plist store.
			[trackMap setValue:val forKey:key];
			[trackMap writeToFile:plistFilename atomically: YES];
			
			[self updateStatus];
		}
		
		newFrame.origin.x = [importSheet frame].origin.x;
		newFrame.origin.y = [importSheet frame].origin.y + [extractingBox frame].size.height;
		newFrame.size.width = [importSheet frame].size.width;
		newFrame.size.height = [importSheet frame].size.height - [extractingBox frame].size.height;
		
		[importSheet setFrame:newFrame display:YES animate:YES];
		
		[NSApp endModalSession:session];
		[importSheet orderOut:nil];
		[NSApp endSheet:importSheet];
		[indicator stopAnimation:self];
		[extractingBox setHidden:TRUE];
	}
}

/**
 * Required table methods begin here.
 */
-(int)numberOfRowsInTableView:(NSTableView *)v
{
	return [results count];
}

/**
 * Return appropriate values - or the distance indicator if it's the meter column.
 */
-(id)tableView:(NSTableView *)v objectValueForTableColumn:(NSTableColumn *)tc row:(NSInteger)row
{
	id result = [results objectAtIndex:row];
	id value = [result objectForKey:[tc identifier]];
	
	if([[tc identifier] isEqualToString:@"meter"])
	{
		NSLevelIndicatorCell *distance = [[NSLevelIndicatorCell alloc] initWithLevelIndicatorStyle:NSRelevancyLevelIndicatorStyle];
		[distance setFloatValue:10-[(NSNumber*)value floatValue]*100];
		return distance;
	}
	else
	{
		return value;
	}
}

/**
 * Handle column sorting.
 */
- (void)tableView:(NSTableView *)v sortDescriptorsDidChange:(NSArray *)oldDescriptors
{
    [results sortUsingDescriptors:[v sortDescriptors]];
    [v reloadData];
}

/**
 * Only enable the import menu option if a database is loaded.
 */
- (BOOL)validateUserInterfaceItem:(id <NSValidatedUserInterfaceItem>)anItem
{
	SEL theAction = [anItem action];
	if (theAction == @selector(importAudio:))
	{
		if(!db)
		{
			return NO;
		}
	}
	return YES;
}

/**
 * Ensure play buttons are only enabled if a track is selected.
 */
-(IBAction)selectedChanged:(id)sender
{
	if([tracksView numberOfSelectedRows] == 0)
	{
		[playBothButton setEnabled:FALSE];
		[playResultButton setEnabled:FALSE];
	}
	else
	{
		[playBothButton setEnabled:TRUE];
		[playResultButton setEnabled:TRUE];
	}
}

/**
 * Play just the result track.
 */
-(IBAction)playResult:(id)sender
{

	NSDictionary* selectedRow = [results objectAtIndex:[tracksView selectedRow]];
	NSString* value = [selectedRow objectForKey:@"key"];
	float ipos = [[selectedRow objectForKey:@"ipos"] floatValue];
	NSString* filename = [trackMap objectForKey:value];
	NSLog(@"Key: %@ Value: %@", value, filename);
	
	if(queryTrack)
	{
		if([queryTrack isPlaying])
		{
			[queryTrack setDelegate:Nil];
			[queryTrack stop];
		}
		[queryTrack release];
	}
	
	if(resultTrack)
	{
		if([resultTrack isPlaying])
		{
			[resultTrack setDelegate:Nil];
			[resultTrack stop];
		}
		[resultTrack release];
	}
	
	resultTrack = [[[NSSound alloc] initWithContentsOfFile:filename byReference:YES] retain];
	[resultTrack setCurrentTime:ipos];
	[resultTrack setDelegate:self];
	[resultTrack play];
	
	[stopButton setEnabled:YES];
}

/**
 * Play the result and query simultaneously.
 */
-(IBAction)playBoth:(id)sender
{
	
	NSDictionary* selectedRow = [results objectAtIndex:[tracksView selectedRow]];
	NSString* value = [selectedRow objectForKey:@"key"];
	float ipos = [[selectedRow objectForKey:@"ipos"] floatValue];
	float qpos = [[selectedRow objectForKey:@"qpos"] floatValue];
	NSString* filename = [trackMap objectForKey:value];
	NSLog(@"Key: %@ Value: %@", value, filename);
		
	if(queryTrack)
	{
		
		if([queryTrack isPlaying])
		{
			[queryTrack setDelegate:Nil];
			[queryTrack stop];
		}
		[queryTrack release];
	}
	if(resultTrack)
	{
		if([resultTrack isPlaying])
		{
			[resultTrack setDelegate:Nil];
			[resultTrack stop];
		}
		[resultTrack release];
	}
	
	// Get query track and shift to start point
	queryTrack = [[[NSSound alloc] initWithContentsOfFile:selectedFilename byReference:YES] retain];
	[queryTrack setCurrentTime:qpos];
	[queryTrack setDelegate:self];
	
	[queryTrack play];
	
	resultTrack = [[[NSSound alloc] initWithContentsOfFile:filename byReference:YES] retain];
	[resultTrack setCurrentTime:ipos];
	[resultTrack setDelegate:self];
	[resultTrack play];
	
	[stopButton setEnabled:YES];
}

/**
 * Disable the stop button after playback of both tracks.
 */
- (void)sound:(NSSound *)sound didFinishPlaying:(BOOL)playbackSuccessful
{
	
	if((queryTrack && [queryTrack isPlaying]) || (resultTrack && [resultTrack isPlaying]))
	{
		return;
	}
	else
	{
		[stopButton setEnabled:NO];
	}
}

/**
 * Stop playback.
 */
-(IBAction)stopPlay:(id)sender
{
	if(queryTrack)
	{
		[queryTrack stop];
	}
	if(resultTrack)
	{
		[resultTrack stop];
	}
}

/**
 * Select an audio file, determine the key, and fire off a query.
 */
-(IBAction)chooseQuery:(id)sender
{
	NSArray* fileTypes = [NSArray arrayWithObject:@"wav"];
	NSOpenPanel* panel = [NSOpenPanel openPanel];
	NSInteger response = [panel runModalForDirectory:NSHomeDirectory() file:@"" types:fileTypes];
	if(response == NSFileHandlingPanelOKButton)
	{
		NSLog(@"%@", [panel filename]);
		// Grab key
		NSArray* opts = [trackMap allKeysForObject:[panel filename]];
		if([opts count] != 1)
		{
			NSAlert *alert = [[[NSAlert alloc] init] autorelease];
			[alert addButtonWithTitle:@"OK"];
			[alert setMessageText:@"Track not found"];
			[alert setInformativeText:@"Make sure you have specified a valid track identifier."];
			[alert setAlertStyle:NSWarningAlertStyle];
			[alert beginSheetModalForWindow:mainWindow modalDelegate:self didEndSelector:NULL contextInfo:nil];
		}
		else
		{
			selectedKey = [opts objectAtIndex:0];
			[queryKey setStringValue:selectedKey];
			selectedFilename = [[panel filename] retain];
			[self performQuery];
		}
	}
}

/**
 * Actually perform the query. TODO: Monolithic.
 */
-(void)performQuery
{
	NSLog(@"Perform query! %@, %@", selectedKey, selectedFilename);
	
	adb_query_spec_t *spec = (adb_query_spec_t *)malloc(sizeof(adb_query_spec_t));
	spec->qid.datum = (adb_datum_t *)malloc(sizeof(adb_datum_t));
	
	spec->qid.sequence_length = 20;
	spec->qid.sequence_start = 0;
	spec->qid.flags = 0;
	
//	spec->qid.flags = spec->qid.flags | ADB_QID_FLAG_EXHAUSTIVE;
	spec->params.accumulation = ADB_ACCUMULATION_PER_TRACK;
	spec->params.distance = ADB_DISTANCE_EUCLIDEAN_NORMED;
	
	spec->params.npoints = 1;
	spec->params.ntracks = 100;
	//spec->refine.radius = 5.0;
	spec->refine.hopsize = 1;
//	spec->refine.absolute_threshold = -6;
//	spec->refine.relative_threshold = 10;
//	spec->refine.duration_ratio = 0;
	
	spec->refine.flags = 0;
//	spec->refine.flags |= ADB_REFINE_ABSOLUTE_THRESHOLD;
//	spec->refine.flags |= ADB_REFINE_RELATIVE_THRESHOLD;
	spec->refine.flags |= ADB_REFINE_HOP_SIZE;
	//spec->refine.flags |= ADB_REFINE_RADIUS;

	adb_query_results_t *result = (adb_query_results_t *)malloc(sizeof(adb_query_results_t));
	spec->qid.datum->data = NULL;
	spec->qid.datum->power = NULL;
	spec->qid.datum->times = NULL;
	
	[results removeAllObjects];
	
	int ok = audiodb_retrieve_datum(db, [selectedKey cStringUsingEncoding:NSUTF8StringEncoding], spec->qid.datum);
	if(ok == 0)
	{
		NSLog(@"Got a datum");
		result = audiodb_query_spec(db, spec);
		if(result == NULL)
		{
			
			NSLog(@"No results");
		}
		else
		{
			for(int i=0; i<result->nresults; i++)
			{
				NSMutableDictionary* dict = [[NSMutableDictionary alloc] initWithCapacity:4];
				[dict setValue:[NSString stringWithFormat:@"%s", result->results[i].key] forKey:@"key"];
				[dict setValue:[NSNumber numberWithFloat:result->results[i].dist] forKey:@"distance"];
				[dict setValue:[NSNumber numberWithFloat:result->results[i].dist] forKey:@"meter"];
				[dict setValue:[NSNumber numberWithFloat:result->results[i].qpos/4] forKey:@"qpos"];
				[dict setValue:[NSNumber numberWithFloat:result->results[i].ipos/4] forKey:@"ipos"];
				NSLog(@"%s qpos %d ipos %d", result->results[i].key, result->results[i].qpos/4, result->results[i].ipos/4);
				[results addObject: dict];
			}
		}
		
		NSSortDescriptor *distSort = [[NSSortDescriptor alloc]initWithKey:@"meter"  ascending:YES];
		NSArray *distDescs = [NSArray arrayWithObject:distSort];
		
		[results sortUsingDescriptors:distDescs];
		[tracksView setSortDescriptors:distDescs];
		[tracksView reloadData];
		
	}
	else
	{		
		NSAlert *alert = [[[NSAlert alloc] init] autorelease];
		[alert addButtonWithTitle:@"OK"];
		[alert setMessageText:@"Track not found"];
		[alert setInformativeText:@"Make sure you have specified a valid track identifier."];
		[alert setAlertStyle:NSWarningAlertStyle];
		[alert beginSheetModalForWindow:mainWindow modalDelegate:self didEndSelector:NULL contextInfo:nil];
	}
//	audiodb_query_free_results(db, spec, result);
}

@end
