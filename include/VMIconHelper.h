#import <UIKit/UIKit.h>

@interface VMIconHelper : NSObject

+ (UIImage *)compatibleSystemImageNamed:(NSString *)name;

+ (UIImage *)compatibleSystemImageNamed:(NSString *)name fallback:(NSString *)fallbackName;

@end
