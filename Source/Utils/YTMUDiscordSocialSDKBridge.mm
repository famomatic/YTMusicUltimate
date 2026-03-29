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
#include <optional>
#include <string>
#endif

static const uint64_t kYTMUDiscordFixedApplicationID = 1487516478876942502ULL;

@interface YTMUDiscordSocialSDKBridge ()
@property (nonatomic, strong) dispatch_queue_t queue;
@property (nonatomic, strong, nullable) dispatch_source_t callbackTimer;
@property (nonatomic, copy) NSString *activeToken;
@property (nonatomic, copy) NSString *pendingTitle;
@property (nonatomic, copy) NSString *pendingArtist;
@property (nonatomic, copy) NSString *pendingAlbum;
@property (nonatomic, copy) NSString *pendingArtworkURL;
@property (nonatomic, copy) NSString *pendingTrackURL;
@property (nonatomic, copy) NSString *pendingArtistURL;
@property (nonatomic, copy) NSString *pendingAlbumURL;
@property (nonatomic, assign) NSTimeInterval pendingElapsed;
@property (nonatomic, assign) NSTimeInterval pendingDuration;
@property (nonatomic, assign) BOOL pendingPaused;
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
        _pendingTitle = @"";
        _pendingArtist = @"";
        _pendingAlbum = @"";
        _pendingArtworkURL = @"";
        _pendingTrackURL = @"";
        _pendingArtistURL = @"";
        _pendingAlbumURL = @"";
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

static NSString *YTMUValidatedHTTPURL(NSString *value) {
    if (value.length == 0 || value.length > 256) return @"";
    NSURLComponents *components = [NSURLComponents componentsWithString:value];
    NSString *scheme = components.scheme.lowercaseString;
    if (!([scheme isEqualToString:@"https"] || [scheme isEqualToString:@"http"])) return @"";
    if (components.host.length == 0) return @"";
    return value;
}

static NSDictionary *YTMUPresencePrefsSnapshot(void) {
    NSDictionary *prefs = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"YTMUltimate"];
    if (![prefs isKindOfClass:[NSDictionary class]]) return @{};
    return prefs;
}

static BOOL YTMUPresencePrefBool(NSDictionary *prefs, NSString *key, BOOL fallback) {
    id value = prefs[key];
    if (!value) return fallback;
    return [value boolValue];
}

static NSArray<NSString *> *YTMUPresenceTextOrder(NSDictionary *prefs) {
    NSArray *fallback = @[@"title", @"artist", @"album"];
    id raw = prefs[@"discordPresenceTextOrder"];
    if (![raw isKindOfClass:[NSArray class]]) return fallback;

    NSMutableOrderedSet<NSString *> *ordered = [NSMutableOrderedSet orderedSet];
    for (id item in (NSArray *)raw) {
        if (![item isKindOfClass:[NSString class]]) continue;
        NSString *token = (NSString *)item;
        if ([token isEqualToString:@"title"] || [token isEqualToString:@"artist"] || [token isEqualToString:@"album"]) {
            [ordered addObject:token];
        }
    }

    for (NSString *required in fallback) {
        if (![ordered containsObject:required]) {
            [ordered addObject:required];
        }
    }

    return ordered.array;
}

- (void)ensureClient {
    if (_client) return;

    _client = std::make_shared<discordpp::Client>();
    _client->SetApplicationId(kYTMUDiscordFixedApplicationID);

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

    NSString *title = self.pendingTitle ?: @"";
    NSString *artist = self.pendingArtist ?: @"";
    NSString *album = self.pendingAlbum ?: @"";
    NSString *artworkURL = self.pendingArtworkURL ?: @"";
    NSString *trackURL = self.pendingTrackURL ?: @"";
    NSString *artistURL = self.pendingArtistURL ?: @"";
    NSString *albumURL = self.pendingAlbumURL ?: @"";
    NSTimeInterval elapsed = self.pendingElapsed;
    NSTimeInterval duration = self.pendingDuration;
    BOOL paused = self.pendingPaused;

    self.hasPendingPresence = NO;
    self.pendingTitle = @"";
    self.pendingArtist = @"";
    self.pendingAlbum = @"";
    self.pendingArtworkURL = @"";
    self.pendingTrackURL = @"";
    self.pendingArtistURL = @"";
    self.pendingAlbumURL = @"";
    self.pendingElapsed = 0;
    self.pendingDuration = 0;
    self.pendingPaused = NO;

    [self updateRichPresenceWithTitle:title
                               artist:artist
                                album:album
                           artworkURL:artworkURL
                             trackURL:trackURL
                            artistURL:artistURL
                             albumURL:albumURL
                               paused:paused
                              elapsed:elapsed
                             duration:duration
                           completion:nil];
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

- (void)updateRichPresenceWithTitle:(NSString *)title
                             artist:(NSString *)artist
                              album:(NSString *)album
                         artworkURL:(NSString *)artworkURL
                           trackURL:(NSString *)trackURL
                          artistURL:(NSString *)artistURL
                           albumURL:(NSString *)albumURL
                             paused:(BOOL)paused
                            elapsed:(NSTimeInterval)elapsed
                           duration:(NSTimeInterval)duration
                         completion:(void (^ _Nullable)(BOOL success, NSString *message))completion {
    void (^completionCopy)(BOOL, NSString *) = [completion copy];

#if !YTMU_DISCORD_SOCIAL_SDK
    if (completionCopy) completionCopy(NO, [self availabilityMessage]);
    return;
#else
    NSString *safeTitle = title ?: @"";
    NSString *safeArtist = artist ?: @"";
    NSString *safeAlbum = album ?: @"";
    NSString *safeArtworkURL = artworkURL ?: @"";
    NSString *safeTrackURL = YTMUValidatedHTTPURL(trackURL ?: @"");
    NSString *safeArtistURL = YTMUValidatedHTTPURL(artistURL ?: @"");
    NSString *safeAlbumURL = YTMUValidatedHTTPURL(albumURL ?: @"");
    NSTimeInterval safeElapsed = MAX(0, elapsed);
    NSTimeInterval safeDuration = MAX(0, duration);

    dispatch_async(self.queue, ^{
        if (!_client || !self.tokenLoaded) {
            self.pendingTitle = safeTitle;
            self.pendingArtist = safeArtist;
            self.pendingAlbum = safeAlbum;
            self.pendingArtworkURL = safeArtworkURL;
            self.pendingTrackURL = safeTrackURL;
            self.pendingArtistURL = safeArtistURL;
            self.pendingAlbumURL = safeAlbumURL;
            self.pendingElapsed = safeElapsed;
            self.pendingDuration = safeDuration;
            self.pendingPaused = paused;
            self.hasPendingPresence = YES;
            if (completionCopy) completionCopy(NO, @"Discord Social SDK is not connected yet.");
            return;
        }

        if (!self.isReady) {
            self.pendingTitle = safeTitle;
            self.pendingArtist = safeArtist;
            self.pendingAlbum = safeAlbum;
            self.pendingArtworkURL = safeArtworkURL;
            self.pendingTrackURL = safeTrackURL;
            self.pendingArtistURL = safeArtistURL;
            self.pendingAlbumURL = safeAlbumURL;
            self.pendingElapsed = safeElapsed;
            self.pendingDuration = safeDuration;
            self.pendingPaused = paused;
            self.hasPendingPresence = YES;
            if (!self.isConnecting) {
                self.isConnecting = YES;
                _client->Connect();
            }
            if (completionCopy) completionCopy(YES, @"Discord Social SDK connection pending; presence queued.");
            return;
        }

        NSDictionary *prefs = YTMUPresencePrefsSnapshot();
        BOOL showText = YTMUPresencePrefBool(prefs, @"discordPresenceShowText", YES);
        BOOL showTitle = YTMUPresencePrefBool(prefs, @"discordPresenceShowTitle", YES);
        BOOL showArtist = YTMUPresencePrefBool(prefs, @"discordPresenceShowArtist", YES);
        BOOL showAlbum = YTMUPresencePrefBool(prefs, @"discordPresenceShowAlbum", YES);
        BOOL enableTextLinks = YTMUPresencePrefBool(prefs, @"discordPresenceEnableTextLinks", YES);
        BOOL enableArtworkLink = YTMUPresencePrefBool(prefs, @"discordPresenceEnableArtworkLink", YES);
        BOOL showButtons = YTMUPresencePrefBool(prefs, @"discordPresenceShowButtons", YES);
        BOOL linkTitle = YTMUPresencePrefBool(prefs, @"discordPresenceLinkTitle", YES);
        BOOL linkArtist = YTMUPresencePrefBool(prefs, @"discordPresenceLinkArtist", YES);
        BOOL linkAlbum = YTMUPresencePrefBool(prefs, @"discordPresenceLinkAlbum", YES);
        NSArray<NSString *> *textOrder = YTMUPresenceTextOrder(prefs);

        NSDictionary<NSString *, NSDictionary *> *allItems = @{
            @"title": @{@"text": safeTitle ?: @"", @"url": safeTrackURL ?: @"", @"show": @(showTitle), @"link": @(linkTitle)},
            @"artist": @{@"text": safeArtist ?: @"", @"url": safeArtistURL ?: @"", @"show": @(showArtist), @"link": @(linkArtist)},
            @"album": @{@"text": safeAlbum ?: @"", @"url": safeAlbumURL ?: @"", @"show": @(showAlbum), @"link": @(linkAlbum)}
        };

        NSMutableArray<NSDictionary *> *visibleItems = [NSMutableArray array];
        if (showText) {
            for (NSString *itemKey in textOrder) {
                NSDictionary *item = allItems[itemKey];
                if (![item isKindOfClass:[NSDictionary class]]) continue;
                if (![item[@"show"] boolValue]) continue;
                NSString *text = item[@"text"];
                if (![text isKindOfClass:[NSString class]] || text.length == 0) continue;
                [visibleItems addObject:item];
            }
        }

        NSString *detailsText = visibleItems.count > 0 ? (NSString *)visibleItems[0][@"text"] : @"";
        NSString *statePrimary = visibleItems.count > 1 ? (NSString *)visibleItems[1][@"text"] : @"";
        NSString *stateSecondary = visibleItems.count > 2 ? (NSString *)visibleItems[2][@"text"] : @"";
        NSString *stateText = @"";
        if (statePrimary.length > 0 && stateSecondary.length > 0) {
            stateText = [NSString stringWithFormat:@"%@\n%@", statePrimary, stateSecondary];
        } else if (statePrimary.length > 0) {
            stateText = statePrimary;
        } else if (stateSecondary.length > 0) {
            stateText = stateSecondary;
        }
        if (detailsText.length > 128) detailsText = [detailsText substringToIndex:128];
        if (stateText.length > 128) stateText = [stateText substringToIndex:128];

        NSString *detailsURL = @"";
        NSString *stateURL = @"";
        if (enableTextLinks) {
            if (visibleItems.count > 0 && [visibleItems[0][@"link"] boolValue]) {
                detailsURL = visibleItems[0][@"url"] ?: @"";
            }
            if (visibleItems.count > 1 && [visibleItems[1][@"link"] boolValue]) {
                stateURL = visibleItems[1][@"url"] ?: @"";
            } else if (visibleItems.count > 2 && [visibleItems[2][@"link"] boolValue]) {
                // SDK exposes a single URL for the state field, so we use the next visible linked line.
                stateURL = visibleItems[2][@"url"] ?: @"";
            }
        }

        discordpp::Activity activity;
        activity.SetType(discordpp::ActivityTypes::Listening);
        activity.SetName(YTMUToStdString(@"YouTube Music"));
        if (detailsText.length > 0) {
            activity.SetDetails(std::make_optional(YTMUToStdString(detailsText)));
        }
        if (stateText.length > 0) {
            activity.SetState(std::make_optional(YTMUToStdString(stateText)));
        }
        if (detailsURL.length > 0) {
            activity.SetDetailsUrl(std::make_optional(YTMUToStdString(detailsURL)));
        }
        if (stateURL.length > 0) {
            activity.SetStateUrl(std::make_optional(YTMUToStdString(stateURL)));
        }

        discordpp::ActivityAssets assets;
        if (safeArtworkURL.length > 0) {
            assets.SetLargeImage(std::make_optional(YTMUToStdString(safeArtworkURL)));
        }
        if (enableArtworkLink && safeTrackURL.length > 0) {
            assets.SetLargeUrl(std::make_optional(YTMUToStdString(safeTrackURL)));
        }
        if (showAlbum && safeAlbum.length > 0) {
            assets.SetLargeText(std::make_optional(YTMUToStdString(safeAlbum)));
        }
        assets.SetSmallImage(std::make_optional(std::string(paused ? "pause" : "play")));
        assets.SetSmallText(std::make_optional(std::string(paused ? "Paused" : "Playing")));
        activity.SetAssets(std::make_optional(assets));

        if (showButtons && safeTrackURL.length > 0) {
            discordpp::ActivityButton listenButton;
            listenButton.SetLabel(YTMUToStdString(@"이 노래 듣기"));
            listenButton.SetUrl(YTMUToStdString(safeTrackURL));
            activity.AddButton(listenButton);
        }

        if (showButtons && safeAlbumURL.length > 0 && ![safeAlbumURL isEqualToString:safeTrackURL]) {
            discordpp::ActivityButton albumButton;
            albumButton.SetLabel(YTMUToStdString(@"앨범 보기"));
            albumButton.SetUrl(YTMUToStdString(safeAlbumURL));
            activity.AddButton(albumButton);
        }

        if (!paused && safeDuration > 0) {
            NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
            uint64_t start = (uint64_t)llround(now - safeElapsed);
            uint64_t end = (uint64_t)llround((now - safeElapsed) + safeDuration);
            if (end > start) {
                discordpp::ActivityTimestamps timestamps;
                timestamps.SetStart(start);
                timestamps.SetEnd(end);
                activity.SetTimestamps(std::make_optional(timestamps));
            }
        }

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
        self.pendingTitle = @"";
        self.pendingArtist = @"";
        self.pendingAlbum = @"";
        self.pendingArtworkURL = @"";
        self.pendingTrackURL = @"";
        self.pendingArtistURL = @"";
        self.pendingAlbumURL = @"";
        self.pendingElapsed = 0;
        self.pendingDuration = 0;
        self.pendingPaused = NO;

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
        self.pendingTitle = @"";
        self.pendingArtist = @"";
        self.pendingAlbum = @"";
        self.pendingArtworkURL = @"";
        self.pendingTrackURL = @"";
        self.pendingArtistURL = @"";
        self.pendingAlbumURL = @"";
        self.pendingElapsed = 0;
        self.pendingDuration = 0;
        self.pendingPaused = NO;
        self.activeToken = @"";
        self.tokenLoaded = NO;
        self.isConnecting = NO;
        self.isReady = NO;
    });
#endif
}

@end
