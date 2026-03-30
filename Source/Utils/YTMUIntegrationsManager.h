#import <Foundation/Foundation.h>

@class YTPlayerViewController;

NS_ASSUME_NONNULL_BEGIN

@interface YTMUIntegrationsManager : NSObject
+ (instancetype)sharedManager;
+ (void)initializeDefaultSettings;

- (nullable NSURL *)discordAuthorizationURLWithError:(NSError * _Nullable * _Nullable)error;
- (void)exchangeDiscordCode:(NSString *)code completion:(void (^)(BOOL success, NSString *message))completion;
- (void)disconnectDiscord;

- (void)startLastFMLoginWithCompletion:(void (^)(BOOL success, NSString *message, NSURL * _Nullable authURL))completion;
- (void)completeLastFMLoginWithCompletion:(void (^)(BOOL success, NSString *message))completion;

- (void)trackDidActivateForPlayer:(YTPlayerViewController *)player;
- (void)trackTimeDidChangeForPlayer:(YTPlayerViewController *)player;
- (void)trackPlaybackStateDidChangeForPlayer:(YTPlayerViewController *)player;
- (void)clearDiscordPresence;
@end

NS_ASSUME_NONNULL_END
