#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface VMImportHandler : NSObject

+ (instancetype)shared;

- (BOOL)handleImportWithData:(nullable NSData *)fileData
                         url:(nullable NSURL *)url;

@end

NS_ASSUME_NONNULL_END
