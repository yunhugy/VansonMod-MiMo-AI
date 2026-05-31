#import "VMShareHelper.h"
#import "include/VMLocalization.h"
#import <MobileCoreServices/MobileCoreServices.h>
#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#include <sys/stat.h>

#define TR(key) ([[VMLocalization shared] localizedString:key])

#import "src/utils/managers/StorageCore.hpp"

@implementation VMShareHelper

+ (NSString *)generateUniqueExportPathForName:(NSString *)baseName
                                    extension:(NSString *)ext {
  std::string res = VMCore::StorageCore::shared().generateUniquePath(
      [baseName UTF8String], [ext UTF8String]);
  return [NSString stringWithUTF8String:res.c_str()];
}

+ (void)shareContent:(id)content
    fromViewController:(UIViewController *)vc
            sourceView:(UIView *)sourceView
            sourceRect:(CGRect)sourceRect {

  if (!content || !vc)
    return;

  dispatch_async(dispatch_get_main_queue(), ^{
    NSURL *urlToShare = nil;

    if ([content isKindOfClass:[NSURL class]]) {
      urlToShare = (NSURL *)content;
      if (urlToShare.isFileURL) {
        
        chmod([urlToShare.path UTF8String], 0666);
      }
    }

    UIViewController *topVC = vc;
    while (topVC.presentedViewController) {
      topVC = topVC.presentedViewController;
    }

    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
      
      if (urlToShare) {
        if (![[NSFileManager defaultManager]
                fileExistsAtPath:urlToShare.path]) {
          return;
        }

        UIDocumentPickerViewController *picker;
        if (@available(iOS 14.0, *)) {
          picker = [[UIDocumentPickerViewController alloc]
              initForExportingURLs:@[ urlToShare ]
                            asCopy:YES];
        } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
          picker = [[UIDocumentPickerViewController alloc]
              initWithURL:urlToShare
                   inMode:UIDocumentPickerModeExportToService];
#pragma clang diagnostic pop
        }
        picker.modalPresentationStyle = UIModalPresentationFormSheet;
        [topVC presentViewController:picker animated:YES completion:nil];
      }
    } else {
      
      NSArray *items = urlToShare ? @[ urlToShare ] : @[ content ];
      UIActivityViewController *avc =
          [[UIActivityViewController alloc] initWithActivityItems:items
                                            applicationActivities:nil];

      avc.excludedActivityTypes =
          @[ UIActivityTypeAssignToContact, UIActivityTypeAddToReadingList ];

      avc.popoverPresentationController.sourceView = sourceView ?: topVC.view;
      avc.popoverPresentationController.sourceRect =
          CGRectIsEmpty(sourceRect)
              ? CGRectMake(topVC.view.bounds.size.width / 2,
                           topVC.view.bounds.size.height / 2, 1, 1)
              : sourceRect;

      [topVC presentViewController:avc animated:YES completion:nil];
    }
  });
}

+ (void)showAlert:(NSString *)msg inVC:(UIViewController *)vc {
  UIAlertController *alert =
      [UIAlertController alertControllerWithTitle:nil
                                          message:msg
                                   preferredStyle:UIAlertControllerStyleAlert];
  [alert addAction:[UIAlertAction actionWithTitle:TR(@"Btn_OK")
                                            style:UIAlertActionStyleCancel
                                          handler:nil]];
  [vc presentViewController:alert animated:YES completion:nil];
}

@end
