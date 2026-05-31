#import <UIKit/UIKit.h>

@interface VMPointerSessionListViewController : UIViewController

@property (nonatomic, copy) NSString *bundleID;
@property (nonatomic, assign) BOOL isFolderMode; 
@property (nonatomic, strong) NSMutableArray *folderList; 

- (void)showToast:(NSString *)msg;

@end
