#import "include/VMMemoryEngine.h" // For VMDataType
#import <UIKit/UIKit.h>

@protocol VMItemCardCellDelegate <NSObject>
@optional
- (void)itemCellDidToggleSwitch:(UITableViewCell *)cell isOn:(BOOL)isOn;
@end

@interface VMItemCardCell : UITableViewCell
@property(nonatomic, strong) UIView *bgView;
@property(nonatomic, strong) UILabel *lblNote;
@property(nonatomic, strong) UILabel *lblAddr;
@property(nonatomic, strong) UILabel *lblValue;
@property(nonatomic, strong) UISwitch *lockSwitch;
@property(nonatomic, strong) UIImageView *favIcon;
@property(nonatomic, weak) id<VMItemCardCellDelegate> delegate;
@property(nonatomic, assign) BOOL isFavMode;

- (void)configureWithDict:(NSDictionary *)item isFavorite:(BOOL)isFav;
@end
