
#import "../../../include/VMMemoryEngine.h"
#import "../../../include/VMPointerChain.h"
#import <UIKit/UIKit.h>

@class VMPointerLockCell;

@protocol VMPointerLockCellDelegate <NSObject>
- (void)didClickSettings:(UITableViewCell *)cell;
- (void)didClickSet:(UITableViewCell *)cell;
- (void)didChangeLockState:(UITableViewCell *)cell isOn:(BOOL)isOn;
- (void)didClickScan:(UITableViewCell *)cell;

- (void)didClickModifyResult:(UITableViewCell *)cell
                   atAddress:(uint64_t)address
                 currentType:(VMDataType)type;
- (void)didChangeSliderValue:(UITableViewCell *)cell value:(NSString *)val;

- (void)didChangeSwitchState:(UITableViewCell *)cell isOn:(BOOL)isOn;
@end

@interface VMPointerLockCell : UITableViewCell

@property(nonatomic, weak) id<VMPointerLockCellDelegate> delegate;
@property(nonatomic, strong) VMPointerChain *currentChain;

- (void)configureWithChain:(VMPointerChain *)chain
                   address:(NSString *)addr
                       val:(NSString *)val
                      type:(NSString *)typeStr;
- (void)configureForSignature:(VMPointerChain *)chain;
- (void)updateLockStateVisuals:(BOOL)isLocked animated:(BOOL)animated;

@end
