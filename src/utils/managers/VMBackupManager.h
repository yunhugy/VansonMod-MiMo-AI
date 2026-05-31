#import <Foundation/Foundation.h>

@interface VMBackupManager : NSObject

+ (instancetype)shared;

- (NSString *)getDataPathForBundleID:(NSString *)bid;

- (NSString *)myBackupFolder;

- (NSString *)backupApp:(NSString *)bid name:(NSString *)appName;

- (BOOL)restoreApp:(NSString *)bid backupPath:(NSString *)backupPath;

- (NSArray *)getBackupsForApp:(NSString *)appName;

- (void)deleteBackupPath:(NSString *)path;

@end
