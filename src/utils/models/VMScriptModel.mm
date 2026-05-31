#import "VMScriptModel.h"

@implementation VMScriptModel

+ (BOOL)supportsSecureCoding {
  return YES;
}

- (instancetype)init {
  if (self = [super init]) {
    _createdAt = [[NSDate date] timeIntervalSince1970];
    _scriptContent = @"";
    _author = @"VansonMod";
    _desc = @"VansonMod Script"; 
  }
  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
  [coder encodeObject:_fileName forKey:@"fn"];
  [coder encodeObject:_bundleID forKey:@"bid"];
  [coder encodeObject:_appName forKey:@"aname"];
  [coder encodeObject:_scriptContent forKey:@"src"];
  [coder encodeObject:_note forKey:@"note"];
  [coder encodeObject:_desc forKey:@"desc"];
  [coder encodeObject:_author forKey:@"auth"];
  [coder encodeBool:_isImported forKey:@"isImported"]; 
  [coder encodeDouble:_createdAt forKey:@"date"];
  [coder encodeDouble:_sortOrder forKey:@"sortOrder"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
  if (self = [super init]) {
    _fileName = [coder decodeObjectOfClass:[NSString class] forKey:@"fn"];
    _bundleID = [coder decodeObjectOfClass:[NSString class] forKey:@"bid"];
    _appName = [coder decodeObjectOfClass:[NSString class] forKey:@"aname"];
    _scriptContent = [coder decodeObjectOfClass:[NSString class] forKey:@"src"];
    _note = [coder decodeObjectOfClass:[NSString class] forKey:@"note"];
    _desc = [coder decodeObjectOfClass:[NSString class] forKey:@"desc"];
    _author = [coder decodeObjectOfClass:[NSString class] forKey:@"auth"];
    _isImported = [coder decodeBoolForKey:@"isImported"];
    _createdAt = [coder decodeDoubleForKey:@"date"];
    _sortOrder = [coder decodeDoubleForKey:@"sortOrder"];

    if (!_desc)
      _desc = @"VansonMod Script";
  }
  return self;
}

- (NSDictionary *)toDictionary {
  return @{
    @"type" : @"script",
    @"fn" : _fileName ?: @"",
    @"bid" : _bundleID ?: @"",
    @"src" : _scriptContent ?: @"",
    @"note" : _note ?: @"",
    @"desc" : _desc ?: @"",
    @"auth" : _author ?: @"",
    @"isImported" : @(_isImported), 
    @"date" : @(_createdAt),
    @"sortOrder" : @(_sortOrder)
  };
}

+ (instancetype)fromDictionary:(NSDictionary *)dict {
  VMScriptModel *m = [[VMScriptModel alloc] init];
  m.fileName = dict[@"fn"];
  m.bundleID = dict[@"bid"];
  m.scriptContent = dict[@"src"];
  m.note = dict[@"note"];
  m.desc = dict[@"desc"];
  if (!m.desc || m.desc.length == 0)
    m.desc = @"VansonMod Script";

  m.author = dict[@"auth"];
  m.isImported = [dict[@"isImported"] boolValue];
  m.createdAt = [dict[@"date"] doubleValue];
  m.sortOrder = [dict[@"sortOrder"] doubleValue];

  return m;
}

@end
