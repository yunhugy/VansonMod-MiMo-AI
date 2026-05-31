#import <Foundation/Foundation.h>
#import "VMPointerChain.h"

@interface VMPointerManager : NSObject

@property (nonatomic, copy, readonly) NSString *verifierFolder;

+ (instancetype)shared;

- (NSArray<VMPointerChain *> *)loadChainsFromPath:(NSString *)filePath;
- (NSString *)saveChainsToVerifierFile:(NSArray<VMPointerChain *> *)chains bundleID:(NSString *)bundleID;
- (NSString *)generateUniquePathInFolder:(NSString *)folder baseName:(NSString *)baseName extension:(NSString *)ext;

- (NSArray<NSString *> *)getSavedApps;

@end
