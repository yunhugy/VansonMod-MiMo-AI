#import <UIKit/UIKit.h>

@interface VMShareHelper : NSObject
+ (NSString *)generateUniqueExportPathForName:(NSString *)baseName extension:(NSString *)ext;
+ (void)shareContent:(id)content 
  fromViewController:(UIViewController *)vc 
          sourceView:(UIView *)view 
          sourceRect:(CGRect)rect;
@end
