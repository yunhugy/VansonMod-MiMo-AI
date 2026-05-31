#import "include/VMFavoriteManager.h"
#import "include/VMMemoryEngine.h"

@implementation VMFavoriteManager

+ (instancetype)shared {
  static VMFavoriteManager *instance;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    instance = [[self alloc] init];
  });
  return instance;
}

- (NSString *)favoritesDirForApp:(NSString *)bundleID {
  return nil; 
}

- (NSString *)filePathForApp:(NSString *)bundleID {
  return nil; 
}

- (NSArray<NSDictionary *> *)favoritesForApp:(NSString *)bundleID {
  
  return [VMMemoryEngine shared].favoriteItems;
}

- (void)saveFavorites:(NSArray *)list forApp:(NSString *)bundleID {
  
}

- (void)addFavorite:(NSDictionary *)item forApp:(NSString *)bundleID {
  if (!item) return;
  
  uint64_t addr = [item[@"addr"] unsignedLongLongValue];
  
  NSMutableArray *favItems = [VMMemoryEngine shared].favoriteItems;
  if (!favItems) {
    [VMMemoryEngine shared].favoriteItems = [NSMutableArray array];
    favItems = [VMMemoryEngine shared].favoriteItems;
  }
  
  for (NSDictionary *existing in favItems) {
    if ([existing[@"addr"] unsignedLongLongValue] == addr) {
      return; 
    }
  }
  
  [favItems addObject:[item mutableCopy]];
}

- (void)removeFavorite:(NSDictionary *)item forApp:(NSString *)bundleID {
  if (!item) return;
  
  uint64_t addr = [item[@"addr"] unsignedLongLongValue];
  
  NSMutableArray *favItems = [VMMemoryEngine shared].favoriteItems;
  for (NSInteger i = favItems.count - 1; i >= 0; i--) {
    if ([favItems[i][@"addr"] unsignedLongLongValue] == addr) {
      [favItems removeObjectAtIndex:i];
      break;
    }
  }
}

- (BOOL)isFavorite:(uint64_t)address forApp:(NSString *)bundleID {
  
  NSMutableArray *favItems = [VMMemoryEngine shared].favoriteItems;
  for (NSDictionary *item in favItems) {
    if ([item[@"addr"] unsignedLongLongValue] == address) {
      return YES;
    }
  }
  return NO;
}

@end
