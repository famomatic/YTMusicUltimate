#import "YTMUIntegrationsManager.h"
#import "../Headers/YTPlayerViewController.h"
#import "../Headers/YTPlayerResponse.h"
#import "../Headers/YTIPlayerResponse.h"
#import "../Headers/YTIVideoDetails.h"
#import "YTMUDebugLogger.h"
#import <CommonCrypto/CommonDigest.h>
#import <Security/Security.h>

static NSString *const kYTMUPrefsKey = @"YTMUltimate";

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

static NSString *YTMUDiscordStatusText(NSString *prefix, NSString *title, NSString *artist, BOOL showArtist, BOOL showProgress, NSTimeInterval elapsed, NSTimeInterval totalDuration) {
    NSMutableString *status = [NSMutableString string];
    if (prefix.length > 0) {
        [status appendFormat:@"%@ ", prefix];
    }

    [status appendString:title ?: @""];

    if (showArtist && artist.length > 0) {
        [status appendFormat:@" - %@", artist];
    }

    if (showProgress && totalDuration > 0) {
        NSInteger elapsedInt = MAX(0, (NSInteger)llround(elapsed));
        NSInteger totalInt = MAX(0, (NSInteger)llround(totalDuration));
        [status appendFormat:@" (%02ld:%02ld/%02ld:%02ld)",
         (long)(elapsedInt / 60), (long)(elapsedInt % 60),
         (long)(totalInt / 60), (long)(totalInt % 60)];
    }

    if (status.length > 128) {
        return [status substringToIndex:128];
    }

    return status;
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
    return YTMUScopeContains(scopes, @"activities.write") ||
           YTMUScopeContains(scopes, @"rpc.activities.write") ||
           YTMUScopeContains(scopes, @"presences.write") ||
           YTMUScopeContains(scopes, @"sdk.social_layer_presence");
}

@interface YTMUIntegrationsManager ()
@property (nonatomic, strong) dispatch_queue_t queue;
@property (nonatomic, copy) NSString *currentVideoID;
@property (nonatomic, copy) NSString *currentTrackTitle;
@property (nonatomic, copy) NSString *currentTrackArtist;
@property (nonatomic, assign) NSTimeInterval currentTrackDuration;
@property (nonatomic, assign) NSTimeInterval currentTrackStartTimestamp;
@property (nonatomic, assign) NSTimeInterval lastDiscordUpdate;
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
        @"discordShowArtist": @YES,
        @"discordShowProgress": @YES,
        @"discordStatusPrefix": @"Listening to",
        @"discordOAuthScope": @"identify",
        @"discordAuthorizedScope": @"",
        @"discordPresenceLastError": @"",
        @"discordRedirectURI": @"https://localhost/ytmusicultimate-discord-callback",
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
    NSString *clientID = YTMUString(@"discordClientID", @"");
    NSString *redirectURI = YTMUString(@"discordRedirectURI", @"https://localhost/ytmusicultimate-discord-callback");
    NSString *oauthScope = YTMUString(@"discordOAuthScope", @"identify");
    if (oauthScope.length == 0) {
        oauthScope = @"identify";
    }
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
    NSString *clientID = YTMUString(@"discordClientID", @"");
    NSString *redirectURI = YTMUString(@"discordRedirectURI", @"https://localhost/ytmusicultimate-discord-callback");
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
                    completion(YES, [NSString stringWithFormat:@"%@\nCurrent OAuth scope: %@\nStatus sync requires activities.write (or equivalent).", baseMessage, scopeText]);
                    return;
                }
                completion(YES, baseMessage);
            });
        }];
    }] resume];
}

- (void)disconnectDiscord {
    [YTMUDebugLogger logCategory:@"Discord" message:@"Disconnect requested."];
    [self clearDiscordPresence];

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
    NSString *clientID = YTMUString(@"discordClientID", @"");
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
    NSString *authorizedScope = YTMUString(@"discordAuthorizedScope", @"");
    if (!YTMUCanWriteDiscordProfileStatus(authorizedScope)) {
        NSString *scopeText = authorizedScope.length > 0 ? authorizedScope : @"(none)";
        [YTMUDebugLogger logCategory:@"Discord" message:[NSString stringWithFormat:@"Presence update skipped: scope not allowed (%@).", scopeText]];
        YTMUSetValue(@"discordPresenceLastError", [NSString stringWithFormat:@"OAuth scope '%@' cannot update Discord profile status.", scopeText]);
        return;
    }

    BOOL showArtist = YTMUBool(@"discordShowArtist", YES);
    BOOL showProgress = YTMUBool(@"discordShowProgress", YES);
    NSString *prefix = YTMUString(@"discordStatusPrefix", @"Listening to");
    NSString *statusText = YTMUDiscordStatusText(prefix, self.currentTrackTitle, self.currentTrackArtist, showArtist, showProgress, elapsed, self.currentTrackDuration);

    if (!force && [self.lastDiscordStatusPayload isEqualToString:statusText]) {
        return;
    }

    self.lastDiscordStatusPayload = statusText;
    self.lastDiscordUpdate = [[NSDate date] timeIntervalSince1970];
    [YTMUDebugLogger logCategory:@"Discord" message:[NSString stringWithFormat:@"Presence update request. text=\"%@\"", statusText]];

    NSDictionary *payload = @{
        @"status": @"online",
        @"custom_status": @{
            @"text": statusText
        }
    };

    [self withValidDiscordToken:^(NSString *token, NSError *error) {
        if (error || token.length == 0) {
            [YTMUDebugLogger logCategory:@"Discord" message:[NSString stringWithFormat:@"Presence update blocked: %@", error.localizedDescription ?: @"token missing"]];
            return;
        }

        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://discord.com/api/v10/users/@me/settings"]];
        request.HTTPMethod = @"PATCH";
        [request setValue:[NSString stringWithFormat:@"Bearer %@", token] forHTTPHeaderField:@"Authorization"];
        [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
        request.HTTPBody = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];

        [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *requestError) {
            if (requestError) {
                [YTMUDebugLogger logCategory:@"Discord" message:[NSString stringWithFormat:@"Presence update network error: %@", requestError.localizedDescription ?: @"unknown"]];
                YTMUSetValue(@"discordPresenceLastError", requestError.localizedDescription ?: @"Discord status update failed.");
                return;
            }
            NSInteger statusCode = [response isKindOfClass:[NSHTTPURLResponse class]] ? [(NSHTTPURLResponse *)response statusCode] : 0;
            if (statusCode >= 200 && statusCode < 300) {
                [YTMUDebugLogger logCategory:@"Discord" message:[NSString stringWithFormat:@"Presence update success (HTTP %ld).", (long)statusCode]];
                YTMUSetValue(@"discordPresenceLastError", nil);
                return;
            }
            NSString *apiError = nil;
            if (data.length > 0) {
                NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                if ([json isKindOfClass:[NSDictionary class]]) {
                    apiError = json[@"message"] ?: json[@"error_description"] ?: json[@"error"];
                }
            }
            NSString *detail = apiError.length > 0 ? apiError : @"Unknown API error";
            [YTMUDebugLogger logCategory:@"Discord" message:[NSString stringWithFormat:@"Presence update failed (HTTP %ld): %@", (long)statusCode, detail]];
            YTMUSetValue(@"discordPresenceLastError", [NSString stringWithFormat:@"Discord API error (%ld): %@", (long)statusCode, detail]);
        }] resume];
    }];
}

- (void)clearDiscordPresence {
    NSDictionary *payload = @{@"custom_status": [NSNull null]};
    [YTMUDebugLogger logCategory:@"Discord" message:@"Clear presence requested."];
    [self withValidDiscordToken:^(NSString *token, NSError *error) {
        if (error || token.length == 0) {
            [YTMUDebugLogger logCategory:@"Discord" message:[NSString stringWithFormat:@"Clear presence skipped: %@", error.localizedDescription ?: @"token missing"]];
            return;
        }

        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://discord.com/api/v10/users/@me/settings"]];
        request.HTTPMethod = @"PATCH";
        [request setValue:[NSString stringWithFormat:@"Bearer %@", token] forHTTPHeaderField:@"Authorization"];
        [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
        request.HTTPBody = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];

        [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(__unused NSData *data, NSURLResponse *response, NSError *requestError) {
            NSInteger statusCode = [response isKindOfClass:[NSHTTPURLResponse class]] ? [(NSHTTPURLResponse *)response statusCode] : 0;
            if (requestError) {
                [YTMUDebugLogger logCategory:@"Discord" message:[NSString stringWithFormat:@"Clear presence network error: %@", requestError.localizedDescription ?: @"unknown"]];
                return;
            }
            [YTMUDebugLogger logCategory:@"Discord" message:[NSString stringWithFormat:@"Clear presence response HTTP %ld.", (long)statusCode]];
        }] resume];
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
    NSString *title = player.playerResponse.playerData.videoDetails.title ?: @"";
    NSString *artist = player.playerResponse.playerData.videoDetails.author ?: @"";
    NSTimeInterval duration = MAX(0, player.currentVideoTotalMediaTime);

    if (videoID.length == 0 || title.length == 0) return;

    dispatch_async(self.queue, ^{
        self.currentVideoID = videoID;
        self.currentTrackTitle = title;
        self.currentTrackArtist = artist;
        self.currentTrackDuration = duration;
        self.currentTrackStartTimestamp = [[NSDate date] timeIntervalSince1970];
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

        if (YTMUBool(@"discordPresenceEnabled", NO) && YTMUBool(@"discordShowProgress", YES)) {
            NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
            if (now - self.lastDiscordUpdate >= 15.0) {
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
