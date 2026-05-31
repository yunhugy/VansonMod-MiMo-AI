#import <UIKit/UIKit.h>

@interface VMItemEditViewController : UIViewController

@property(nonatomic, strong) id model;
@property(nonatomic, copy) void (^onSave)(id updatedModel);

+ (void)presentInController:(UIViewController *)vc
                      model:(id)model
                     onSave:(void (^)(id updatedModel))onSave;

@end
