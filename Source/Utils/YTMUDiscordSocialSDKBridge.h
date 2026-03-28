#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface YTMUDiscordSocialSDKBridge : NSObject

+ (instancetype)sharedBridge;
- (BOOL)isAvailable;
- (NSString *)availabilityMessage;

- (void)connectWithAccessToken:(NSString *)accessToken completion:(void (^ _Nullable)(BOOL success, NSString *message))completion;
- (void)updateRichPresenceWithDetails:(NSString *)details state:(NSString *)state completion:(void (^ _Nullable)(BOOL success, NSString *message))completion;
- (void)clearRichPresenceWithCompletion:(void (^ _Nullable)(BOOL success, NSString *message))completion;
- (void)disconnect;

@end

NS_ASSUME_NONNULL_END
