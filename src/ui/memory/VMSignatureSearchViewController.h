#import <UIKit/UIKit.h>
#import "include/VMMemoryEngine.h"

@interface VMSignatureSearchViewController : UIViewController <UITextFieldDelegate, UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, assign) uint64_t initialAddress;
@property (nonatomic, assign) VMDataType targetType;
@property (nonatomic, strong) NSDate *scanStartTime;
@end
