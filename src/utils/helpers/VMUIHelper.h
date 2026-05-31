#import <UIKit/UIKit.h>

@interface VMUIHelper : NSObject

+ (UIButton *)createButtonWithTitle:(NSString *)title
                              color:(UIColor *)color
                             target:(id)target
                             action:(SEL)action;

+ (UIButton *)createIconButton:(NSString *)iconName
                         color:(UIColor *)color
                        target:(id)target
                        action:(SEL)action;

+ (UIView *)createVansonFooterViewForWidth:(CGFloat)width;

+ (void)addFixedFooterTo:(UIViewController *)vc forTableView:(UITableView *)tableView;

@end
