#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#define kVMUpdateAvailableNotification @"VMUpdateAvailableNotification"

@interface VMUpdateManager : NSObject

+ (instancetype)shared;

@property (nonatomic, assign) BOOL hasNewVersion;
@property (nonatomic, copy) NSString *latestVersionStr;
@property (nonatomic, copy) NSString *releaseNotes;
@property (nonatomic, copy) NSString *downloadURL;

- (void)performAutoCheck;

- (void)checkForUpdateManual:(BOOL)manual completion:(void(^)(void))completion;

- (void)showUpdateAlertFromViewController:(UIViewController *)vc;

@end
