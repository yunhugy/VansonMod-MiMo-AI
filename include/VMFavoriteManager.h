#import <Foundation/Foundation.h>

@interface VMFavoriteManager : NSObject

+ (instancetype)shared;

- (void)addFavorite:(NSDictionary *)item forApp:(NSString *)bundleID;
- (void)removeFavorite:(NSDictionary *)item forApp:(NSString *)bundleID;
- (NSArray<NSDictionary *> *)favoritesForApp:(NSString *)bundleID;
- (BOOL)isFavorite:(uint64_t)address forApp:(NSString *)bundleID;

@end
