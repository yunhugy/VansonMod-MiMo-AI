#import <UIKit/UIKit.h>
@class VMRVAPatch;

@protocol VMRVAManagerCellDelegate <NSObject>
- (void)didClickRVAEdit:(UITableViewCell *)cell;
- (void)didClickRVAToggle:(UITableViewCell *)cell; 
@end

@interface VMRVAManagerCell : UITableViewCell

@property (nonatomic, weak) id<VMRVAManagerCellDelegate> delegate;

- (void)configureWithPatch:(VMRVAPatch *)patch;

- (void)updateStateVisuals:(BOOL)isActive animated:(BOOL)animated;

@end
