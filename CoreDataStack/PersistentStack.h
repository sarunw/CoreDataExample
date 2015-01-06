@import Foundation;
@import CoreData;

FOUNDATION_EXTERN NSString* const PSStoreChangeNotification;

@interface PersistentStack : NSObject

- (id)initWithStoreURL:(NSURL *)storeURL modelURL:(NSURL *)modelURL;

@property (nonatomic,strong,readonly) NSManagedObjectContext *managedObjectContext;

@end