#import "VMAIManager.h"
#import <UIKit/UIKit.h>

static NSString *const kAIBaseURL    = @"ai_baseURL";
static NSString *const kAIApiKey     = @"ai_apiKey";
static NSString *const kAIModel      = @"ai_model";
static NSString *const kAITemp       = @"ai_temperature";
static NSString *const kAIMaxTokens  = @"ai_maxTokens";

#pragma mark - SSE Stream Delegate

@interface VMAIStreamParser : NSObject <NSURLSessionDataDelegate>
@property (nonatomic, copy)   void (^onChunk)(NSString *delta, NSString *accumulated);
@property (nonatomic, copy)   void (^onDone)(NSString *fullText, NSError *error);
@property (nonatomic, strong) NSMutableData *buffer;
@property (nonatomic, strong) NSMutableString *accumulated;
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSURLSessionDataTask *task;
@end

@implementation VMAIStreamParser

- (instancetype)init {
    if (self = [super init]) {
        _buffer     = [NSMutableData data];
        _accumulated = [NSMutableString string];
    }
    return self;
}

- (void)startRequest:(NSMutableURLRequest *)req {
    NSURLSessionConfiguration *cfg =
        [NSURLSessionConfiguration defaultSessionConfiguration];
    cfg.timeoutIntervalForRequest  = 120;
    self.session = [NSURLSession sessionWithConfiguration:cfg delegate:self delegateQueue:nil];
    self.task = [self.session dataTaskWithRequest:req];
    [self.task resume];
}

// Accumulate data and parse SSE lines
- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveData:(NSData *)data {
    [self.buffer appendData:data];
    [self parseBuffer];
}

- (void)parseBuffer {
    NSString *str = [[NSString alloc] initWithData:self.buffer encoding:NSUTF8StringEncoding];
    if (!str) return;

    NSArray *lines = [str componentsSeparatedByString:@"\n"];
    // Keep last incomplete line in buffer
    NSMutableArray *complete = [NSMutableArray array];
    for (NSUInteger i = 0; i < lines.count; i++) {
        if (i == lines.count - 1) {
            // Last piece — might be incomplete
            if (![str hasSuffix:@"\n"]) {
                self.buffer = [NSMutableData dataWithData:
                    [lines[i] dataUsingEncoding:NSUTF8StringEncoding]];
                continue;
            }
        }
        [complete addObject:lines[i]];
    }
    if ([str hasSuffix:@"\n"]) {
        self.buffer = [NSMutableData data];
    }

    for (NSString *line in complete) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (![trimmed hasPrefix:@"data:"]) continue;

        NSString *payload = [trimmed substringFromIndex:5];
        payload = [payload stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceCharacterSet]];

        if ([payload isEqualToString:@"[DONE]"]) continue;

        NSData *jsonData = [payload dataUsingEncoding:NSUTF8StringEncoding];
        if (!jsonData) continue;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
        if (!json) continue;

        NSArray *choices = json[@"choices"];
        if (choices.count == 0) continue;
        NSDictionary *delta = choices[0][@"delta"];
        NSString *content = delta[@"content"];
        if (content.length > 0) {
            [self.accumulated appendString:content];
            if (self.onChunk) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.onChunk(content, self.accumulated);
                });
            }
        }
    }
}

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error {
    // Flush remaining buffer
    if (self.buffer.length > 0) {
        [self parseBuffer];
    }
    if (self.onDone) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.onDone(self.accumulated, error);
        });
    }
    [self.session finishTasksAndInvalidate];
}

@end

#pragma mark - VMAIManager

@interface VMAIManager ()
@property (nonatomic, strong) VMAIStreamParser *activeParser;
@end

@implementation VMAIManager

+ (instancetype)shared {
    static VMAIManager *s;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ s = [self new]; });
    return s;
}

- (instancetype)init {
    if (self = [super init]) {
        [self reloadConfig];
    }
    return self;
}

#pragma mark - Config

- (void)reloadConfig {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    self.baseURL    = [d objectForKey:kAIBaseURL] ?: @"https://api.xiaomi.com/v1";
    self.apiKey     = [d objectForKey:kAIApiKey]  ?: @"";
    self.model      = [d objectForKey:kAIModel]   ?: @"MiMo-V2-Flash";
    self.temperature = [d objectForKey:kAITemp] ? [d doubleForKey:kAITemp] : 0.7;
    self.maxTokens   = [d objectForKey:kAIMaxTokens] ? [d integerForKey:kAIMaxTokens] : 4096;
}

- (void)saveConfig {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setObject:self.baseURL   forKey:kAIBaseURL];
    [d setObject:self.apiKey    forKey:kAIApiKey];
    [d setObject:self.model     forKey:kAIModel];
    [d setDouble:self.temperature forKey:kAITemp];
    [d setInteger:self.maxTokens  forKey:kAIMaxTokens];
    [d synchronize];
}

- (BOOL)isConfigured {
    return self.apiKey.length > 0 && self.baseURL.length > 0;
}

#pragma mark - Request Builder

- (NSURL *)chatURL {
    NSString *base = [self.baseURL stringByTrimmingCharactersInSet:
                      [NSCharacterSet characterSetWithCharactersInString:@"/"]];
    return [NSURL URLWithString:[NSString stringWithFormat:@"%@/chat/completions", base]];
}

- (NSMutableURLRequest *)buildRequest:(NSDictionary *)body {
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[self chatURL]];
    req.HTTPMethod = @"POST";
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [req setValue:[NSString stringWithFormat:@"Bearer %@", self.apiKey]
       forHTTPHeaderField:@"Authorization"];
    req.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    return req;
}

- (NSDictionary *)buildBody:(NSArray<NSDictionary *> *)messages stream:(BOOL)stream {
    return @{
        @"model": self.model ?: @"MiMo-V2-Flash",
        @"messages": messages,
        @"temperature": @(self.temperature),
        @"max_tokens": @(self.maxTokens),
        @"stream": @(stream)
    };
}

- (NSMutableArray *)buildMessages:(NSString *)prompt system:(NSString *)systemPrompt {
    NSMutableArray *msgs = [NSMutableArray array];
    if (systemPrompt.length > 0) {
        [msgs addObject:@{@"role": @"system", @"content": systemPrompt}];
    }
    [msgs addObject:@{@"role": @"user", @"content": prompt ?: @""}];
    return msgs;
}

#pragma mark - Synchronous Chat

- (NSString *)chatSync:(NSString *)prompt {
    return [self chatSync:prompt system:nil];
}

- (NSString *)chatSync:(NSString *)prompt system:(NSString *)systemPrompt {
    if (![self isConfigured]) return @"[AI] Error: API not configured";
    if (!prompt || prompt.length == 0) return @"[AI] Error: empty prompt";

    NSArray *msgs = [self buildMessages:prompt system:systemPrompt];
    NSDictionary *body = [self buildBody:msgs stream:NO];

    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
    cfg.timeoutIntervalForRequest = 60;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:cfg];
    NSMutableURLRequest *req = [self buildRequest:body];

    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    __block NSString *result = nil;

    NSURLSessionDataTask *task =
        [session dataTaskWithRequest:req
                   completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
            if (err) {
                result = [NSString stringWithFormat:@"[AI] Error: %@", err.localizedDescription];
            } else {
                NSHTTPURLResponse *http = (NSHTTPURLResponse *)resp;
                if (http.statusCode != 200) {
                    NSString *b = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                    result = [NSString stringWithFormat:@"[AI] HTTP %ld: %@",
                              (long)http.statusCode, b ?: @""];
                } else {
                    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                    NSArray *choices = json[@"choices"];
                    if (choices.count > 0) {
                        result = choices[0][@"message"][@"content"];
                    }
                    if (!result) result = @"[AI] Empty response";
                }
            }
            dispatch_semaphore_signal(sema);
    }];
    [task resume];
    dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
    [session finishTasksAndInvalidate];
    return result;
}

#pragma mark - Streaming Chat

- (void)chatStream:(NSString *)prompt
        completion:(VMAIStreamBlock)completion {
    [self chatStream:prompt system:nil completion:completion];
}

- (void)chatStream:(NSString *)prompt
            system:(NSString *)systemPrompt
        completion:(VMAIStreamBlock)completion {
    if (![self isConfigured]) {
        if (completion) completion(nil, nil,
            [NSError errorWithDomain:@"VMAI" code:1
                            userInfo:@{NSLocalizedDescriptionKey: @"API not configured"}]);
        return;
    }
    if (!prompt || prompt.length == 0) {
        if (completion) completion(nil, nil,
            [NSError errorWithDomain:@"VMAI" code:2
                            userInfo:@{NSLocalizedDescriptionKey: @"Empty prompt"}]);
        return;
    }
    NSArray *msgs = [self buildMessages:prompt system:systemPrompt];
    [self chatMessages:msgs completion:completion];
}

- (void)chatMessages:(NSArray<NSDictionary *> *)messages
          completion:(VMAIStreamBlock)completion {
    if (![self isConfigured]) {
        if (completion) completion(nil, nil,
            [NSError errorWithDomain:@"VMAI" code:1
                            userInfo:@{NSLocalizedDescriptionKey: @"API not configured"}]);
        return;
    }

    NSDictionary *body = [self buildBody:messages stream:YES];
    NSMutableURLRequest *req = [self buildRequest:body];

    VMAIStreamParser *parser = [[VMAIStreamParser alloc] init];
    parser.onChunk = ^(NSString *delta, NSString *accumulated) {
        if (completion) completion(delta, accumulated, nil);
    };
    parser.onDone = ^(NSString *fullText, NSError *error) {
        if (completion) completion(nil, fullText, error);
    };
    self.activeParser = parser;
    [parser startRequest:req];
}

@end
