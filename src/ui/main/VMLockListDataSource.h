#import "include/VMMemoryEngine.h"
#import "include/VMPointerChain.h"
#import <UIKit/UIKit.h>

@protocol VMLockListDataProvider <NSObject>
- (NSInteger)currentTab;
- (BOOL)isFolderMode;
- (NSArray *)folderList;
- (NSDictionary *)folderMetadata;
- (NSArray *)currentDisplayData;
- (uint64_t)forceResolveChain:(VMPointerChain *)chain;
- (NSString *)typeNameForType:(VMDataType)type;
- (NSString *)getDirectoryForCurrentTab;
- (NSString *)targetBundleID;
@end

@interface VMLockListDataSource : NSObject <UITableViewDataSource>
@property(nonatomic, weak) id<VMLockListDataProvider> dataProvider;
@property(nonatomic, weak) id delegate; 

- (instancetype)initWithDataProvider:(id<VMLockListDataProvider>)provider
                            delegate:(id)delegate;
@end
