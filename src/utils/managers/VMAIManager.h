#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Streaming callback: called multiple times with incremental text,
/// then one final time with (nil, error) or (fullText, nil).
typedef void (^VMAIStreamBlock)(NSString * _Nullable chunk,
                                NSString * _Nullable fullText,
                                NSError * _Nullable error);

@interface VMAIManager : NSObject

+ (instancetype)shared;

/// Config from NSUserDefaults
@property (nonatomic, copy) NSString *baseURL;   // e.g. https://api.xiaomi.com/v1
@property (nonatomic, copy) NSString *apiKey;
@property (nonatomic, copy) NSString *model;     // e.g. MiMo-V2-Flash
@property (nonatomic, assign) double temperature;
@property (nonatomic, assign) NSInteger maxTokens;

/// Reload config from NSUserDefaults
- (void)reloadConfig;

/// Save current config to NSUserDefaults
- (void)saveConfig;

/// Synchronous chat (blocks calling thread). Used by JS scripts.
- (NSString *)chatSync:(NSString *)prompt;

/// Synchronous chat with system prompt
- (NSString *)chatSync:(NSString *)prompt system:(NSString * _Nullable)systemPrompt;

/// Async chat with streaming
- (void)chatStream:(NSString *)prompt
        completion:(VMAIStreamBlock)completion;

/// Async chat with streaming + system prompt
- (void)chatStream:(NSString *)prompt
            system:(NSString * _Nullable)systemPrompt
        completion:(VMAIStreamBlock)completion;

/// Multi-turn conversation (messages array)
- (void)chatMessages:(NSArray<NSDictionary *> *)messages
          completion:(VMAIStreamBlock)completion;

/// Check if AI is configured
- (BOOL)isConfigured;

@end

NS_ASSUME_NONNULL_END
