#import <UIKit/UIKit.h>

@interface VMModifierViewController : UIViewController

@property (nonatomic, assign) BOOL isPointerSearchMode;
@property (nonatomic, copy) NSString *initialSearchVal;
@property (nonatomic, assign) NSInteger initialSearchMode;

- (void)performPointerSearch:(uint64_t)targetAddress;

@end
