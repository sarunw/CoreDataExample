//
//  MasterViewController.h
//  CoreDataExample
//
//  Created by Sarun Wongpatcharapakorn on 1/5/15.
//  Copyright (c) 2015 Sarun Wongpatcharapakorn. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <CoreData/CoreData.h>

@interface MasterViewController : UITableViewController <NSFetchedResultsControllerDelegate>

@property (strong, nonatomic) NSFetchedResultsController *fetchedResultsController;
@property (strong, nonatomic) NSManagedObjectContext *managedObjectContext;


@end

