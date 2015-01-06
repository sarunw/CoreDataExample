#import "PersistentStack.h"

NSString* const PSStoreChangeNotification = @"PSStoreChangeNotification";

@interface PersistentStack ()

@property (nonatomic, strong, readwrite) NSManagedObjectContext* managedObjectContext;
@property (nonatomic, strong) NSURL* modelURL;
@property (nonatomic, strong) NSURL* storeURL;

@property (nonatomic, assign, getter=isCloudEnabled) BOOL cloudEnabled;

@end

@implementation PersistentStack

- (id)initWithStoreURL:(NSURL*)storeURL modelURL:(NSURL*)modelURL 
{
    self = [super init];
    if (self) {
        self.storeURL = storeURL;
        self.modelURL = modelURL;
        [self setupManagedObjectContext];
    }
    return self;
}

- (void)setupManagedObjectContext
{
    self.managedObjectContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
    self.managedObjectContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy;
    self.managedObjectContext.persistentStoreCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:self.managedObjectModel];
    
    
    __weak NSPersistentStoreCoordinator *psc = self.managedObjectContext.persistentStoreCoordinator;
    
    // iCloud notification subscriptions
    NSNotificationCenter *dc = [NSNotificationCenter defaultCenter];
    [dc addObserver:self
           selector:@selector(storesWillChange:)
               name:NSPersistentStoreCoordinatorStoresWillChangeNotification
             object:psc];
    
    [dc addObserver:self
           selector:@selector(storesDidChange:)
               name:NSPersistentStoreCoordinatorStoresDidChangeNotification
             object:psc];
    
    [dc addObserver:self
           selector:@selector(persistentStoreDidImportUbiquitousContentChanges:)
               name:NSPersistentStoreDidImportUbiquitousContentChangesNotification
             object:psc];
    
    NSError* error;
    // the only difference in this call that makes the store an iCloud enabled store
    // is the NSPersistentStoreUbiquitousContentNameKey in options. I use "iCloudStore"
    // but you can use what you like. For a non-iCloud enabled store, I pass "nil" for options.

    // Note that the store URL is the same regardless of whether you're using iCloud or not.
    // If you create a non-iCloud enabled store, it will be created in the App's Documents directory.
    // An iCloud enabled store will be created below a directory called CoreDataUbiquitySupport
    // in your App's Documents directory
    [self.managedObjectContext.persistentStoreCoordinator addPersistentStoreWithType:NSSQLiteStoreType
                                                                       configuration:nil
                                                                                 URL:self.storeURL
                                                                             options:@{ NSPersistentStoreUbiquitousContentNameKey : @"iCloudStore" }
                                                                               error:&error];
    if (error) {
        NSLog(@"error: %@", error);
    }
}

- (NSManagedObjectModel*)managedObjectModel
{
    return [[NSManagedObjectModel alloc] initWithContentsOfURL:self.modelURL];
}

// Subscribe to NSPersistentStoreDidImportUbiquitousContentChangesNotification
- (void)persistentStoreDidImportUbiquitousContentChanges:(NSNotification*)note
{
    NSLog(@"%s", __PRETTY_FUNCTION__);
    NSLog(@"%@", note.userInfo.description);
    
    NSManagedObjectContext *moc = self.managedObjectContext;
    [moc performBlock:^{
        [moc mergeChangesFromContextDidSaveNotification:note];
        
        // you may want to post a notification here so that which ever part of your app
        // needs to can react appropriately to what was merged. 
        // An exmaple of how to iterate over what was merged follows, although I wouldn't
        // recommend doing it here. Better handle it in a delegate or use notifications.
        // Note that the notification contains NSManagedObjectIDs
        // and not NSManagedObjects.
        NSDictionary *changes = note.userInfo;
        NSMutableSet *allChanges = [NSMutableSet new];
        [allChanges unionSet:changes[NSInsertedObjectsKey]];
        [allChanges unionSet:changes[NSUpdatedObjectsKey]];
        [allChanges unionSet:changes[NSDeletedObjectsKey]];
        
        for (NSManagedObjectID *objID in allChanges) {
            // do whatever you need to with the NSManagedObjectID
            // you can retrieve the object from with [moc objectWithID:objID]
        }

    }];
}

// Subscribe to NSPersistentStoreCoordinatorStoresWillChangeNotification
// most likely to be called if the user enables / disables iCloud 
// (either globally, or just for your app) or if the user changes
// iCloud accounts.
- (void)storesWillChange:(NSNotification *)note {
    NSLog(@"Store will change");
    NSManagedObjectContext *moc = self.managedObjectContext;
    [moc performBlockAndWait:^{
        NSError *error = nil;
        if ([moc hasChanges]) {
            [moc save:&error];
        }
        
        [moc reset];
    }];
    
    // now reset your UI to be prepared for a totally different
    // set of data (eg, popToRootViewControllerAnimated:)
    // but don't load any new data yet.
}

// Subscribe to NSPersistentStoreCoordinatorStoresDidChangeNotification
- (void)storesDidChange:(NSNotification *)n {
    // here is when you can refresh your UI and
    // load new data from the new store
    NSLog(@"Store did change");
    
    // Check type of transition
    NSNumber *type = [n.userInfo objectForKey:NSPersistentStoreUbiquitousTransitionTypeKey];
    
    NSLog(@" userInfo is %@", n.userInfo);
    NSLog(@" transition type is %@", type);
    
    if (type.intValue == NSPersistentStoreUbiquitousTransitionTypeInitialImportCompleted) {
        
        NSLog(@" transition type is NSPersistentStoreUbiquitousTransitionTypeInitialImportCompleted");
        
    } else if (type.intValue == NSPersistentStoreUbiquitousTransitionTypeAccountAdded) {
        NSLog(@" transition type is NSPersistentStoreUbiquitousTransitionTypeAccountAdded");
    } else if (type.intValue == NSPersistentStoreUbiquitousTransitionTypeAccountRemoved) {
        NSLog(@" transition type is NSPersistentStoreUbiquitousTransitionTypeAccountRemoved");
    } else if (type.intValue == NSPersistentStoreUbiquitousTransitionTypeContentRemoved) {
        NSLog(@" transition type is NSPersistentStoreUbiquitousTransitionTypeContentRemoved");
    }
    
    [self postStoreChangedNotification];
}

#pragma mark - Notifications
- (void)postStoreChangedNotification {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:PSStoreChangeNotification
                                                            object:self];
    });
}

#pragma mark - Moving

//////////
/*! Moves a local document to iCloud by migrating the existing store to iCloud and then removing the original store.
 We use a local file name of persistentStore and an iCloud name of persistentStore_ICLOUD so its easy to tell if
 the file is iCloud enabled
 
 */
//- (bool)moveStoreToICloud {
//    FLOG(@" called");
//    return [self moveStoreFileToICloud:[self localStoreURL] delete:YES backup:YES];
//}
//- (bool)moveStoreFileToICloud:(NSURL*)fileURL delete:(bool)shouldDelete backup:(bool)shouldBackup {
//    FLOG(@" called");
//    
//    // Always make a backup of the local store before migrating to iCloud
//    if (shouldBackup)
//        [self backupLocalStore];
//    
//    NSPersistentStoreCoordinator *migrationPSC = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:self.managedObjectModel];
//    
//    // Open the existing local store using the original options
//    id sourceStore = [migrationPSC addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:fileURL options:[self localStoreOptions] error:nil];
//    
//    if (!sourceStore) {
//        
//        FLOG(@" failed to add old store");
//        return FALSE;
//    } else {
//        FLOG(@" Successfully added store to migrate");
//        
//        bool moveSuccess = NO;
//        NSError *error;
//        
//        FLOG(@" About to migrate the store...");
//        // Now migrate the store using the iCloud options
//        id migrationSuccess = [migrationPSC migratePersistentStore:sourceStore toURL:[self icloudStoreURL] options:[self icloudStoreOptions] withType:NSSQLiteStoreType error:&error];
//        
//        if (migrationSuccess) {
//            moveSuccess = YES;
//            FLOG(@"store successfully migrated");
//            [self deregisterForStoreChanges];
//            _persistentStoreCoordinator = nil;
//            _managedObjectContext = nil;
//            self.storeURL = [self icloudStoreURL];
//            // Now delete the local file
//            if (shouldDelete) {
//                FLOG(@" deleting local store");
//                [self deleteLocalStore];
//            } else {
//                FLOG(@" not deleting local store");
//            }
//            return TRUE;
//        }
//        else {
//            FLOG(@"Failed to migrate store: %@, %@", error, error.userInfo);
//            return FALSE;
//        }
//        
//    }
//    return FALSE;
//}
///*! Moves an iCloud store to local by migrating the iCloud store to a new local store and then removes the store from iCloud.
// 
// Note that even if it fails to remove the iCloud files it deletes the local copy.  User may need to clean up orphaned iCloud files using a Mac!
// 
// @return Returns YES of file was migrated or NO if not.
// */
//- (bool)moveStoreToLocal {
//    FLOG(@"moveStoreToLocal called");
//    
//    // Lets use the existing PSC
//    NSPersistentStoreCoordinator *migrationPSC = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:self.managedObjectModel];
//    
//    // Open the store
//    id sourceStore = [migrationPSC addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:[self icloudStoreURL] options:[self icloudStoreOptions] error:nil];
//    
//    if (!sourceStore) {
//        
//        FLOG(@" failed to add old store");
//        return FALSE;
//    } else {
//        FLOG(@" Successfully added store to migrate");
//        
//        bool moveSuccess = NO;
//        NSError *error;
//        
//        FLOG(@" About to migrate the store...");
//        id migrationSuccess = [migrationPSC migratePersistentStore:sourceStore toURL:[self localStoreURL] options:[self localStoreOptions] withType:NSSQLiteStoreType error:&error];
//        
//        if (migrationSuccess) {
//            moveSuccess = YES;
//            FLOG(@"store successfully migrated");
//            [self deregisterForStoreChanges];
//            _persistentStoreCoordinator = nil;
//            _managedObjectContext = nil;
//            self.storeURL = [self localStoreURL];
//            [self removeICloudStore];
//        }
//        else {
//            FLOG(@"Failed to migrate store: %@, %@", error, error.userInfo);
//            return FALSE;
//        }
//        
//    }
//    
//    return TRUE;
//}
//- (void)removeICloudStore {
//    BOOL result;
//    NSError *error;
//    // Now delete the iCloud content and file
//    result = [NSPersistentStoreCoordinator removeUbiquitousContentAndPersistentStoreAtURL:[self icloudStoreURL]
//                                                                                  options:[self icloudStoreOptions]
//                                                                                    error:&error];
//    if (!result) {
//        FLOG(@" error removing store");
//        FLOG(@" error %@, %@", error, error.userInfo);
//        return ;
//    } else {
//        FLOG(@" Core Data store removed.");
//        
//        // Now delete the local file
//        [self deleteLocalCopyOfiCloudStore];
//        
//        return ;
//    }
//    
//}
////Check the User setting and if a backup has been requested make one and reset the option
//- (bool)backupCurrentStore {
//    FLOG(@" called");
//    
//    if (!_makeBackupPreferenceKey) {
//        FLOG(@" error _makeBackupPreferenceKey not set!");
//        return FALSE;
//    }
//    
//    [[NSUserDefaults standardUserDefaults] synchronize];
//    NSUserDefaults* userDefaults = [NSUserDefaults standardUserDefaults];
//    bool makeBackup = [userDefaults boolForKey:_makeBackupPreferenceKey];
//    
//    if (!makeBackup) {
//        FLOG(@" backup not required");
//        return FALSE;
//    }
//    
//    return  [self backupCurrentStoreWithNoCheck];
//    
//}
//


@end