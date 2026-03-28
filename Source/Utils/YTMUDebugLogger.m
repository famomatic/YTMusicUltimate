#import "YTMUDebugLogger.h"
#import <dispatch/dispatch.h>

static NSString *const kYTMUPrefsKey = @"YTMUltimate";
static NSString *const kYTMUDebugLogEntriesKey = @"globalDebugLogEntries";
static NSString *const kYTMUDebugLogSequenceKey = @"globalDebugLogSequence";
static NSUInteger const kYTMUDebugLogMaxEntries = 200;

@implementation YTMUDebugLogger

+ (NSMutableDictionary *)mutablePrefs {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSDictionary *existing = [defaults dictionaryForKey:kYTMUPrefsKey] ?: @{};
    return [NSMutableDictionary dictionaryWithDictionary:existing];
}

+ (NSArray<NSDictionary<NSString *, id> *> *)sortedEntries {
    NSDictionary *prefs = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kYTMUPrefsKey] ?: @{};
    id value = prefs[kYTMUDebugLogEntriesKey];
    NSArray<NSDictionary<NSString *, id> *> *entries = [value isKindOfClass:[NSArray class]] ? value : @[];

    NSMutableArray<NSDictionary<NSString *, id> *> *sorted = [entries mutableCopy];
    [sorted sortUsingComparator:^NSComparisonResult(NSDictionary<NSString *, id> *lhs, NSDictionary<NSString *, id> *rhs) {
        double leftTs = [lhs[@"ts"] doubleValue];
        double rightTs = [rhs[@"ts"] doubleValue];
        if (leftTs > rightTs) return NSOrderedAscending;
        if (leftTs < rightTs) return NSOrderedDescending;

        unsigned long long leftSeq = [lhs[@"seq"] unsignedLongLongValue];
        unsigned long long rightSeq = [rhs[@"seq"] unsignedLongLongValue];
        if (leftSeq > rightSeq) return NSOrderedAscending;
        if (leftSeq < rightSeq) return NSOrderedDescending;
        return NSOrderedSame;
    }];
    return [sorted copy];
}

+ (void)logCategory:(NSString *)category message:(NSString *)message {
    if (category.length == 0 || message.length == 0) return;

    @synchronized(self) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        NSMutableDictionary *prefs = [self mutablePrefs];

        id existingEntries = prefs[kYTMUDebugLogEntriesKey];
        NSMutableArray<NSDictionary<NSString *, id> *> *entries = [existingEntries isKindOfClass:[NSArray class]]
            ? [existingEntries mutableCopy]
            : [NSMutableArray array];

        unsigned long long sequence = [prefs[kYTMUDebugLogSequenceKey] unsignedLongLongValue] + 1;
        prefs[kYTMUDebugLogSequenceKey] = @(sequence);

        NSDictionary<NSString *, id> *entry = @{
            @"ts": @([[NSDate date] timeIntervalSince1970]),
            @"seq": @(sequence),
            @"category": category,
            @"message": message
        };
        [entries addObject:entry];

        [entries sortUsingComparator:^NSComparisonResult(NSDictionary<NSString *, id> *lhs, NSDictionary<NSString *, id> *rhs) {
            double leftTs = [lhs[@"ts"] doubleValue];
            double rightTs = [rhs[@"ts"] doubleValue];
            if (leftTs > rightTs) return NSOrderedAscending;
            if (leftTs < rightTs) return NSOrderedDescending;

            unsigned long long leftSeq = [lhs[@"seq"] unsignedLongLongValue];
            unsigned long long rightSeq = [rhs[@"seq"] unsignedLongLongValue];
            if (leftSeq > rightSeq) return NSOrderedAscending;
            if (leftSeq < rightSeq) return NSOrderedDescending;
            return NSOrderedSame;
        }];

        if (entries.count > kYTMUDebugLogMaxEntries) {
            NSRange overflow = NSMakeRange(kYTMUDebugLogMaxEntries, entries.count - kYTMUDebugLogMaxEntries);
            [entries removeObjectsInRange:overflow];
        }

        prefs[kYTMUDebugLogEntriesKey] = [entries copy];
        [defaults setObject:prefs forKey:kYTMUPrefsKey];
    }
}

+ (NSArray<NSString *> *)formattedEntriesWithLimit:(NSUInteger)limit {
    NSArray<NSDictionary<NSString *, id> *> *entries = [self sortedEntries];
    if (limit > 0 && entries.count > limit) {
        entries = [entries subarrayWithRange:NSMakeRange(0, limit)];
    }

    static NSDateFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.dateFormat = @"HH:mm:ss";
    });

    NSMutableArray<NSString *> *lines = [NSMutableArray arrayWithCapacity:entries.count];
    for (NSDictionary<NSString *, id> *entry in entries) {
        NSString *category = [entry[@"category"] isKindOfClass:[NSString class]] ? entry[@"category"] : @"General";
        NSString *message = [entry[@"message"] isKindOfClass:[NSString class]] ? entry[@"message"] : @"";
        NSDate *date = [NSDate dateWithTimeIntervalSince1970:[entry[@"ts"] doubleValue]];
        NSString *timeText = [formatter stringFromDate:date];
        [lines addObject:[NSString stringWithFormat:@"[%@] [%@] %@", timeText, category, message]];
    }
    return lines;
}

+ (void)clear {
    @synchronized(self) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        NSMutableDictionary *prefs = [self mutablePrefs];
        [prefs removeObjectForKey:kYTMUDebugLogEntriesKey];
        [prefs removeObjectForKey:kYTMUDebugLogSequenceKey];
        [defaults setObject:prefs forKey:kYTMUPrefsKey];
    }
}

@end
