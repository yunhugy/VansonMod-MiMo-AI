#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface VMScriptShortcutViewController : UIViewController
@property(nonatomic, copy) void (^didSelectShortcut)(NSString *code);
@end

@interface VMScriptExampleViewController : UIViewController
@property(nonatomic, copy) void (^didSelectShortcut)(NSString *code);
@end

NS_ASSUME_NONNULL_END
