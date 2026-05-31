 
#import <Foundation/Foundation.h>
#include <mach/mach_types.h>

NS_ASSUME_NONNULL_BEGIN

@interface VMStackFrame : NSObject
@property (nonatomic, assign) uint64_t pc;
@property (nonatomic, copy) NSString *imageName;
@property (nonatomic, assign) uint64_t imageBase;
@property (nonatomic, assign) uint64_t offset;
@end

@interface VMWatchHit : NSObject
@property (nonatomic, assign) uint32_t slotIndex;
@property (nonatomic, assign) uint64_t pc;
@property (nonatomic, assign) uint64_t address;
@property (nonatomic, assign) uint64_t newValue;
@property (nonatomic, copy) NSString *imageName;
@property (nonatomic, assign) uint64_t offset;
@property (nonatomic, strong) NSArray<VMStackFrame *> *stackTrace;
@property (nonatomic, assign) double timestamp;
@end

typedef NS_ENUM(NSUInteger, VMWatchType) {
    VMWatchTypeWrite = 0,
    VMWatchTypeRead = 1,
    VMWatchTypeReadWrite = 2
};

typedef NS_ENUM(NSUInteger, VMWatchSize) {
    VMWatchSizeByte1 = 0,
    VMWatchSizeByte2 = 1,
    VMWatchSizeByte4 = 2,
    VMWatchSizeByte8 = 3
};

typedef void (^VMWatchHitBlock)(VMWatchHit *hit);

@interface VMDebugEngine : NSObject

+ (instancetype)shared;

+ (BOOL)isAvailable;

- (BOOL)attach;
- (void)detach;
@property (nonatomic, readonly) BOOL isAttached;
@property (nonatomic, readonly) mach_port_t currentTask;

- (int)addWatchpoint:(uint64_t)address
                type:(VMWatchType)type
                size:(VMWatchSize)size;
- (BOOL)removeWatchpoint:(uint32_t)index;
- (void)removeAllWatchpoints;

@property (nonatomic, readonly) uint32_t activeCount;
@property (nonatomic, readonly) uint32_t maxSlots;

- (BOOL)isSlotActive:(uint32_t)index;
- (uint64_t)slotAddress:(uint32_t)index;

- (NSArray<VMWatchHit *> *)hitsForSlot:(uint32_t)index;
- (void)clearHitsForSlot:(uint32_t)index;
- (void)clearAllHits;

@property (nonatomic, copy, nullable) VMWatchHitBlock hitCallback;

- (NSArray<NSDictionary *> *)disassembleAt:(uint64_t)address
                               countBefore:(uint32_t)before
                                countAfter:(uint32_t)after
                                moduleName:(nullable NSString *)moduleName;

- (NSArray<NSDictionary *> *)disassembleFunctionAt:(uint64_t)pc
                                        moduleName:(nullable NSString *)moduleName;

@end

NS_ASSUME_NONNULL_END
