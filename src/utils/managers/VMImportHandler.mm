#import "VMImportHandler.h"
#import "include/VMDataSession.h"
#import "include/VMLocalization.h"
#import "include/VMPointerChain.h"
#import "include/VMRVAPatch.h"
#import "include/VMSignatureModel.h"
#import "include/VMStoragePathHelper.h"
#import "../models/VMScriptModel.h"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#define TR(key) ([[VMLocalization shared] localizedString:key])

@implementation VMImportHandler

+ (instancetype)shared {
  static VMImportHandler *instance = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    instance = [[VMImportHandler alloc] init];
  });
  return instance;
}

- (BOOL)handleImportWithData:(nullable NSData *)fileData
                         url:(nullable NSURL *)url {
  NSData *activeData = fileData;
  if (!activeData && url) {
    BOOL accessing = [url startAccessingSecurityScopedResource];
    activeData = [NSData dataWithContentsOfURL:url];
    if (accessing)
      [url stopAccessingSecurityScopedResource];
  }

  if (!activeData || activeData.length == 0)
    return NO;

  NSString *ext = [[url pathExtension] lowercaseString];
  NSString *fileName = [url lastPathComponent];

  if (!ext || ext.length == 0)
    return NO;

  VMDataSession *session = nil;
  if ([ext isEqualToString:@"vmvapt"]) {
    session = [VMDataSession fromVerifierJSONData:activeData];
    if (!session) {
      NSError *err = nil;
      NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:activeData
                                                           options:0
                                                             error:&err];
      if (dict && [dict isKindOfClass:[NSDictionary class]]) {
        session = [[VMDataSession alloc] init];
        session.bundleID = dict[@"bundleID"];
      }
    }
  } else {
    session = [VMDataSession fromJSONData:activeData];
  }

  if (!session || !session.bundleID || session.bundleID.length == 0) {
    return NO;
  }

  NSString *bid = session.bundleID;
  NSString *targetTypeDir = nil;

  if ([ext isEqualToString:@"vmsig"]) {
    targetTypeDir = @"SIG";
  } else if ([ext isEqualToString:@"vmrva"]) {
    targetTypeDir = @"RVA";
  } else if ([ext isEqualToString:@"vmsc"]) {
    targetTypeDir = @"Script";
  } else if ([ext isEqualToString:@"vmpt"]) {
    targetTypeDir = @"PTR";
  } else if ([ext isEqualToString:@"vmvapt"]) {
    targetTypeDir = @"ValidatePtr";
  }

  if (!targetTypeDir)
    return NO;

  NSString *appDir = [VMStoragePathHelper pathForSubdirectory:targetTypeDir
                                                     bundleID:bid
                                                       create:YES];

  [VMStoragePathHelper ensureDirectoryAtPath:appDir];

  BOOL success = NO;

  if ([ext isEqualToString:@"vmvapt"] || !session.dataItems || session.dataItems.count <= 1) {
    
    NSString *destPath = [appDir stringByAppendingPathComponent:fileName];
    if ([[NSFileManager defaultManager] fileExistsAtPath:destPath]) {
      [[NSFileManager defaultManager] removeItemAtPath:destPath error:nil];
    }
    success = [activeData writeToFile:destPath atomically:YES];
  } else {
    
    NSString *baseName = [[fileName stringByDeletingPathExtension]
        stringByAppendingString:@"_"];
    NSUInteger idx = 0;
    for (id item in session.dataItems) {
      NSString *itemFileName = [NSString stringWithFormat:@"%@%lu.%@",
          baseName, (unsigned long)idx, ext];
      NSString *destPath = [appDir stringByAppendingPathComponent:itemFileName];
      
      int counter = 1;
      while ([[NSFileManager defaultManager] fileExistsAtPath:destPath]) {
        itemFileName = [NSString stringWithFormat:@"%@%lu_%d.%@",
            baseName, (unsigned long)idx, counter, ext];
        destPath = [appDir stringByAppendingPathComponent:itemFileName];
        counter++;
      }
      VMDataSession *singleSession = [VMDataSession sessionWithData:@[item]
                                                           bundleID:bid
                                                           dataType:session.dataType];
      if (session.appName) singleSession.appName = session.appName;
      if (session.appVersion) singleSession.appVersion = session.appVersion;
      NSData *data = [singleSession toJSONData];
      if (data && [data writeToFile:destPath atomically:YES]) {
        success = YES;
      }
      idx++;
    }
  }

  if (success) {
    NSString *toastMsg = [NSString stringWithFormat:@"%@ %@", TR(@"Msg_Import_Success"), bid];
    
    dispatch_async(dispatch_get_main_queue(), ^{
      dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIViewController *rootVC = nil;
        if (@available(iOS 13.0, *)) {
          for (UIScene *scene in [[UIApplication sharedApplication] connectedScenes]) {
            if ([scene isKindOfClass:[UIWindowScene class]] &&
                scene.activationState == UISceneActivationStateForegroundActive) {
              UIWindowScene *windowScene = (UIWindowScene *)scene;
              for (UIWindow *window in windowScene.windows) {
                if (window.isKeyWindow) {
                  rootVC = window.rootViewController;
                  break;
                }
              }
              break;
            }
          }
        }
        if (!rootVC) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
          rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
#pragma clang diagnostic pop
        }
        
        if (rootVC) {
          UIAlertController *alert = [UIAlertController
              alertControllerWithTitle:nil
                               message:toastMsg
                        preferredStyle:UIAlertControllerStyleAlert];
          [rootVC presentViewController:alert animated:YES completion:^{
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
              [alert dismissViewControllerAnimated:YES completion:nil];
            });
          }];
        }
      });
    });
    
    [[NSNotificationCenter defaultCenter] postNotificationName:@"VM_LockItemAdded" object:nil];
    return YES;
  }

  return NO;
}

@end
