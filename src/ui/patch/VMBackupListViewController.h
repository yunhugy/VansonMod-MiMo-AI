#import <UIKit/UIKit.h>

@interface VMBackupListViewController : UITableViewController
@property (nonatomic, copy) NSString *appName; 
@property (nonatomic, copy) NSString *bid;     
@property (nonatomic, assign) BOOL isFolderMode; 
@property (nonatomic, strong) NSMutableArray *folderList; 
@end
