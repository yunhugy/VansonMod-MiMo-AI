#import "VMBackupManager.h"
#include "BackupCore.hpp"
#import <UIKit/UIKit.h>
#include <sys/stat.h>

@implementation VMBackupManager

+ (instancetype)shared {
  static VMBackupManager *s;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    s = [self new];
  });
  return s;
}

- (NSString *)getDataPathForBundleID:(NSString *)bid {
  if (!bid)
    return nil;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
  id proxy = [NSClassFromString(@"LSApplicationProxy")
      performSelector:NSSelectorFromString(@"applicationProxyForIdentifier:")
           withObject:bid];
  NSURL *url =
      [proxy performSelector:NSSelectorFromString(@"dataContainerURL")];
#pragma clang diagnostic pop
  return url.path;
}

- (NSString *)myBackupFolder {
  return [NSString
      stringWithUTF8String:BackupCore::getInstance().getBackupFolder().c_str()];
}

- (NSString *)backupApp:(NSString *)bid name:(NSString *)appName {
  NSString *srcDataPath = [self getDataPathForBundleID:bid];
  if (!srcDataPath)
    return nil;

  std::string result = BackupCore::getInstance().backupApp(
      [bid UTF8String], [srcDataPath UTF8String]);
  return result.empty() ? nil : [NSString stringWithUTF8String:result.c_str()];
}

- (void)fixPermissionsForPath:(NSString *)path {
  if (!path)
    return;
  BackupCore::getInstance().fixPermissions([path UTF8String]);
}

- (BOOL)restoreApp:(NSString *)bid backupPath:(NSString *)backupFolderPath {
  NSString *targetRoot = [self getDataPathForBundleID:bid];
  if (!targetRoot || !backupFolderPath)
    return NO;

  return BackupCore::getInstance().restoreApp(
      [bid UTF8String], [backupFolderPath UTF8String], [targetRoot UTF8String]);
}

- (NSArray *)getBackupsForApp:(NSString *)bundleID {
  if (!bundleID)
    return @[];
  std::vector<std::string> backups =
      BackupCore::getInstance().getBackups([bundleID UTF8String]);

  NSMutableArray *res = [NSMutableArray arrayWithCapacity:backups.size()];
  for (const auto &name : backups) {
    [res addObject:[NSString stringWithUTF8String:name.c_str()]];
  }
  return res;
}

- (void)deleteBackupPath:(NSString *)path {
  if (!path)
    return;
  BackupCore::getInstance().deleteBackup([path UTF8String]);
}

@end
