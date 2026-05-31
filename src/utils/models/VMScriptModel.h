#import <Foundation/Foundation.h>

@interface VMScriptModel : NSObject <NSSecureCoding>

@property(nonatomic, copy) NSString *fileName; 
@property(nonatomic, copy) NSString *bundleID; 
@property(nonatomic, copy) NSString *appName;
@property(nonatomic, copy) NSString *scriptContent; 
@property(nonatomic, copy) NSString *note;          
@property(nonatomic, copy) NSString *desc;          
@property(nonatomic, copy) NSString *author;        
@property(nonatomic, assign) BOOL isImported;       

@property(nonatomic, assign) NSTimeInterval createdAt;
@property(nonatomic, assign) double sortOrder;  

- (NSDictionary *)toDictionary;
+ (instancetype)fromDictionary:(NSDictionary *)dict;

@end
