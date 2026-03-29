#import "YTMUDiscordSocialSDKBridge.h"
#import "YTMUDebugLogger.h"

#if YTMU_DISCORD_SOCIAL_SDK
#define DISCORDPP_IMPLEMENTATION
#if __has_include(<discord_partner_sdk/discordpp.h>)
#include <discord_partner_sdk/discordpp.h>
#elif __has_include(<discordpp.h>)
#include <discordpp.h>
#else
#error Discord Social SDK header not found. Ensure include path contains discordpp.h.
#endif
#include <memory>
#include <string>
#endif

@interface YTMUDiscordSocialSDKBridge ()
@property (nonatomic, strong) dispatch_queue_t queue;
@property (nonatomic, strong, nullable) dispatch_source_t callbackTimer;
@property (nonatomic, copy) NSString *activeToken;
@property (nonatomic, copy) NSString *pendingDetails;
@property (nonatomic, copy) NSString *pendingState;
@property (nonatomic, assign) BOOL hasPendingPresence;
@property (nonatomic, assign) BOOL isReady;
@property (nonatomic, assign) BOOL isConnecting;
@property (nonatomic, assign) BOOL tokenLoaded;
@end

@implementation YTMUDiscordSocialSDKBridge {
#if YTMU_DISCORD_SOCIAL_SDK
    std::shared_ptr<discordpp::Client> _client;
#endif
}

+ (instancetype)sharedBridge {
    static YTMUDiscordSocialSDKBridge *bridge = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        bridge = [[YTMUDiscordSocialSDKBridge alloc] init];
    });
    return bridge;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _queue = dispatch_queue_create("dev.ginsu.ytmu.discord.socialsdk", DISPATCH_QUEUE_SERIAL);
        _activeToken = @"";
        _pendingDetails = @"";
        _pendingState = @"";
    }
    return self;
}

- (BOOL)isAvailable {
#if YTMU_DISCORD_SOCIAL_SDK
    return YES;
#else
    return NO;
#endif
}

- (NSString *)availabilityMessage {
    if ([self isAvailable]) return @"Discord Social SDK is available.";
    return @"Discord Social SDK is not linked. Build with ENABLE_DISCORD_SOCIAL_SDK=1 and provide discord_partner_sdk.xcframework.";
}

#if YTMU_DISCORD_SOCIAL_SDK
static std::string YTMUToStdString(NSString *value) {
    if (value.length == 0) return std::string();
    return std::string([value UTF8String]);
}

- (void)ensureClient {
    if (_client) return;

    _client = std::make_shared<discordpp::Client>();

    __weak YTMUDiscordSocialSDKBridge *weakSelf = self;
    _client->SetStatusChangedCallback([weakSelf](discordpp::Client::Status status, discordpp::Client::Error error, int32_t errorDetail) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong YTMUDiscordSocialSDKBridge *strongSelf = weakSelf;
            if (!strongSelf) return;
            [strongSelf handleStatus:status error:error detail:errorDetail];
        });
    });

    [self startCallbackPumpIfNeeded];
    [YTMUDebugLogger logCategory:@"Discord" message:@"Discord Social SDK client initialized."];
}

- (void)startCallbackPumpIfNeeded {
    if (self.callbackTimer) return;

    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, self.queue);
    if (!timer) return;

    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 0), 50ull * NSEC_PER_MSEC, 5ull * NSEC_PER_MSEC);
    dispatch_source_set_event_handler(timer, ^{
        discordpp::RunCallbacks();
    });
    dispatch_resume(timer);
    self.callbackTimer = timer;
}

- (void)handleStatus:(discordpp::Client::Status)status error:(discordpp::Client::Error)error detail:(int32_t)errorDetail {
    dispatch_async(self.queue, ^{
        if (status == discordpp::Client::Status::Ready) {
            self.isReady = YES;
            self.isConnecting = NO;
            [YTMUDebugLogger logCategory:@"Discord" message:@"Discord Social SDK status: Ready."];
            [self flushPendingPresence];
            return;
        }

        if (error != discordpp::Client::Error::None) {
            self.isReady = NO;
            self.isConnecting = NO;
            NSString *message = [NSString stringWithFormat:@"Discord Social SDK status error: %s (%d).",
                                 discordpp::Client::ErrorToString(error).c_str(),
                                 (int)errorDetail];
            [YTMUDebugLogger logCategory:@"Discord" message:message];
        }
    });
}

- (void)flushPendingPresence {
    if (!self.hasPendingPresence || !self.isReady || !_client) return;

    NSString *details = self.pendingDetails ?: @"";
    NSString *state = self.pendingState ?: @"";
    self.hasPendingPresence = NO;
    self.pendingDetails = @"";
    self.pendingState = @"";

    [self updateRichPresenceWithDetails:details state:state completion:nil];
}
#endif

- (void)connectWithAccessToken:(NSString *)accessToken completion:(void (^ _Nullable)(BOOL success, NSString *message))completion {
    void (^completionCopy)(BOOL, NSString *) = [completion copy];

#if !YTMU_DISCORD_SOCIAL_SDK
    if (completionCopy) completionCopy(NO, [self availabilityMessage]);
    return;
#else
    NSString *token = [accessToken copy] ?: @"";
    if (token.length == 0) {
        if (completionCopy) completionCopy(NO, @"Discord Social SDK connection failed: access token is empty.");
        return;
    }

    dispatch_async(self.queue, ^{
        [self ensureClient];

        if (self.tokenLoaded && [self.activeToken isEqualToString:token]) {
            if (!self.isReady && !self.isConnecting) {
                self.isConnecting = YES;
                _client->Connect();
            }
            if (completionCopy) completionCopy(YES, @"Discord Social SDK token is already active.");
            return;
        }

        self.activeToken = token;
        self.tokenLoaded = NO;
        self.isReady = NO;
        self.isConnecting = YES;

        std::string tokenStd = YTMUToStdString(token);
        __weak YTMUDiscordSocialSDKBridge *weakSelf = self;
        _client->UpdateToken(discordpp::AuthorizationTokenType::Bearer, tokenStd, [weakSelf, completionCopy](discordpp::ClientResult result) {
            dispatch_queue_t callbackQueue = weakSelf ? weakSelf.queue : dispatch_get_main_queue();
            dispatch_async(callbackQueue, ^{
                __strong YTMUDiscordSocialSDKBridge *strongSelf = weakSelf;
                if (!strongSelf) {
                    if (completionCopy) completionCopy(NO, @"Discord Social SDK connection callback was released.");
                    return;
                }

                if (!result.Successful()) {
                    strongSelf.tokenLoaded = NO;
                    strongSelf.isConnecting = NO;
                    if (completionCopy) completionCopy(NO, @"Discord Social SDK token update failed.");
                    return;
                }

                strongSelf.tokenLoaded = YES;
                strongSelf.isConnecting = YES;
                strongSelf->_client->Connect();
                if (completionCopy) completionCopy(YES, @"Discord Social SDK token updated.");
            });
        });
    });
#endif
}

- (void)updateRichPresenceWithDetails:(NSString *)details state:(NSString *)state completion:(void (^ _Nullable)(BOOL success, NSString *message))completion {
    void (^completionCopy)(BOOL, NSString *) = [completion copy];

#if !YTMU_DISCORD_SOCIAL_SDK
    if (completionCopy) completionCopy(NO, [self availabilityMessage]);
    return;
#else
    NSString *safeDetails = details ?: @"";
    NSString *safeState = state ?: @"";

    dispatch_async(self.queue, ^{
        if (!_client || !self.tokenLoaded) {
            self.pendingDetails = safeDetails;
            self.pendingState = safeState;
            self.hasPendingPresence = YES;
            if (completionCopy) completionCopy(NO, @"Discord Social SDK is not connected yet.");
            return;
        }

        if (!self.isReady) {
            self.pendingDetails = safeDetails;
            self.pendingState = safeState;
            self.hasPendingPresence = YES;
            if (!self.isConnecting) {
                self.isConnecting = YES;
                _client->Connect();
            }
            if (completionCopy) completionCopy(YES, @"Discord Social SDK connection pending; presence queued.");
            return;
        }

        discordpp::Activity activity;
        activity.SetType(discordpp::ActivityTypes::Playing);
        activity.SetDetails(YTMUToStdString(safeDetails));
        activity.SetState(YTMUToStdString(safeState));

        __weak YTMUDiscordSocialSDKBridge *weakSelf = self;
        _client->UpdateRichPresence(activity, [weakSelf, completionCopy](discordpp::ClientResult result) {
            dispatch_queue_t callbackQueue = weakSelf ? weakSelf.queue : dispatch_get_main_queue();
            dispatch_async(callbackQueue, ^{
                __strong YTMUDiscordSocialSDKBridge *strongSelf = weakSelf;
                if (!strongSelf) {
                    if (completionCopy) completionCopy(NO, @"Discord Rich Presence callback was released.");
                    return;
                }

                if (!result.Successful()) {
                    if (completionCopy) completionCopy(NO, @"Discord Rich Presence update failed.");
                    return;
                }

                if (completionCopy) completionCopy(YES, @"Discord Rich Presence updated.");
            });
        });
    });
#endif
}

- (void)clearRichPresenceWithCompletion:(void (^ _Nullable)(BOOL success, NSString *message))completion {
    void (^completionCopy)(BOOL, NSString *) = [completion copy];

#if !YTMU_DISCORD_SOCIAL_SDK
    if (completionCopy) completionCopy(NO, [self availabilityMessage]);
    return;
#else
    dispatch_async(self.queue, ^{
        self.hasPendingPresence = NO;
        self.pendingDetails = @"";
        self.pendingState = @"";

        if (!_client || !self.tokenLoaded) {
            if (completionCopy) completionCopy(YES, @"Discord Social SDK clear skipped: not connected.");
            return;
        }

        _client->ClearRichPresence();
        if (completionCopy) {
            completionCopy(YES, @"Discord Rich Presence clear requested.");
        }
    });
#endif
}

- (void)disconnect {
#if !YTMU_DISCORD_SOCIAL_SDK
    return;
#else
    dispatch_async(self.queue, ^{
        self.hasPendingPresence = NO;
        self.pendingDetails = @"";
        self.pendingState = @"";
        self.activeToken = @"";
        self.tokenLoaded = NO;
        self.isConnecting = NO;
        self.isReady = NO;
    });
#endif
}

@end
