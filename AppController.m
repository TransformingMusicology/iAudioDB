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

- (void)awakeFromNib {
	[tracksView setTarget:self];
	[tracksView setDoubleAction:@selector(tableDoubleClick:)];
	[self updateStatus];
}


- (IBAction)tableDoubleClick:(id)sender
{
	[self playResult:Nil];
//	NSLog(@"Table double clicked");
}
	

/**
 * Create a new database, given the selected filename.
 */
-(IBAction)newDatabase:(id)sender
{
	
	[NSApp beginSheet:createSheet modalForWindow:mainWindow modalDelegate:self didEndSelector:NULL contextInfo:nil];
	session = [NSApp beginModalSessionForWindow:createSheet];
	[NSApp runModalSession:session];	
}

/**
 * Cancel the db creation (at configuration time).
 */
-(IBAction)cancelCreate:(id)sender
{
	[NSApp endModalSession:session];
	[createSheet orderOut:nil];
	[NSApp endSheet:createSheet];
}

-(IBAction)createDatabase:(id)sender
{
	[self cancelCreate:self];
	
	NSSavePanel* panel = [NSSavePanel savePanel];
	NSInteger response = [panel runModalForDirectory:NSHomeDirectory() file:@""];
	 
	[results removeAllObjects];
	[tracksView reloadData];
	 
	if(response == NSFileHandlingPanelOKButton)
	{
		// Work out which extractor to use
		NSString* extractor = @"adb_chroma";
		// TODO: This should be stored with the n3.
		int dim;
		switch([extractorOptions selectedTag])
		{
			case 0:
				extractor = @"adb_chroma";
				dim = 12;
				break;
			case 1:
				extractor = @"adb_cq";
				dim = 48;
				break;
			case 2:
				extractor = @"qm_chroma";
				dim = 12;
				break;
			case 3:
				extractor = @"qm_mfcc";
				dim = 12;
				break;
		}
		
		// Calculate the max DB size
		int vectors = ceil(([maxLengthField doubleValue] * 60.0f) / ([hopSizeField doubleValue] / 44100.0f));
		int numtracks = [maxTracksField intValue];
		int datasize = ceil((numtracks * vectors * dim * 8.0f) / 1024.0f / 1024.0f); // In MB
		
		[self reset];
		 
		// Create new db, and set flags.
		db = audiodb_create([[panel filename] cStringUsingEncoding:NSUTF8StringEncoding], datasize, numtracks, dim);
		audiodb_l2norm(db);
			 
		// Store useful paths.
		dbName = [[[panel URL] relativePath] retain];
		dbFilename = [[panel filename] retain];
		plistFilename = [[NSString stringWithFormat:@"%@.plist", [dbFilename stringByDeletingPathExtension]] retain];
			
		// Create the plist file (contains mapping from filename to key).
		dbState = [[NSMutableDictionary alloc] init];
		trackMap = [[NSMutableDictionary alloc] init];
		[dbState setValue:trackMap forKey:@"tracks"];
		[dbState setValue:extractor forKey:@"extractor"];
		[dbState setValue:[hopSizeField stringValue] forKey:@"hopsize"];
		[dbState writeToFile:plistFilename atomically:YES];
			 
		[queryKey setStringValue:@"None Selected"];
		[self updateStatus];
	}
}

-(void)reset
{
	// Tidy any existing references up.
	if(db)
	{
		NSLog(@"Close db");
		audiodb_close(db);
	}
	
	if(dbFilename)
	{
		NSLog(@"Tidy up filenames");
		[dbFilename release];
		[dbName release];
		[plistFilename release];
		[trackMap release];
		[dbState release];
	}
	
	if(selectedKey)
	{
		[selectedKey release];
		selectedKey = Nil;
	}
	
	// Reset query flags
	[queryPath setStringValue: @"No file selected"];
	[queryLengthSeconds setDoubleValue:0];
	[queryLengthVectors setDoubleValue:0];
	[multipleCheckBox setState:NSOnState];
	[queryStartSeconds setDoubleValue:0];
	[queryStartVectors setDoubleValue:0];
	
	[queryLengthSeconds setEnabled:NO];
	[queryLengthVectors setEnabled:NO];
	[queryStartSeconds setEnabled:NO];
	[queryStartVectors setEnabled:NO];
	[resetButton setEnabled:NO];
	[multipleCheckBox setEnabled:NO];
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
		[self reset];
		
		// Store useful paths.
		NSLog(@"Open");
		db = audiodb_open([[panel filename] cStringUsingEncoding:NSUTF8StringEncoding], O_RDONLY);
		dbName = [[[panel URL] relativePath] retain];
		dbFilename = [[panel filename] retain];
		
		// TODO: Verify this exists!
		plistFilename = [[NSString stringWithFormat:@"%@.plist", [dbFilename stringByDeletingPathExtension]] retain];
		
		// Clear out any old results.
		[results removeAllObjects];
		[tracksView reloadData];
		
		[queryKey setStringValue:@"None Selected"];
		
		adb_liszt_results_t* liszt_results = audiodb_liszt(db);
		
		for(int k=0; k<liszt_results->nresults; k++)
		{
			NSMutableString *trackVal = [[NSMutableString alloc] init];
			[trackVal appendFormat:@"%s", liszt_results->entries[k].key];
		}
		
		audiodb_liszt_free_results(db, liszt_results);
		dbState = [[[NSMutableDictionary alloc] initWithContentsOfFile:plistFilename] retain];
		trackMap = [[dbState objectForKey:@"tracks"] retain];
		
		[self updateStatus];
		
		NSLog(@"Size: %d", [trackMap count]);
	}
}

-(IBAction)pathAction:(id)sender
{
	NSLog(@"Path action");
}

/**
 * Update button states and status field based on current state.
 */
-(void)updateStatus
{
	NSLog(@"Update status");
	if(db)
	{
		NSLog(@"Got a db");
		adb_status_t *status = (adb_status_t *)malloc(sizeof(adb_status_t));
		int flags;
		flags = audiodb_status(db, status);
		[statusField setStringValue: [NSString stringWithFormat:@"%@ Dim: %d Files: %d Hop: %@ Ext: %@", 
									  dbName, 
									  status->dim, 
									  status->numFiles, 
									  [dbState objectForKey:@"hopsize"],
									  [dbState objectForKey:@"extractor"]]];
		[performQueryButton setEnabled:YES];
		[importAudioButton setEnabled:YES];
	}
	else
	{
		NSLog(@"No db");
		[performQueryButton setEnabled:NO];
		[importAudioButton setEnabled:NO];
		[playBothButton setEnabled:NO];
		[playResultButton setEnabled:NO];
		[stopButton setEnabled:NO];
	}
}

-(void)importFile:(NSString *)filename withExtractorConfig:(NSString *)extractorPath
{
	// Create the extractor configuration
	
	NSString* extractorContent = [NSString stringWithContentsOfFile:extractorPath];
	NSString* hopStr = [dbState objectForKey:@"hopsize"];
	NSString* newContent = [[extractorContent stringByReplacingOccurrencesOfString:@"HOP_SIZE" withString:hopStr] 
							stringByReplacingOccurrencesOfString:@"WINDOW_SIZE" withString:[NSString stringWithFormat:@"%d", [hopStr intValue] * 8]];
	NSString* n3FileName = [NSTemporaryDirectory() stringByAppendingPathComponent:@"extractor_config.n3"];
	NSLog(extractorContent);
	NSLog(newContent);
	
	NSError* error;
	[newContent writeToFile:n3FileName atomically:YES encoding:NSASCIIStringEncoding error:&error];
	
	// Create the temp file for the extracted features
	NSString* tempFileTemplate = [NSTemporaryDirectory() stringByAppendingPathComponent:@"features.XXXXXX"];
	const char* tempFileTemplateCString = [tempFileTemplate fileSystemRepresentation];
	char* tempFileNameCString = (char *)malloc(strlen(tempFileTemplateCString) + 1);
	strcpy(tempFileNameCString, tempFileTemplateCString);
	mktemp(tempFileNameCString);
	
	NSString* featuresFileName = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:tempFileNameCString length:strlen(tempFileNameCString)];
	free(tempFileNameCString);
	
	// Extract features with sonic-annotator
	NSTask* task = [[NSTask alloc] init];
	[task setLaunchPath:@"/usr/local/bin/sonic-annotator"];
	NSArray* args;
	args = [NSArray arrayWithObjects:@"-t", n3FileName, @"-w", @"rdf", @"-r", @"--rdf-network", @"--rdf-one-file", featuresFileName, @"--rdf-force", filename, nil];
	[task setArguments:args];
	[task launch];
	[task waitUntilExit];
	[task release];
	
	// Populate the audioDB instance
	NSTask* importTask = [[NSTask alloc] init];
	[importTask setLaunchPath:@"/usr/local/bin/populate"];
	args = [NSArray arrayWithObjects:featuresFileName, dbFilename, nil];
	[importTask setArguments:args];
	[importTask launch];
	[importTask waitUntilExit];
	[importTask release];
	
	NSString* val = [filename retain];
	NSString* key = [[filename lastPathComponent] retain]; 
	
	// Update the plist store.
	[trackMap setValue:val forKey:key];
	[dbState writeToFile:plistFilename atomically: YES];
	
}

/**
 * Choose the file(s) to be imported.
 * TODO: Currently handles the import process too - split this off.
 */
-(IBAction)importAudio:(id)sender
{
	[tracksView reloadData];
	
	NSArray *fileTypes = [NSArray arrayWithObject:@"wav"];
	NSOpenPanel* panel = [NSOpenPanel openPanel];
	[panel setAllowsMultipleSelection:TRUE];
	NSInteger response = [panel runModalForDirectory:NSHomeDirectory() file:@"" types:fileTypes];
	if(response == NSFileHandlingPanelOKButton)
	{
		[indicator startAnimation:self];
		
		[NSApp beginSheet:importSheet modalForWindow:mainWindow modalDelegate:self didEndSelector:NULL contextInfo:nil];
		session = [NSApp beginModalSessionForWindow: importSheet];
		[NSApp runModalSession:session];
		
		NSArray *filesToOpen = [panel filenames];
		
		NSString* extractor = [dbState objectForKey:@"extractor"];
		NSString* extractorPath = [NSString stringWithFormat:@"/Applications/iAudioDB.app/rdf/%@.n3", extractor];
		
		// TODO Shift this process into a separate function.
		// Create the customized extractor config
/*		NSString* extractorContent = [NSString stringWithContentsOfFile:extractorPath];
		NSString* hopStr = [dbState objectForKey:@"hopsize"];
		NSString* winStr = [dbState objectForKey:@"windowsize"];
		NSString* newContent = [[extractorContent stringByReplacingOccurrencesOfString:@"HOP_SIZE" withString:hopStr] 
								stringByReplacingOccurrencesOfString:@"WINDOW_SIZE" withString:winStr];
		NSString* n3FileName = [NSTemporaryDirectory() stringByAppendingPathComponent:@"extractor_config.n3"];
		
		NSError* error;
		[newContent writeToFile:n3FileName atomically:YES encoding:NSASCIIStringEncoding error:&error];
*/		
		for(int i=0; i<[filesToOpen count]; i++)
		{		
			audiodb_close(db);
			
			// Get the sample rate for the audio file
			
			[self importFile:[filesToOpen objectAtIndex:i] withExtractorConfig:extractorPath];
			
	/*		NSString* tempFileTemplate = [NSTemporaryDirectory() stringByAppendingPathComponent:@"features.XXXXXX"];
			const char* tempFileTemplateCString = [tempFileTemplate fileSystemRepresentation];
			char* tempFileNameCString = (char *)malloc(strlen(tempFileTemplateCString) + 1);
			strcpy(tempFileNameCString, tempFileTemplateCString);
			mktemp(tempFileNameCString);

			NSString* featuresFileName = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:tempFileNameCString length:strlen(tempFileNameCString)];
			free(tempFileNameCString);
			
			NSTask* task = [[NSTask alloc] init];
			
			[task setLaunchPath:@"/usr/local/bin/sonic-annotator"];
			NSArray* args;
			args = [NSArray arrayWithObjects:@"-t", n3FileName, @"-w", @"rdf", @"-r", @"--rdf-network", @"--rdf-one-file", featuresFileName, @"--rdf-force", [filesToOpen objectAtIndex:i], nil];
			[task setArguments:args];
			[task launch];
			[task waitUntilExit];
			[task release];
			
			NSTask* importTask = [[NSTask alloc] init];
			[importTask setLaunchPath:@"/usr/local/bin/populate"];
			args = [NSArray arrayWithObjects:featuresFileName, dbFilename, nil];
			[importTask setArguments:args];
			[importTask launch];
			[importTask waitUntilExit];
			[importTask release];
			
			NSString* val = [[filesToOpen objectAtIndex:i] retain];
			NSString* key = [[[filesToOpen objectAtIndex:i] lastPathComponent] retain]; 
		
			// Update the plist store.
			[trackMap setValue:val forKey:key];
			[dbState writeToFile:plistFilename atomically: YES];
			*/
			
			db = audiodb_open([dbFilename cStringUsingEncoding:NSUTF8StringEncoding], O_RDONLY);
			[self updateStatus];
		}
		
		[NSApp endModalSession:session];
		[importSheet orderOut:nil];
		[NSApp endSheet:importSheet];
		[indicator stopAnimation:self];
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
		[distance setFloatValue:10.0f-[(NSNumber*)value floatValue]*100.0f];
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
		[playBothButton setEnabled:NO];
		[playResultButton setEnabled:NO];
	}
	else
	{
		[playBothButton setEnabled:YES];
		[playResultButton setEnabled:YES];
	}
}

/**
 * Play just the result track.
 */
-(IBAction)playResult:(id)sender
{

	if([tracksView selectedRow] == -1)
	{
		return;
	}
	
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
		queryTrack = Nil;
	}
	
	if(resultTrack)
	{
		if([resultTrack isPlaying])
		{
			[resultTrack setDelegate:Nil];
			[resultTrack stop];
		}
		[resultTrack release];
		resultTrack = Nil;
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
		queryTrack = Nil;
	}
	if(resultTrack)
	{
		if([resultTrack isPlaying])
		{
			[resultTrack setDelegate:Nil];
			[resultTrack stop];
		}
		[resultTrack release];
		resultTrack = Nil;
	}
	
	// Get query track and shift to start point
	queryTrack = [[[NSSound alloc] initWithContentsOfFile:selectedFilename byReference:YES] retain];
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
	[queryButton setEnabled:(selectedKey ? YES : NO)];
	[NSApp beginSheet:querySheet modalForWindow:mainWindow modalDelegate:self didEndSelector:NULL contextInfo:nil];
	session = [NSApp beginModalSessionForWindow:querySheet];
	[NSApp runModalSession:session];	
}


-(IBAction)selectQueryFile:(id)sender
{
	NSArray* fileTypes = [NSArray arrayWithObject:@"wav"];
	NSOpenPanel* panel = [NSOpenPanel openPanel];
	NSInteger response = [panel runModalForDirectory:NSHomeDirectory() file:@"" types:fileTypes];
	if(response == NSFileHandlingPanelOKButton)
	{
		NSArray* opts = [trackMap allKeysForObject:[panel filename]];
		if([opts count] != 1)
		{
			// TODO : Needs fixing!
			
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
			[queryPath setStringValue:selectedKey];
			selectedFilename = [[panel filename] retain];
			[queryButton setEnabled:YES];
			
			[self resetLengths:self];
		}
	}
}

-(IBAction)resetLengths:(id)sender
{
	queryTrack = [[NSSound alloc] initWithContentsOfFile:selectedFilename byReference:YES];

	double samples = ([queryTrack duration]*44100.0f);
	double hopSize = [[dbState objectForKey:@"hopsize"] doubleValue];
	double winSize = [[dbState objectForKey:@"windowsize"] doubleValue];
	
	[queryLengthSeconds setDoubleValue:[queryTrack duration]];
	[queryLengthVectors setDoubleValue:ceil((samples-winSize)/hopSize)];
	
	// For now, go with 0
	[queryStartSeconds setDoubleValue:0];
	[queryStartVectors setDoubleValue:0];

	[queryLengthSeconds setEnabled:YES];
	[queryLengthVectors setEnabled:YES];
	[queryStartSeconds setEnabled:YES];
	[queryStartVectors setEnabled:YES];
	[resetButton setEnabled:YES];
	[multipleCheckBox setEnabled:YES];
	
}

- (void)controlTextDidChange:(NSNotification *)nd
{
	NSTextField *ed = [nd object];
	
	double hopSize = [[dbState objectForKey:@"hopsize"] doubleValue];
	double winSize = [[dbState objectForKey:@"windowsize"] doubleValue];
	
	if(!queryTrack)
	{
		queryTrack = [[NSSound alloc] initWithContentsOfFile:selectedFilename byReference:YES];
	}
	
	double totalDuration = [queryTrack duration];
	double samples = totalDuration * 44100.0f;
	double totalVectors = ceil((samples-winSize)/hopSize);

	double lengthSecs = [queryLengthSeconds doubleValue];
	double startSecs = [queryStartSeconds doubleValue];
	double lengthVectors = [queryLengthVectors doubleValue];
	double startVectors = [queryStartVectors doubleValue];
	
	// Query Length
	if (ed == queryLengthSeconds)
	{
		if(lengthSecs >= 0)
		{
			lengthVectors = ceil(((lengthSecs*44100.0f)-winSize)/hopSize);
			if(lengthVectors < 0) {lengthVectors = 0; }
			[queryLengthVectors setDoubleValue:lengthVectors];
			
		}
	}
	
	if (ed == queryLengthVectors)
	{
		if(lengthVectors >= 0)
		{
			lengthSecs = ((hopSize*lengthVectors)+winSize)/44100.0f;
			if(lengthSecs < 0) { lengthSecs = 0; }
			[queryLengthSeconds setDoubleValue:lengthSecs];
		}
	}
	
	// Query start
	if (ed == queryStartSeconds)
	{
		if(startSecs >= 0)
		{
			startVectors = ceil(((startSecs*44100.0f)-winSize)/hopSize);
			if(startVectors < 0) { startVectors = 0; }
			[queryStartVectors setDoubleValue:startVectors];
		}
	}
	if (ed == queryStartVectors)
	{
		if(startVectors >= 0)
		{
			startSecs = ((hopSize*startVectors)+winSize)/44100.0f;
			if(startSecs < 0) { startSecs = 0; }
			[queryStartSeconds setDoubleValue:startSecs];
		}
	}
	
	if((lengthSecs + startSecs) > totalDuration || (lengthVectors + startVectors) > totalVectors || lengthVectors == 0)
	{
		[queryButton setEnabled:NO];
	}
	else if(![queryButton isEnabled])
	{
		[queryButton setEnabled:YES];
	}
}

-(IBAction)cancelQuery:(id)sender
{
	[NSApp endModalSession:session];
	[querySheet orderOut:nil];
	[NSApp endSheet:querySheet];
}

/**
 * Actually perform the query. TODO: Monolithic.
 */
-(IBAction)performQuery:(id)sender
{
	[NSApp endModalSession:session];
	[querySheet orderOut:nil];
	[NSApp endSheet:querySheet];
	
	NSLog(@"Perform query! %@, %@", selectedKey, selectedFilename);
	
	adb_query_spec_t *spec = (adb_query_spec_t *)malloc(sizeof(adb_query_spec_t));
	spec->qid.datum = (adb_datum_t *)malloc(sizeof(adb_datum_t));
	
	spec->qid.sequence_length = [queryLengthVectors doubleValue];
	spec->qid.sequence_start = [queryStartVectors doubleValue];
	spec->qid.flags = 0;	
//	spec->qid.flags = spec->qid.flags | ADB_QID_FLAG_EXHAUSTIVE;
	
	spec->params.accumulation = ADB_ACCUMULATION_PER_TRACK;
	
	if([multipleCheckBox state] == NSOnState)
	{
		spec->params.npoints = 100;
	}
	else
	{
		spec->params.npoints = 1;
	}
		
	spec->params.distance = ADB_DISTANCE_EUCLIDEAN_NORMED;
	
	spec->params.ntracks = 100;
	//spec->refine.radius = 5.0;
//	spec->refine.absolute_threshold = -6;
//	spec->refine.relative_threshold = 10;
//	spec->refine.duration_ratio = 0;
	
	spec->refine.flags = 0;
//	spec->refine.flags |= ADB_REFINE_ABSOLUTE_THRESHOLD;
//	spec->refine.flags |= ADB_REFINE_RELATIVE_THRESHOLD;
//	spec->refine.flags |= ADB_REFINE_HOP_SIZE;
	//spec->refine.flags |= ADB_REFINE_RADIUS;

	adb_query_results_t *result = (adb_query_results_t *)malloc(sizeof(adb_query_results_t));
	spec->qid.datum->data = NULL;
	spec->qid.datum->power = NULL;
	spec->qid.datum->times = NULL;
	
	[results removeAllObjects];
	
	int ok = audiodb_retrieve_datum(db, [selectedKey cStringUsingEncoding:NSUTF8StringEncoding], spec->qid.datum);
	if(ok == 0)
	{
		
		float hopSize = [[dbState objectForKey:@"hopsize"] floatValue];
		NSLog(@"Got a datum");
		result = audiodb_query_spec(db, spec);
		if(result == NULL)
		{
			
			NSLog(@"No results");
		}
		else
		{
			NSLog(@"Populate table: %d", result->nresults);
			float divisor = (44100.0f/hopSize);
			for(int i=0; i<result->nresults; i++)
			{
				
				NSMutableDictionary* dict = [[NSMutableDictionary alloc] initWithCapacity:4];
				[dict setValue:[NSString stringWithFormat:@"%s", result->results[i].ikey] forKey:@"key"];
				[dict setValue:[NSNumber numberWithFloat:result->results[i].dist] forKey:@"distance"];
				[dict setValue:[NSNumber numberWithFloat:result->results[i].dist] forKey:@"meter"];
				[dict setValue:[NSNumber numberWithFloat:result->results[i].ipos/divisor] forKey:@"ipos"];
				NSLog(@"%s ipos: %d, dist: %f", result->results[i].ikey,result->results[i].ipos, result->results[i].dist);
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
