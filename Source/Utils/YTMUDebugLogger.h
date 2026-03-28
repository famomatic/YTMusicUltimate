#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface YTMUDebugLogger : NSObject
+ (void)logCategory:(NSString *)category message:(NSString *)message;
+ (NSArray<NSDictionary<NSString *, id> *> *)sortedEntries;
+ (NSArray<NSString *> *)formattedEntriesWithLimit:(NSUInteger)limit;
+ (void)clear;
@end

NS_ASSUME_NONNULL_END
