#import "include/VMPointerManager.h"
#include "PointerCore.hpp"
#import "include/VMDataSession.h"

@implementation VMPointerManager

+ (instancetype)shared {
  static VMPointerManager *instance;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    instance = [[self alloc] init];
  });
  return instance;
}

- (NSString *)verifierFolder {
  return [NSString stringWithUTF8String:PointerCore::getInstance()
                                            .getVerifierFolder()
                                            .c_str()];
}

- (NSArray<NSString *> *)getSavedApps {
  std::vector<std::string> apps = PointerCore::getInstance().getSavedApps();
  NSMutableArray *result = [NSMutableArray arrayWithCapacity:apps.size()];
  for (const auto &app : apps) {
    [result addObject:[NSString stringWithUTF8String:app.c_str()]];
  }
  return result;
}

- (NSArray<VMPointerChain *> *)loadChainsFromPath:(NSString *)filePath {
  if (!filePath)
    return @[];

  std::vector<uint8_t> buffer =
      PointerCore::getInstance().loadChainsData([filePath UTF8String]);
  if (buffer.empty())
    return @[];

  NSData *data = [NSData dataWithBytes:buffer.data() length:buffer.size()];
  VMDataSession *session = [VMDataSession fromJSONData:data];
  return (session && session.dataItems) ? session.dataItems : @[];
}

- (NSString *)generateUniquePathInFolder:(NSString *)folder
                                baseName:(NSString *)baseName
                               extension:(NSString *)ext {
  
  if (!folder || !baseName || !ext)
    return nil;
  std::string path = PointerCore::getInstance().generateUniquePath(
      [folder UTF8String], [baseName UTF8String], [ext UTF8String]);
  return [NSString stringWithUTF8String:path.c_str()];
}

- (NSString *)saveChainsToVerifierFile:(NSArray<VMPointerChain *> *)chains
                              bundleID:(NSString *)bundleID {
  if (chains.count == 0)
    return nil;

  VMDataSession *session = [VMDataSession sessionWithData:chains
                                                 bundleID:bundleID
                                                 dataType:@"pointer"];

  NSData *data = [session toVerifierJSONData];
  if (!data)
    return nil;

  std::string result = PointerCore::getInstance().saveChains(
      [bundleID UTF8String], (const uint8_t *)data.bytes, data.length,
      chains.count);
  return result.empty() ? nil : [NSString stringWithUTF8String:result.c_str()];
}

@end
