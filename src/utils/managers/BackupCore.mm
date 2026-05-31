#include "BackupCore.hpp"
#import "include/VMStoragePathHelper.h"
#import <Foundation/Foundation.h>
#include <sys/stat.h>

BackupCore &BackupCore::getInstance() {
  static BackupCore instance;
  return instance;
}

std::string BackupCore::getBackupFolder() {
  NSString *backupPath = [VMStoragePathHelper pathForSubdirectory:@"Backup"
                                                         bundleID:nil
                                                           create:YES];

  return [backupPath UTF8String];
}

std::string BackupCore::backupApp(const std::string &bundleID,
                                  const std::string &srcDataPath) {
  if (bundleID.empty() || srcDataPath.empty())
    return "";

  NSString *bid = [NSString stringWithUTF8String:bundleID.c_str()];
  NSString *srcRoot = [NSString stringWithUTF8String:srcDataPath.c_str()];

  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *appFolder =
      [[NSString stringWithUTF8String:getBackupFolder().c_str()]
          stringByAppendingPathComponent:bid];

  if (![fm fileExistsAtPath:appFolder]) {
    [fm createDirectoryAtPath:appFolder
        withIntermediateDirectories:YES
                         attributes:nil
                              error:nil];
  }

  NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
  [fmt setDateFormat:@"yyyyMMdd_HHmmss"];
  NSString *timeStr = [fmt stringFromDate:[NSDate date]];

  NSString *destRoot = [appFolder stringByAppendingPathComponent:timeStr];
  if ([fm fileExistsAtPath:destRoot]) {
    NSString *uuid = [[NSUUID UUID] UUIDString];
    destRoot =
        [destRoot stringByAppendingFormat:@"_%@", [uuid substringToIndex:4]];
  }

  NSError *error = nil;
  if (![fm createDirectoryAtPath:destRoot
          withIntermediateDirectories:YES
                           attributes:nil
                                error:&error]) {
    return "";
  }

  NSArray *subDirs = @[ @"Documents", @"Library" ];
  for (NSString *subDir in subDirs) {
    NSString *src = [srcRoot stringByAppendingPathComponent:subDir];
    NSString *dest = [destRoot stringByAppendingPathComponent:subDir];
    if ([fm fileExistsAtPath:src]) {
      [fm copyItemAtPath:src toPath:dest error:&error];
    }
  }

  return [destRoot UTF8String];
}

bool BackupCore::restoreApp(const std::string &bundleID,
                            const std::string &backupPath,
                            const std::string &targetDataPath) {
  if (bundleID.empty() || backupPath.empty() || targetDataPath.empty())
    return false;

  NSString *srcRoot = [NSString stringWithUTF8String:backupPath.c_str()];
  NSString *targetRoot = [NSString stringWithUTF8String:targetDataPath.c_str()];

  NSFileManager *fm = [NSFileManager defaultManager];
  NSError *error = nil;

  NSArray *subDirs = @[ @"Documents", @"Library" ];
  bool success = true;

  for (NSString *subDir in subDirs) {
    NSString *src = [srcRoot stringByAppendingPathComponent:subDir];
    NSString *target = [targetRoot stringByAppendingPathComponent:subDir];

    if ([fm fileExistsAtPath:src]) {
      if ([fm fileExistsAtPath:target]) {
        if (![fm removeItemAtPath:target error:&error]) {
          success = false;
          continue;
        }
      }
      if (![fm copyItemAtPath:src toPath:target error:&error]) {
        success = false;
      } else {
        fixPermissions([target UTF8String]);
      }
    }
  }

  return success;
}

std::vector<std::string> BackupCore::getBackups(const std::string &bundleID) {
  std::vector<std::string> results;
  if (bundleID.empty())
    return results;

  NSString *bid = [NSString stringWithUTF8String:bundleID.c_str()];
  NSString *appFolder =
      [[NSString stringWithUTF8String:getBackupFolder().c_str()]
          stringByAppendingPathComponent:bid];

  NSFileManager *fm = [NSFileManager defaultManager];
  if (![fm fileExistsAtPath:appFolder])
    return results;

  NSError *error = nil;
  NSArray *contents = [fm contentsOfDirectoryAtPath:appFolder error:&error];
  if (!contents)
    return results;

  NSMutableArray *backups = [NSMutableArray array];
  for (NSString *filename in contents) {
    if (![filename hasPrefix:@"."]) {
      [backups addObject:filename];
    }
  }

  [backups
      sortUsingComparator:^NSComparisonResult(NSString *obj1, NSString *obj2) {
        return [obj2 compare:obj1];
      }];

  for (NSString *name in backups) {
    results.push_back([name UTF8String]);
  }

  return results;
}

void BackupCore::deleteBackup(const std::string &path) {
  if (path.empty())
    return;
  NSString *p = [NSString stringWithUTF8String:path.c_str()];
  [[NSFileManager defaultManager] removeItemAtPath:p error:nil];
}

void BackupCore::fixPermissions(const std::string &path) {
  if (path.empty())
    return;
  NSString *nsPath = [NSString stringWithUTF8String:path.c_str()];

  const char *p = path.c_str();
  chown(p, 501, 501);

  NSFileManager *fm = [NSFileManager defaultManager];
  NSDirectoryEnumerator *enumerator = [fm enumeratorAtPath:nsPath];
  for (NSString *file in enumerator) {
    NSString *fullPath = [nsPath stringByAppendingPathComponent:file];
    chown([fullPath UTF8String], 501, 501);
  }
}
