#import <UIKit/UIKit.h>
#import "include/VMSignatureModel.h"
#import "include/VMMemoryEngine.h"

@protocol VMSignatureLockCellDelegate <NSObject>
@optional
- (void)didClickSettings:(UITableViewCell *)cell;
- (void)didClickScan:(UITableViewCell *)cell;
- (void)didClickResultMore:(UITableViewCell *)cell atIndex:(NSInteger)index;
- (void)didClickResultValue:(UITableViewCell *)cell atIndex:(NSInteger)index address:(uint64_t)addr currentValue:(NSString *)val;
- (void)didChangeModeSegment:(UITableViewCell *)cell atIndex:(NSInteger)index isSlider:(BOOL)isSlider isSwitch:(BOOL)isSwitch;
- (void)didChangeResultSliderValue:(UITableViewCell *)cell atIndex:(NSInteger)index value:(NSString *)value;

- (void)didChangeResultSwitchState:(UITableViewCell *)cell atIndex:(NSInteger)index isOn:(BOOL)isOn;
@end

@interface VMSignatureLockCell : UITableViewCell

@property (nonatomic, weak) id<VMSignatureLockCellDelegate> delegate;
@property (nonatomic, strong) VMSignatureModel *currentSig;

- (void)configureWithSignature:(VMSignatureModel *)sig;

@end
