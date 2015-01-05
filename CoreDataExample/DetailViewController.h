//
//  DetailViewController.h
//  CoreDataExample
//
//  Created by Sarun Wongpatcharapakorn on 1/5/15.
//  Copyright (c) 2015 Sarun Wongpatcharapakorn. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface DetailViewController : UIViewController

@property (strong, nonatomic) id detailItem;
@property (weak, nonatomic) IBOutlet UILabel *detailDescriptionLabel;

@end

