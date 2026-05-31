#include "PointerCore.hpp"
#import "include/VMStoragePathHelper.h"
#import <Foundation/Foundation.h>

PointerCore &PointerCore::getInstance() {
  static PointerCore instance;
  return instance;
}

std::string PointerCore::getVerifierFolder() {
  NSString *path = [VMStoragePathHelper pathForSubdirectory:@"ValidatePtr"
                                                   bundleID:nil
                                                     create:YES];
  return [path UTF8String];
}

std::vector<std::string> PointerCore::getSavedApps() {
  std::vector<std::string> results;
  NSString *folder =
      [NSString stringWithUTF8String:getVerifierFolder().c_str()];
  NSFileManager *fm = [NSFileManager defaultManager];

  if (![fm fileExistsAtPath:folder])
    return results;

  NSError *error = nil;
  NSArray *contents = [fm contentsOfDirectoryAtPath:folder error:&error];
  if (!contents)
    return results;

  for (NSString *filename in contents) {
    if (![filename hasPrefix:@"."]) {
      results.push_back([filename UTF8String]);
    }
  }
  return results;
}

std::string PointerCore::generateUniquePath(const std::string &folder,
                                            const std::string &baseName,
                                            const std::string &ext) {
  NSString *nsFolder = [NSString stringWithUTF8String:folder.c_str()];
  NSString *nsBase = [NSString stringWithUTF8String:baseName.c_str()];
  NSString *nsExt = [NSString stringWithUTF8String:ext.c_str()];

  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *fullPath = [[nsFolder stringByAppendingPathComponent:nsBase]
      stringByAppendingPathExtension:nsExt];
  int counter = 1;

  while ([fm fileExistsAtPath:fullPath]) {
    NSString *newBase = [NSString stringWithFormat:@"%@_%d", nsBase, counter++];
    fullPath = [[nsFolder stringByAppendingPathComponent:newBase]
        stringByAppendingPathExtension:nsExt];
  }

  return [fullPath UTF8String];
}

std::string PointerCore::saveChains(const std::string &bundleID,
                                    const uint8_t *dataPtr, size_t dataSize,
                                    size_t chainCount) {
  if (!dataPtr || dataSize == 0)
    return "";

  NSString *bid = bundleID.empty()
                      ? @"unknown.app"
                      : [NSString stringWithUTF8String:bundleID.c_str()];
  
  bid = [bid stringByReplacingOccurrencesOfString:@"/" withString:@"_"];

  NSString *verifierFolder =
      [NSString stringWithUTF8String:getVerifierFolder().c_str()];
  NSString *appFolder = [verifierFolder stringByAppendingPathComponent:bid];

  NSFileManager *fm = [NSFileManager defaultManager];
  if (![fm fileExistsAtPath:appFolder]) {
    [VMStoragePathHelper ensureDirectoryAtPath:appFolder];
  }

  NSString *baseName;
  if (bid.length > 0 && ![bid isEqualToString:@"unknown.app"]) {
    baseName = [NSString stringWithFormat:@"%@(%lu ptrs)", bid, (unsigned long)chainCount];
  } else {
    baseName = [NSString stringWithFormat:@"verify(%lu ptrs)", (unsigned long)chainCount];
  }

  std::string fullPathStd = generateUniquePath([appFolder UTF8String],
                                               [baseName UTF8String], "vmvapt");
  NSString *fullPath = [NSString stringWithUTF8String:fullPathStd.c_str()];

  NSData *data = [NSData dataWithBytesNoCopy:(void *)dataPtr
                                      length:dataSize
                                freeWhenDone:NO];
  if ([data writeToFile:fullPath atomically:YES]) {
    return fullPathStd;
  }
  return "";
}

std::vector<uint8_t> PointerCore::loadChainsData(const std::string &filePath) {
  std::vector<uint8_t> buffer;
  if (filePath.empty())
    return buffer;

  NSString *path = [NSString stringWithUTF8String:filePath.c_str()];
  NSData *data = [NSData dataWithContentsOfFile:path
                                        options:NSDataReadingMappedIfSafe
                                          error:nil];

  if (data) {
    buffer.resize(data.length);
    memcpy(buffer.data(), data.bytes, data.length);
  }

  return buffer;
}
