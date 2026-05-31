#import <Foundation/Foundation.h>
#import <JavaScriptCore/JavaScriptCore.h>

@protocol VMScriptExports <JSExport>

- (void)log:(NSString *)msg;
- (void)toast:(NSString *)msg;
- (void)sleep:(double)seconds;

JSExportAs(setFloatTolerance, -(void)setFloatTolerance : (double)tolerance);

JSExportAs(setBaseAddress, -(void)setBaseAddress : (NSString *)addr);

JSExportAs(search, -(NSUInteger)search : (NSString *)val type : (NSString *)
                       type from : (NSString *)start to : (NSString *)end);

JSExportAs(searchGroup,
           -(NSUInteger)searchGroup : (NSString *)val type : (NSString *)
               type from : (NSString *)start to : (NSString *)end);

JSExportAs(searchFuzzy, -(NSUInteger)searchFuzzy : (NSString *)type);

JSExportAs(searchSign, -(NSUInteger)searchSign : (NSString *)signature from : (
                           NSString *)start to : (NSString *)end);

JSExportAs(searchBetween,
           -(NSUInteger)searchBetween : (NSString *)minVal
                                  max : (NSString *)maxVal
                                 type : (NSString *)type);

JSExportAs(nearby, -(NSUInteger)nearby : (NSString *)val type : (NSString *)
                       type range : (double)range);

JSExportAs(refine, -(void)refine : (NSString *)val type : (NSString *)
                       type mode : (NSString *)mode);

- (long)getResultsCount;

JSExportAs(getResults, -(NSArray *)getResults : (int)count skip : (int)skip);

JSExportAs(getRangesList, -(NSArray *)getRangesList : (NSString *)name);

- (void)clear;

JSExportAs(editAll, -(void)editAll : (NSString *)val type : (NSString *)
                        type filter : (NSString *)filter);

JSExportAs(getValue,
           -(NSString *)getValue : (NSString *)addrStr type : (NSString *)type);

JSExportAs(setValue, -(BOOL)setValue : (NSString *)addrStr val : (NSString *)
                         val type : (NSString *)type);

JSExportAs(writeAll, -(void)writeAll : (NSString *)val type : (NSString *)type);

JSExportAs(write, -(void)write : (NSString *)val type : (NSString *)
                      type offset : (int)index);

JSExportAs(readAddress, -(NSString *)readAddress : (NSString *)
                            addrStr type : (NSString *)type);

JSExportAs(writeAddress, -(void)writeAddress : (NSString *)addrStr val : (
                             NSString *)val type : (NSString *)type);

- (long)getResultCount;

- (long)count;

JSExportAs(lock, -(void)lock : (NSString *)val type : (NSString *)type index : (int)index);

JSExportAs(unlock, -(void)unlock : (int)index);

JSExportAs(lockAll, -(void)lockAll : (NSString *)val type : (NSString *)type filter : (NSString *)filter);

- (void)unlockAll;

JSExportAs(resolvePointer,
           -(NSDictionary *)resolvePointer : (NSString *)moduleName
                                baseOffset : (NSString *)baseOffsetStr
                                   offsets : (NSArray *)offsets
                                      type : (NSString *)type);

JSExportAs(writePointer,
           -(BOOL)writePointer : (NSString *)moduleName
                    baseOffset : (NSString *)baseOffsetStr
                       offsets : (NSArray *)offsets
                           val : (NSString *)val
                          type : (NSString *)type);

JSExportAs(lockPointer,
           -(void)lockPointer : (NSString *)moduleName
                   baseOffset : (NSString *)baseOffsetStr
                      offsets : (NSArray *)offsets
                          val : (NSString *)val
                         type : (NSString *)type
                         note : (NSString *)note);

JSExportAs(patchRVA,
           -(BOOL)patchRVA : (NSString *)moduleName
                    offset : (NSString *)offsetStr
                  patchHex : (NSString *)patchHex);

JSExportAs(restoreRVA,
           -(BOOL)restoreRVA : (NSString *)moduleName
                      offset : (NSString *)offsetStr
                 originalHex : (NSString *)originalHex);

JSExportAs(readRVA,
           -(NSString *)readRVA : (NSString *)moduleName
                         offset : (NSString *)offsetStr
                         length : (int)length);

// ── AI ──
- (NSString *)aiChat:(NSString *)prompt;
JSExportAs(aiChatSystem, -(NSString *)aiChatSystem : (NSString *)prompt
                                system : (NSString *)systemPrompt);
- (BOOL)aiConfigured;

@end

@interface VMScriptManager : NSObject <VMScriptExports>

+ (instancetype)shared;
- (void)runScript:(NSString *)script
       completion:(void (^)(NSString *log))completion;

@end
