#import "VMUpdateManager.h"
#import "include/VMLocalization.h"

#define TR(key) ([[VMLocalization shared] localizedString:key])
#define GITHUB_API_URL @"https://api.github.com/repos/vaenshine/VansonMod/releases/latest"

@implementation VMUpdateManager

+ (instancetype)shared {
  static VMUpdateManager *s;
  static dispatch_once_t once;
  dispatch_once(&once, ^{ s = [self new]; });
  return s;
}

- (void)performAutoCheck {
  [self checkForUpdateManual:NO completion:nil];
}

- (void)checkForUpdateManual:(BOOL)manual completion:(void (^)(void))completion {
  NSString *localVer = [[NSBundle mainBundle] infoDictionary][@"CFBundleShortVersionString"];
  if ([localVer hasPrefix:@"Test"]) {
    dispatch_async(dispatch_get_main_queue(), ^{
      if (completion) completion();
    });
    return;
  }
  
  NSURL *url = [NSURL URLWithString:GITHUB_API_URL];
  NSURLRequest *request = [NSURLRequest requestWithURL:url
                                           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                       timeoutInterval:15.0];

  [[[NSURLSession sharedSession] dataTaskWithRequest:request
      completionHandler:^(NSData *data, NSURLResponse *res, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
          if (completion) completion();

          if (error || !data) {
            if (manual) [self showAlert:TR(@"Alert_Error") msg:TR(@"Err_Network_Failed")];
            return;
          }

          NSError *jsonErr;
          NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonErr];
          if (jsonErr || !json) {
            if (manual) [self showAlert:TR(@"Alert_Error") msg:TR(@"Err_Invalid_JSON")];
            return;
          }

          NSString *remoteVer = json[@"tag_name"];
          if ([remoteVer hasPrefix:@"v"]) remoteVer = [remoteVer substringFromIndex:1];

          if ([remoteVer compare:localVer options:NSNumericSearch] == NSOrderedDescending) {
            self.hasNewVersion = YES;
            self.latestVersionStr = remoteVer;
            self.releaseNotes = json[@"body"];
            self.downloadURL = json[@"html_url"];

            [[NSNotificationCenter defaultCenter] postNotificationName:kVMUpdateAvailableNotification
                                                                object:nil];
            if (manual) {
              [self showUpdateAlertFromViewController:[self topViewController]];
            }
          } else {
            self.hasNewVersion = NO;
            if (manual) {
              [self showAlert:TR(@"Alert_Success") msg:TR(@"Update_No_New")];
            }
          }
        });
      }] resume];
}

- (void)showUpdateAlertFromViewController:(UIViewController *)vc {
  if (!vc)
    vc = [self topViewController];

  NSString *title = [NSString
      stringWithFormat:@"%@ v%@", TR(@"Update_Found"), self.latestVersionStr];
  UIAlertController *alert =
      [UIAlertController alertControllerWithTitle:title
                                          message:self.releaseNotes
                                   preferredStyle:UIAlertControllerStyleAlert];

  [alert
      addAction:[UIAlertAction
                    actionWithTitle:TR(@"Update_Go")
                              style:UIAlertActionStyleDefault
                            handler:^(UIAlertAction *action) {
                              [[UIApplication sharedApplication]
                                            openURL:[NSURL URLWithString:
                                                               self.downloadURL]
                                            options:@{}
                                  completionHandler:nil];
                            }]];

  [alert addAction:[UIAlertAction actionWithTitle:TR(@"Btn_Cancel")
                                            style:UIAlertActionStyleCancel
                                          handler:nil]];

  [vc presentViewController:alert animated:YES completion:nil];
}

- (void)showAlert:(NSString *)title msg:(NSString *)msg {
  UIAlertController *alert =
      [UIAlertController alertControllerWithTitle:title
                                          message:msg
                                   preferredStyle:UIAlertControllerStyleAlert];
  [alert addAction:[UIAlertAction actionWithTitle:TR(@"Btn_OK")
                                            style:UIAlertActionStyleCancel
                                          handler:nil]];
  [[self topViewController] presentViewController:alert
                                         animated:YES
                                       completion:nil];
}

- (UIViewController *)topViewController {
  UIWindow *window = nil;

  if (@available(iOS 13.0, *)) {
    for (UIWindowScene *scene in [UIApplication sharedApplication]
             .connectedScenes) {
      if (scene.activationState == UISceneActivationStateForegroundActive) {
        for (UIWindow *w in scene.windows) {
          if (w.isKeyWindow) {
            window = w;
            break;
          }
        }
      }
      if (window)
        break;
    }
  }

  if (!window) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    window = [[UIApplication sharedApplication] keyWindow];
#pragma clang diagnostic pop
  }

  UIViewController *top = window.rootViewController;
  while (top.presentedViewController) {
    top = top.presentedViewController;
  }
  return top;
}

@end
