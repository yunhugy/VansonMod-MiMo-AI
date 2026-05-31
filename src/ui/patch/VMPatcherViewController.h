#import <UIKit/UIKit.h>

@interface VMPatcherViewController : UIViewController
@property (nonatomic, copy) NSString *tempOriginalHex; 

- (BOOL)isConnectedToBundle:(NSString *)bundleID;

- (BOOL)tryReconnectForBundleID:(NSString *)bundleID;

- (void)exitBatchMode;

@end
