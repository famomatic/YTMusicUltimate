#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface YTMUDiscordSocialSDKBridge : NSObject

+ (instancetype)sharedBridge;
- (BOOL)isAvailable;
- (NSString *)availabilityMessage;

- (void)connectWithAccessToken:(NSString *)accessToken completion:(void (^ _Nullable)(BOOL success, NSString *message))completion;
- (void)updateRichPresenceWithTitle:(NSString *)title
                             artist:(NSString *)artist
                              album:(NSString *)album
                         artworkURL:(NSString *)artworkURL
                             paused:(BOOL)paused
                            elapsed:(NSTimeInterval)elapsed
                           duration:(NSTimeInterval)duration
                         completion:(void (^ _Nullable)(BOOL success, NSString *message))completion;
- (void)clearRichPresenceWithCompletion:(void (^ _Nullable)(BOOL success, NSString *message))completion;
- (void)disconnect;

@end

NS_ASSUME_NONNULL_END
