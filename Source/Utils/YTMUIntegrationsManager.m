#import "YTMUIntegrationsManager.h"
#import "../Headers/YTPlayerViewController.h"
#import "../Headers/YTPlayerResponse.h"
#import "../Headers/YTIPlayerResponse.h"
#import "../Headers/YTIVideoDetails.h"
#import "../Headers/YTIThumbnailDetails.h"
#import "../Headers/YTIThumbnailDetails_Thumbnail.h"
#import "YTMUDebugLogger.h"
#import "YTMUDiscordSocialSDKBridge.h"
#import <CommonCrypto/CommonDigest.h>
#import <Security/Security.h>

static NSString *const kYTMUPrefsKey = @"YTMUltimate";
static NSString *const kYTMUDiscordFixedClientID = @"1487516478876942502";
static NSString *const kYTMUDiscordFixedRedirectURI = @"https://localhost/ytmusicultimate-discord-callback";
static NSString *const kYTMUDiscordFixedOAuthScope = @"identify openid sdk.social_layer_presence";

static NSMutableDictionary *YTMUMutablePrefs(void) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSDictionary *existing = [defaults dictionaryForKey:kYTMUPrefsKey] ?: @{};
    return [NSMutableDictionary dictionaryWithDictionary:existing];
}

static id YTMUValue(NSString *key) {
    return [[NSUserDefaults standardUserDefaults] dictionaryForKey:kYTMUPrefsKey][key];
}

static NSString *YTMUString(NSString *key, NSString *fallback) {
    id value = YTMUValue(key);
    if ([value isKindOfClass:[NSString class]] && [(NSString *)value length] > 0) {
        return (NSString *)value;
    }
    return fallback;
}

static BOOL YTMUBool(NSString *key, BOOL fallback) {
    id value = YTMUValue(key);
    if (!value) return fallback;
    return [value boolValue];
}

static NSInteger YTMUInt(NSString *key, NSInteger fallback) {
    id value = YTMUValue(key);
    if (!value) return fallback;
    return [value integerValue];
}

static void YTMUSetValue(NSString *key, id value) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary *prefs = YTMUMutablePrefs();
    if (value) {
        prefs[key] = value;
    } else {
        [prefs removeObjectForKey:key];
    }
    [defaults setObject:prefs forKey:kYTMUPrefsKey];
}

static NSString *YTMUFormEncodeComponent(NSString *value) {
    if (!value) return @"";
    NSMutableCharacterSet *allowed = [[NSCharacterSet alphanumericCharacterSet] mutableCopy];
    [allowed addCharactersInString:@"-._~"];
    return [value stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: @"";
}

static NSString *YTMUFormEncodedString(NSDictionary<NSString *, NSString *> *params) {
    NSMutableArray<NSString *> *parts = [NSMutableArray arrayWithCapacity:params.count];
    for (NSString *key in params) {
        NSString *value = params[key] ?: @"";
        NSString *encodedKey = YTMUFormEncodeComponent(key);
        NSString *encodedValue = YTMUFormEncodeComponent(value);
        [parts addObject:[NSString stringWithFormat:@"%@=%@", encodedKey, encodedValue]];
    }
    return [parts componentsJoinedByString:@"&"];
}

static NSString *YTMUMD5Hex(NSString *input) {
    const char *cStr = [input UTF8String];
    unsigned char digest[CC_MD5_DIGEST_LENGTH];
    CC_MD5(cStr, (CC_LONG)strlen(cStr), digest);
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_MD5_DIGEST_LENGTH * 2];
    for (NSInteger i = 0; i < CC_MD5_DIGEST_LENGTH; i++) {
        [hex appendFormat:@"%02x", digest[i]];
    }
    return hex;
}

static NSData *YTMUSHA256(NSData *input) {
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(input.bytes, (CC_LONG)input.length, digest);
    return [NSData dataWithBytes:digest length:CC_SHA256_DIGEST_LENGTH];
}

static NSString *YTMUBase64URL(NSData *data) {
    NSString *base64 = [data base64EncodedStringWithOptions:0];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"=" withString:@""];
    return base64;
}

static NSString *YTMURandomString(NSInteger length) {
    NSMutableData *data = [NSMutableData dataWithLength:length];
    OSStatus status = SecRandomCopyBytes(kSecRandomDefault, length, data.mutableBytes);
    if (status != errSecSuccess) {
        return [[NSUUID UUID].UUIDString stringByReplacingOccurrencesOfString:@"-" withString:@""];
    }

    const char charset[] = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~";
    NSMutableString *output = [NSMutableString stringWithCapacity:length];
    const unsigned char *bytes = data.bytes;
    for (NSInteger i = 0; i < length; i++) {
        [output appendFormat:@"%c", charset[bytes[i] % (sizeof(charset) - 1)]];
    }
    return output;
}

static NSString *YTMUSafeStringFromCandidateKeyPaths(id object, NSArray<NSString *> *candidateKeyPaths) {
    if (!object || candidateKeyPaths.count == 0) return @"";
    for (NSString *keyPath in candidateKeyPaths) {
        @try {
            id value = [object valueForKeyPath:keyPath];
            if ([value isKindOfClass:[NSString class]] && [(NSString *)value length] > 0) {
                return (NSString *)value;
            }
        } @catch (__unused NSException *exception) {
        }
    }
    return @"";
}

static NSString *YTMUBestThumbnailURL(YTIThumbnailDetails *thumbnailDetails) {
    if (!thumbnailDetails) return @"";
    NSArray *thumbnails = [thumbnailDetails.thumbnailsArray isKindOfClass:[NSArray class]] ? (NSArray *)thumbnailDetails.thumbnailsArray : @[];
    NSString *bestURL = @"";
    unsigned int bestWidth = 0;

    for (id item in thumbnails) {
        if (![item isKindOfClass:[YTIThumbnailDetails_Thumbnail class]]) continue;
        YTIThumbnailDetails_Thumbnail *thumbnail = (YTIThumbnailDetails_Thumbnail *)item;
        if (![thumbnail.URL isKindOfClass:[NSString class]] || thumbnail.URL.length == 0) continue;
        if (thumbnail.width >= bestWidth) {
            bestWidth = thumbnail.width;
            bestURL = thumbnail.URL;
        }
    }

    return bestURL ?: @"";
}

static BOOL YTMUScopeContains(NSString *scopes, NSString *requiredScope) {
    if (scopes.length == 0 || requiredScope.length == 0) return NO;
    NSArray<NSString *> *tokens = [scopes componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    for (NSString *token in tokens) {
        if ([token isEqualToString:requiredScope]) {
            return YES;
        }
    }
    return NO;
}

static BOOL YTMUCanWriteDiscordProfileStatus(NSString *scopes) {
    return YTMUScopeContains(scopes, @"sdk.social_layer_presence");
}

@interface YTMUIntegrationsManager ()
@property (nonatomic, strong) dispatch_queue_t queue;
@property (nonatomic, copy) NSString *currentVideoID;
@property (nonatomic, copy) NSString *currentTrackTitle;
@property (nonatomic, copy) NSString *currentTrackArtist;
@property (nonatomic, copy) NSString *currentTrackAlbum;
@property (nonatomic, copy) NSString *currentTrackArtworkURL;
@property (nonatomic, assign) NSTimeInterval currentTrackDuration;
@property (nonatomic, assign) NSTimeInterval currentTrackStartTimestamp;
@property (nonatomic, assign) NSTimeInterval lastDiscordUpdate;
@property (nonatomic, assign) NSTimeInterval lastObservedPlaybackTime;
@property (nonatomic, assign) BOOL currentPlaybackPaused;
@property (nonatomic, assign) BOOL currentTrackScrobbled;
@property (nonatomic, copy) NSString *lastDiscordStatusPayload;
@end

@implementation YTMUIntegrationsManager

+ (instancetype)sharedManager {
    static YTMUIntegrationsManager *manager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [[YTMUIntegrationsManager alloc] init];
    });
    return manager;
}

+ (void)initializeDefaultSettings {
    NSDictionary *defaults = @{
        @"offlineDownloadsSearch": @YES,
        @"discordPresenceEnabled": @NO,
        @"discordClientID": kYTMUDiscordFixedClientID,
        @"discordOAuthScope": kYTMUDiscordFixedOAuthScope,
        @"discordAuthorizedScope": @"",
        @"discordPresenceLastError": @"",
        @"discordRedirectURI": kYTMUDiscordFixedRedirectURI,
        @"lastfmScrobbleEnabled": @NO,
        @"lastfmUpdateNowPlaying": @YES,
        @"lastfmMinPercent": @50,
        @"lastfmMinSeconds": @30
    };

    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary *prefs = YTMUMutablePrefs();

    for (NSString *key in defaults) {
        if (!prefs[key]) {
            prefs[key] = defaults[key];
        }
    }

    prefs[@"discordClientID"] = kYTMUDiscordFixedClientID;
    prefs[@"discordOAuthScope"] = kYTMUDiscordFixedOAuthScope;
    prefs[@"discordRedirectURI"] = kYTMUDiscordFixedRedirectURI;

    [userDefaults setObject:prefs forKey:kYTMUPrefsKey];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _queue = dispatch_queue_create("dev.ginsu.ytmu.integrations", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

#pragma mark - Discord OAuth2
- (nullable NSURL *)discordAuthorizationURLWithError:(NSError *__autoreleasing  _Nullable * _Nullable)error {
    NSString *clientID = kYTMUDiscordFixedClientID;
    NSString *redirectURI = kYTMUDiscordFixedRedirectURI;
    NSString *oauthScope = kYTMUDiscordFixedOAuthScope;
    if (clientID.length == 0) {
        [YTMUDebugLogger logCategory:@"Discord" message:@"OAuth URL generation failed: client ID is empty."];
        if (error) {
            *error = [NSError errorWithDomain:@"YTMUIntegrations" code:100 userInfo:@{NSLocalizedDescriptionKey: @"Discord Client ID is empty."}];
        }
        return nil;
    }

    NSString *codeVerifier = YTMURandomString(64);
    NSData *challengeData = YTMUSHA256([codeVerifier dataUsingEncoding:NSUTF8StringEncoding]);
    NSString *codeChallenge = YTMUBase64URL(challengeData);

    YTMUSetValue(@"discordPKCEVerifier", codeVerifier);

    NSURLComponents *components = [NSURLComponents componentsWithString:@"https://discord.com/oauth2/authorize"];
    components.queryItems = @[
        [NSURLQueryItem queryItemWithName:@"response_type" value:@"code"],
        [NSURLQueryItem queryItemWithName:@"client_id" value:clientID],
        [NSURLQueryItem queryItemWithName:@"scope" value:oauthScope],
        [NSURLQueryItem queryItemWithName:@"redirect_uri" value:redirectURI],
        [NSURLQueryItem queryItemWithName:@"prompt" value:@"consent"],
        [NSURLQueryItem queryItemWithName:@"code_challenge_method" value:@"S256"],
        [NSURLQueryItem queryItemWithName:@"code_challenge" value:codeChallenge]
    ];

    [YTMUDebugLogger logCategory:@"Discord" message:[NSString stringWithFormat:@"OAuth URL generated. scope=%@ redirect=%@", oauthScope, redirectURI]];
    return components.URL;
}

- (void)exchangeDiscordCode:(NSString *)code completion:(void (^)(BOOL success, NSString *message))completion {
    NSString *clientID = kYTMUDiscordFixedClientID;
    NSString *redirectURI = kYTMUDiscordFixedRedirectURI;
    NSString *codeVerifier = YTMUString(@"discordPKCEVerifier", @"");
    [YTMUDebugLogger logCategory:@"Discord" message:[NSString stringWithFormat:@"Token exchange requested. code_len=%lu", (unsigned long)code.length]];

    if (clientID.length == 0 || code.length == 0 || codeVerifier.length == 0) {
        [YTMUDebugLogger logCategory:@"Discord" message:@"Token exchange blocked: OAuth2 parameters incomplete."];
        completion(NO, @"OAuth2 parameters are incomplete.");
        return;
    }

    NSDictionary<NSString *, NSString *> *params = @{
        @"client_id": clientID,
        @"grant_type": @"authorization_code",
        @"code": code,
        @"redirect_uri": redirectURI,
        @"code_verifier": codeVerifier
    };

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://discord.com/api/oauth2/token"]];
    request.HTTPMethod = @"POST";
    request.HTTPBody = [[YTMUFormEncodedString(params) dataUsingEncoding:NSUTF8StringEncoding] copy];
    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];

    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger statusCode = [response isKindOfClass:[NSHTTPURLResponse class]] ? [(NSHTTPURLResponse *)response statusCode] : 0;
        if (error || !data) {
            [YTMUDebugLogger logCategory:@"Discord" message:[NSString stringWithFormat:@"Token exchange failed. status=%ld error=%@", (long)statusCode, error.localizedDescription ?: @"unknown"]];
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO, error.localizedDescription ?: @"Token exchange failed.");
            });
            return;
        }

        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSString *accessToken = json[@"access_token"];
        NSString *refreshToken = json[@"refresh_token"];
        NSNumber *expiresIn = json[@"expires_in"];
        NSString *authorizedScope = [json[@"scope"] isKindOfClass:[NSString class]] ? json[@"scope"] : @"";

        if (accessToken.length == 0) {
            NSString *errorDescription = json[@"error_description"] ?: json[@"error"] ?: @"Token exchange failed.";
            [YTMUDebugLogger logCategory:@"Discord" message:[NSString stringWithFormat:@"Token exchange denied. status=%ld detail=%@", (long)statusCode, errorDescription]];
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO, errorDescription);
            });
            return;
        }

        YTMUSetValue(@"discordAccessToken", accessToken);
        YTMUSetValue(@"discordRefreshToken", refreshToken);
        if (expiresIn) {
            YTMUSetValue(@"discordAccessTokenExpiry", @([[NSDate dateWithTimeIntervalSinceNow:[expiresIn doubleValue]] timeIntervalSince1970]));
        }
        YTMUSetValue(@"discordAuthorizedScope", authorizedScope);
        YTMUSetValue(@"discordPresenceLastError", nil);
        [YTMUDebugLogger logCategory:@"Discord" message:[NSString stringWithFormat:@"Token exchange success. scope=%@", authorizedScope.length > 0 ? authorizedScope : @"(none)"]];

        [self fetchDiscordUserNameWithToken:accessToken completion:^(NSString *username) {
            if (username.length > 0) {
                YTMUSetValue(@"discordConnectedUser", username);
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                NSString *baseMessage = username.length > 0 ? [NSString stringWithFormat:@"Connected as %@", username] : @"Discord connection completed.";
                if (!YTMUCanWriteDiscordProfileStatus(authorizedScope)) {
                    NSString *scopeText = authorizedScope.length > 0 ? authorizedScope : @"(none)";
                    completion(YES, [NSString stringWithFormat:@"%@\nCurrent OAuth scope: %@\nRich Presence sync requires sdk.social_layer_presence.", baseMessage, scopeText]);
                    return;
                }
                [[YTMUDiscordSocialSDKBridge sharedBridge] connectWithAccessToken:accessToken completion:^(BOOL success, NSString *message) {
                    NSString *fullMessage = baseMessage;
                    if (message.length > 0) {
                        fullMessage = [fullMessage stringByAppendingFormat:@"\n%@", message];
                    }
                    completion(success, fullMessage);
                }];
            });
        }];
    }] resume];
}

- (void)disconnectDiscord {
    [YTMUDebugLogger logCategory:@"Discord" message:@"Disconnect requested."];
    [self clearDiscordPresence];
    [[YTMUDiscordSocialSDKBridge sharedBridge] disconnect];

    NSArray<NSString *> *keys = @[
        @"discordAccessToken",
        @"discordRefreshToken",
        @"discordAccessTokenExpiry",
        @"discordPKCEVerifier",
        @"discordConnectedUser",
        @"discordAuthorizedScope",
        @"discordPresenceLastError"
    ];
    for (NSString *key in keys) {
        YTMUSetValue(key, nil);
    }
}

- (void)fetchDiscordUserNameWithToken:(NSString *)accessToken completion:(void (^)(NSString *username))completion {
    if (accessToken.length == 0) {
        [YTMUDebugLogger logCategory:@"Discord" message:@"Username fetch skipped: access token missing."];
        completion(@"");
        return;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://discord.com/api/v10/users/@me"]];
    [request setValue:[NSString stringWithFormat:@"Bearer %@", accessToken] forHTTPHeaderField:@"Authorization"];

    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || !data) {
            [YTMUDebugLogger logCategory:@"Discord" message:[NSString stringWithFormat:@"Username fetch failed: %@", error.localizedDescription ?: @"no response"]];
            completion(@"");
            return;
        }

        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSString *username = json[@"username"] ?: @"";
        NSString *discriminator = json[@"discriminator"] ?: @"";
        if (username.length == 0) {
            [YTMUDebugLogger logCategory:@"Discord" message:@"Username fetch returned empty username."];
            completion(@"");
            return;
        }

        if (discriminator.length > 0 && ![discriminator isEqualToString:@"0"]) {
            completion([NSString stringWithFormat:@"%@#%@", username, discriminator]);
            return;
        }

        completion(username);
    }] resume];
}

- (void)withValidDiscordToken:(void (^)(NSString *token, NSError *error))completion {
    NSString *accessToken = YTMUString(@"discordAccessToken", @"");
    NSString *refreshToken = YTMUString(@"discordRefreshToken", @"");
    NSString *clientID = kYTMUDiscordFixedClientID;
    NSTimeInterval expiry = [YTMUValue(@"discordAccessTokenExpiry") doubleValue];
    BOOL isExpired = (expiry > 0) && ([[NSDate date] timeIntervalSince1970] >= (expiry - 120));

    if (!isExpired && accessToken.length > 0) {
        [YTMUDebugLogger logCategory:@"Discord" message:@"Using cached access token."];
        completion(accessToken, nil);
        return;
    }

    if (refreshToken.length == 0 || clientID.length == 0) {
        [YTMUDebugLogger logCategory:@"Discord" message:@"Token refresh blocked: refresh token or client ID missing."];
        NSError *tokenError = [NSError errorWithDomain:@"YTMUIntegrations" code:101 userInfo:@{NSLocalizedDescriptionKey: @"Discord token is missing or expired. Re-connect OAuth2."}];
        completion(nil, tokenError);
        return;
    }

    [YTMUDebugLogger logCategory:@"Discord" message:@"Refreshing Discord access token."];

    NSDictionary<NSString *, NSString *> *params = @{
        @"client_id": clientID,
        @"grant_type": @"refresh_token",
        @"refresh_token": refreshToken
    };

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://discord.com/api/oauth2/token"]];
    request.HTTPMethod = @"POST";
    request.HTTPBody = [[YTMUFormEncodedString(params) dataUsingEncoding:NSUTF8StringEncoding] copy];
    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];

    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger statusCode = [response isKindOfClass:[NSHTTPURLResponse class]] ? [(NSHTTPURLResponse *)response statusCode] : 0;
        if (error || !data) {
            [YTMUDebugLogger logCategory:@"Discord" message:[NSString stringWithFormat:@"Token refresh failed. status=%ld error=%@", (long)statusCode, error.localizedDescription ?: @"unknown"]];
            completion(nil, error ?: [NSError errorWithDomain:@"YTMUIntegrations" code:102 userInfo:@{NSLocalizedDescriptionKey: @"Discord token refresh failed."}]);
            return;
        }

        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSString *newAccessToken = json[@"access_token"];
        NSString *newRefreshToken = json[@"refresh_token"] ?: refreshToken;
        NSNumber *expiresIn = json[@"expires_in"];

        if (newAccessToken.length == 0) {
            NSString *refreshError = json[@"error_description"] ?: json[@"error"] ?: @"missing access token";
            [YTMUDebugLogger logCategory:@"Discord" message:[NSString stringWithFormat:@"Token refresh denied. status=%ld detail=%@", (long)statusCode, refreshError]];
            completion(nil, [NSError errorWithDomain:@"YTMUIntegrations" code:103 userInfo:@{NSLocalizedDescriptionKey: @"Discord token refresh failed."}]);
            return;
        }

        YTMUSetValue(@"discordAccessToken", newAccessToken);
        YTMUSetValue(@"discordRefreshToken", newRefreshToken);
        if (expiresIn) {
            YTMUSetValue(@"discordAccessTokenExpiry", @([[NSDate dateWithTimeIntervalSinceNow:[expiresIn doubleValue]] timeIntervalSince1970]));
        }

        [YTMUDebugLogger logCategory:@"Discord" message:@"Token refresh success."];
        completion(newAccessToken, nil);
    }] resume];
}

- (void)updateDiscordPresenceWithElapsed:(NSTimeInterval)elapsed force:(BOOL)force {
    if (!YTMUBool(@"discordPresenceEnabled", NO)) return;
    if (self.currentTrackTitle.length == 0) return;

    YTMUDiscordSocialSDKBridge *bridge = [YTMUDiscordSocialSDKBridge sharedBridge];
    if (![bridge isAvailable]) {
        NSString *message = [bridge availabilityMessage];
        [YTMUDebugLogger logCategory:@"Discord" message:[NSString stringWithFormat:@"Presence update skipped: %@", message]];
        YTMUSetValue(@"discordPresenceLastError", message);
        return;
    }

    NSString *authorizedScope = YTMUString(@"discordAuthorizedScope", @"");
    if (!YTMUCanWriteDiscordProfileStatus(authorizedScope)) {
        NSString *scopeText = authorizedScope.length > 0 ? authorizedScope : @"(none)";
        [YTMUDebugLogger logCategory:@"Discord" message:[NSString stringWithFormat:@"Presence update skipped: scope not allowed (%@).", scopeText]];
        YTMUSetValue(@"discordPresenceLastError", [NSString stringWithFormat:@"OAuth scope '%@' does not include sdk.social_layer_presence.", scopeText]);
        return;
    }

    NSString *titleText = self.currentTrackTitle ?: @"";
    if (titleText.length > 128) titleText = [titleText substringToIndex:128];
    NSString *artistText = self.currentTrackArtist ?: @"";
    if (artistText.length > 128) artistText = [artistText substringToIndex:128];
    NSString *albumText = self.currentTrackAlbum ?: @"";
    if (albumText.length > 128) albumText = [albumText substringToIndex:128];
    NSString *artworkURL = self.currentTrackArtworkURL ?: @"";
    BOOL paused = self.currentPlaybackPaused;
    NSString *payloadSignature = [NSString stringWithFormat:@"%@\n%@\n%@\n%@\n%@\n%lld",
                                  titleText,
                                  artistText,
                                  albumText,
                                  artworkURL,
                                  paused ? @"1" : @"0",
                                  (long long)llround(elapsed)];

    if (!force && [self.lastDiscordStatusPayload isEqualToString:payloadSignature]) {
        return;
    }

    self.lastDiscordStatusPayload = payloadSignature;
    self.lastDiscordUpdate = [[NSDate date] timeIntervalSince1970];
    [YTMUDebugLogger logCategory:@"Discord" message:[NSString stringWithFormat:@"Presence update request. title=\"%@\" artist=\"%@\" album=\"%@\" paused=%@ elapsed=%.2f", titleText, artistText, albumText, paused ? @"YES" : @"NO", elapsed]];

    [self withValidDiscordToken:^(NSString *token, NSError *error) {
        if (error || token.length == 0) {
            [YTMUDebugLogger logCategory:@"Discord" message:[NSString stringWithFormat:@"Presence update blocked: %@", error.localizedDescription ?: @"token missing"]];
            YTMUSetValue(@"discordPresenceLastError", error.localizedDescription ?: @"Discord token missing.");
            return;
        }

        [bridge connectWithAccessToken:token completion:^(BOOL success, NSString *message) {
            if (!success) {
                [YTMUDebugLogger logCategory:@"Discord" message:[NSString stringWithFormat:@"Social SDK connect failed: %@", message ?: @"unknown"]];
                YTMUSetValue(@"discordPresenceLastError", message ?: @"Discord Social SDK connection failed.");
                return;
            }

            [bridge updateRichPresenceWithTitle:titleText artist:artistText album:albumText artworkURL:artworkURL paused:paused elapsed:elapsed duration:self.currentTrackDuration completion:^(BOOL updateSuccess, NSString *updateMessage) {
                if (updateSuccess) {
                    [YTMUDebugLogger logCategory:@"Discord" message:@"Presence update success via Discord Social SDK."];
                    YTMUSetValue(@"discordPresenceLastError", nil);
                    return;
                }

                NSString *failure = updateMessage.length > 0 ? updateMessage : @"Discord Rich Presence update failed.";
                [YTMUDebugLogger logCategory:@"Discord" message:[NSString stringWithFormat:@"Presence update failed via Discord Social SDK: %@", failure]];
                YTMUSetValue(@"discordPresenceLastError", failure);
            }];
        }];
    }];
}

- (void)clearDiscordPresence {
    [YTMUDebugLogger logCategory:@"Discord" message:@"Clear presence requested."];
    YTMUDiscordSocialSDKBridge *bridge = [YTMUDiscordSocialSDKBridge sharedBridge];
    if (![bridge isAvailable]) {
        [YTMUDebugLogger logCategory:@"Discord" message:[NSString stringWithFormat:@"Clear presence skipped: %@", [bridge availabilityMessage]]];
        return;
    }

    [self withValidDiscordToken:^(NSString *token, NSError *error) {
        if (error || token.length == 0) {
            [YTMUDebugLogger logCategory:@"Discord" message:[NSString stringWithFormat:@"Clear presence skipped: %@", error.localizedDescription ?: @"token missing"]];
            return;
        }

        [bridge connectWithAccessToken:token completion:^(BOOL success, NSString *message) {
            if (!success) {
                [YTMUDebugLogger logCategory:@"Discord" message:[NSString stringWithFormat:@"Clear presence connect failed: %@", message ?: @"unknown"]];
                return;
            }

            [bridge clearRichPresenceWithCompletion:^(BOOL clearSuccess, NSString *clearMessage) {
                if (!clearSuccess && clearMessage.length > 0) {
                    [YTMUDebugLogger logCategory:@"Discord" message:[NSString stringWithFormat:@"Clear presence failed: %@", clearMessage]];
                    return;
                }
                [YTMUDebugLogger logCategory:@"Discord" message:@"Clear presence request completed via Discord Social SDK."];
            }];
        }];
    }];
}

#pragma mark - Last.fm
- (void)startLastFMLoginWithCompletion:(void (^)(BOOL success, NSString *message, NSURL * _Nullable authURL))completion {
    NSString *apiKey = YTMUString(@"lastfmApiKey", @"");
    if (apiKey.length == 0 || YTMUString(@"lastfmApiSecret", @"").length == 0) {
        completion(NO, @"Set Last.fm API key and API secret first.", nil);
        return;
    }

    NSDictionary<NSString *, NSString *> *params = @{
        @"method": @"auth.getToken",
        @"api_key": apiKey
    };

    [self sendLastFMRequestJSON:params completion:^(NSDictionary *json, NSError *error) {
        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO, error.localizedDescription ?: @"Failed to start Last.fm login.", nil);
            });
            return;
        }

        NSString *token = json[@"token"];
        if (token.length == 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO, @"Could not fetch Last.fm auth token.", nil);
            });
            return;
        }

        YTMUSetValue(@"lastfmPendingToken", token);
        NSString *urlString = [NSString stringWithFormat:@"https://www.last.fm/api/auth/?api_key=%@&token=%@", apiKey, token];
        NSURL *authURL = [NSURL URLWithString:urlString];

        dispatch_async(dispatch_get_main_queue(), ^{
            completion(YES, @"Approve access in browser, then tap 'Complete Last.fm Login'.", authURL);
        });
    }];
}

- (void)completeLastFMLoginWithCompletion:(void (^)(BOOL success, NSString *message))completion {
    NSString *apiKey = YTMUString(@"lastfmApiKey", @"");
    NSString *token = YTMUString(@"lastfmPendingToken", @"");
    if (apiKey.length == 0 || token.length == 0) {
        completion(NO, @"No pending Last.fm login. Start login first.");
        return;
    }

    NSDictionary<NSString *, NSString *> *params = @{
        @"method": @"auth.getSession",
        @"api_key": apiKey,
        @"token": token
    };

    [self sendLastFMRequestJSON:params completion:^(NSDictionary *json, NSError *error) {
        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO, error.localizedDescription ?: @"Failed to complete Last.fm login.");
            });
            return;
        }

        NSDictionary *session = json[@"session"];
        NSString *sessionKey = session[@"key"];
        NSString *name = session[@"name"];
        if (sessionKey.length == 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO, @"Last.fm session key was not returned.");
            });
            return;
        }

        YTMUSetValue(@"lastfmSessionKey", sessionKey);
        if (name.length > 0) {
            YTMUSetValue(@"lastfmUsername", name);
        }
        YTMUSetValue(@"lastfmPendingToken", nil);

        dispatch_async(dispatch_get_main_queue(), ^{
            completion(YES, @"Last.fm login completed.");
        });
    }];
}

- (BOOL)isLastFMConfigured {
    return YTMUString(@"lastfmApiKey", @"").length > 0
        && YTMUString(@"lastfmApiSecret", @"").length > 0
        && YTMUString(@"lastfmSessionKey", @"").length > 0;
}

- (NSString *)lastFMSignatureForParameters:(NSDictionary<NSString *, NSString *> *)parameters apiSecret:(NSString *)apiSecret {
    NSArray<NSString *> *sortedKeys = [[parameters allKeys] sortedArrayUsingSelector:@selector(compare:)];
    NSMutableString *signatureBase = [NSMutableString string];
    for (NSString *key in sortedKeys) {
        [signatureBase appendString:key];
        [signatureBase appendString:parameters[key] ?: @""];
    }
    [signatureBase appendString:apiSecret];
    return YTMUMD5Hex(signatureBase);
}

- (void)sendLastFMRequestJSON:(NSDictionary<NSString *, NSString *> *)params completion:(void (^)(NSDictionary *json, NSError *error))completion {
    NSString *apiSecret = YTMUString(@"lastfmApiSecret", @"");
    if (apiSecret.length == 0) {
        completion(nil, [NSError errorWithDomain:@"YTMUIntegrations" code:200 userInfo:@{NSLocalizedDescriptionKey: @"Last.fm API secret is missing."}]);
        return;
    }

    NSMutableDictionary<NSString *, NSString *> *mutableParams = [params mutableCopy];
    mutableParams[@"api_sig"] = [self lastFMSignatureForParameters:mutableParams apiSecret:apiSecret];
    mutableParams[@"format"] = @"json";

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://ws.audioscrobbler.com/2.0/"]];
    request.HTTPMethod = @"POST";
    request.HTTPBody = [[YTMUFormEncodedString(mutableParams) dataUsingEncoding:NSUTF8StringEncoding] copy];
    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];

    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || !data) {
            completion(nil, error ?: [NSError errorWithDomain:@"YTMUIntegrations" code:201 userInfo:@{NSLocalizedDescriptionKey: @"Last.fm request failed."}]);
            return;
        }

        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (![json isKindOfClass:[NSDictionary class]]) {
            completion(nil, [NSError errorWithDomain:@"YTMUIntegrations" code:202 userInfo:@{NSLocalizedDescriptionKey: @"Last.fm returned an invalid response."}]);
            return;
        }

        if (json[@"error"]) {
            NSString *message = json[@"message"] ?: @"Last.fm returned an error.";
            completion(json, [NSError errorWithDomain:@"YTMUIntegrations" code:203 userInfo:@{NSLocalizedDescriptionKey: message}]);
            return;
        }

        completion(json, nil);
    }] resume];
}

- (void)sendLastFMNowPlaying {
    if (!YTMUBool(@"lastfmScrobbleEnabled", NO)) return;
    if (!YTMUBool(@"lastfmUpdateNowPlaying", YES)) return;
    if (![self isLastFMConfigured]) return;
    if (self.currentTrackTitle.length == 0 || self.currentTrackArtist.length == 0) return;

    NSString *apiKey = YTMUString(@"lastfmApiKey", @"");
    NSString *sessionKey = YTMUString(@"lastfmSessionKey", @"");

    NSMutableDictionary<NSString *, NSString *> *params = [@{
        @"method": @"track.updateNowPlaying",
        @"api_key": apiKey,
        @"sk": sessionKey,
        @"artist": self.currentTrackArtist,
        @"track": self.currentTrackTitle,
        @"duration": [NSString stringWithFormat:@"%ld", (long)llround(self.currentTrackDuration)]
    } mutableCopy];

    NSString *album = YTMUString(@"lastfmAlbum", @"");
    if (album.length > 0) params[@"album"] = album;

    [self sendLastFMRequestJSON:params completion:^(__unused NSDictionary *json, __unused NSError *error) {
    }];
}

- (void)sendLastFMScrobble {
    if (!YTMUBool(@"lastfmScrobbleEnabled", NO)) return;
    if (![self isLastFMConfigured]) return;
    if (self.currentTrackTitle.length == 0 || self.currentTrackArtist.length == 0) return;

    NSString *apiKey = YTMUString(@"lastfmApiKey", @"");
    NSString *sessionKey = YTMUString(@"lastfmSessionKey", @"");
    NSString *timestamp = [NSString stringWithFormat:@"%ld", (long)llround(self.currentTrackStartTimestamp)];

    NSMutableDictionary<NSString *, NSString *> *params = [@{
        @"method": @"track.scrobble",
        @"api_key": apiKey,
        @"sk": sessionKey,
        @"artist[0]": self.currentTrackArtist,
        @"track[0]": self.currentTrackTitle,
        @"timestamp[0]": timestamp,
        @"duration[0]": [NSString stringWithFormat:@"%ld", (long)llround(self.currentTrackDuration)]
    } mutableCopy];

    NSString *album = YTMUString(@"lastfmAlbum", @"");
    if (album.length > 0) params[@"album[0]"] = album;

    [self sendLastFMRequestJSON:params completion:^(__unused NSDictionary *json, __unused NSError *error) {
    }];
}

#pragma mark - Playback Integration
- (void)trackDidActivateForPlayer:(YTPlayerViewController *)player {
    NSString *videoID = player.currentVideoID ?: player.contentVideoID ?: @"";
    YTIVideoDetails *videoDetails = player.playerResponse.playerData.videoDetails;
    NSString *title = videoDetails.title ?: @"";
    NSString *artist = videoDetails.author ?: @"";
    NSString *album = YTMUSafeStringFromCandidateKeyPaths(videoDetails, @[
        @"album",
        @"albumName",
        @"musicMetadata.album",
        @"musicMetadata.albumName",
        @"trackData.album",
        @"metadata.album"
    ]);
    if (album.length == 0) {
        album = YTMUSafeStringFromCandidateKeyPaths(player.playerResponse.playerData, @[
            @"musicMetadata.album",
            @"musicMetadata.albumName",
            @"metadata.album",
            @"playlistMetadata.album",
            @"microformat.playerMicroformatRenderer.album"
        ]);
    }
    NSString *artworkURL = YTMUBestThumbnailURL(videoDetails.thumbnail);
    NSTimeInterval duration = MAX(0, player.currentVideoTotalMediaTime);

    if (videoID.length == 0 || title.length == 0) return;

    dispatch_async(self.queue, ^{
        self.currentVideoID = videoID;
        self.currentTrackTitle = title;
        self.currentTrackArtist = artist;
        self.currentTrackAlbum = album;
        self.currentTrackArtworkURL = artworkURL;
        self.currentTrackDuration = duration;
        self.currentTrackStartTimestamp = [[NSDate date] timeIntervalSince1970];
        self.lastObservedPlaybackTime = 0;
        self.currentPlaybackPaused = NO;
        self.currentTrackScrobbled = NO;

        [self updateDiscordPresenceWithElapsed:0 force:YES];
        [self sendLastFMNowPlaying];
    });
}

- (void)trackTimeDidChangeForPlayer:(YTPlayerViewController *)player {
    NSString *videoID = player.currentVideoID ?: player.contentVideoID ?: @"";
    NSTimeInterval currentTime = MAX(0, player.currentVideoMediaTime);

    if (videoID.length == 0) return;

    dispatch_async(self.queue, ^{
        if (![self.currentVideoID isEqualToString:videoID]) {
            return;
        }

        BOOL wasPaused = self.currentPlaybackPaused;
        if (self.lastObservedPlaybackTime > 0 && fabs(currentTime - self.lastObservedPlaybackTime) < 0.05) {
            self.currentPlaybackPaused = YES;
        } else {
            self.currentPlaybackPaused = NO;
        }
        self.lastObservedPlaybackTime = currentTime;

        if (YTMUBool(@"discordPresenceEnabled", NO)) {
            NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
            if ((now - self.lastDiscordUpdate >= 5.0) || (wasPaused != self.currentPlaybackPaused)) {
                [self updateDiscordPresenceWithElapsed:currentTime force:NO];
            }
        }

        if (!YTMUBool(@"lastfmScrobbleEnabled", NO) || self.currentTrackScrobbled || ![self isLastFMConfigured]) {
            return;
        }

        NSInteger minSeconds = MAX(1, YTMUInt(@"lastfmMinSeconds", 30));
        NSInteger minPercent = MIN(100, MAX(1, YTMUInt(@"lastfmMinPercent", 50)));
        NSTimeInterval percentThreshold = (self.currentTrackDuration > 0) ? (self.currentTrackDuration * ((double)minPercent / 100.0)) : minSeconds;
        NSTimeInterval threshold = MAX((NSTimeInterval)minSeconds, percentThreshold);

        if (currentTime >= threshold) {
            self.currentTrackScrobbled = YES;
            [self sendLastFMScrobble];
        }
    });
}

@end
