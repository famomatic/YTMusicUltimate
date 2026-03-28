#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <SystemConfiguration/SystemConfiguration.h>
#import "Headers/YTPlayerViewController.h"
#import "Prefs/YTMDownloads.h"
#import "Utils/YTMUIntegrationsManager.h"

static BOOL YTMU(NSString *key) {
    NSDictionary *prefs = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"YTMUltimate"];
    return [prefs[key] boolValue];
}

static BOOL YTMUHasInternetConnection(void) {
    SCNetworkReachabilityRef reachability = SCNetworkReachabilityCreateWithName(NULL, "music.youtube.com");
    if (!reachability) return NO;

    SCNetworkReachabilityFlags flags = 0;
    BOOL success = SCNetworkReachabilityGetFlags(reachability, &flags);
    CFRelease(reachability);
    if (!success) return NO;

    BOOL reachable = (flags & kSCNetworkReachabilityFlagsReachable) != 0;
    BOOL connectionRequired = (flags & kSCNetworkReachabilityFlagsConnectionRequired) != 0;
    return reachable && !connectionRequired;
}

static const void *kYTMUOfflineDownloadsVCKey = &kYTMUOfflineDownloadsVCKey;

%hook YTMSearchTabViewController
- (void)viewDidLoad {
    %orig;
    [self ytmu_updateOfflineDownloadsSearchOverlay];
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    [self ytmu_updateOfflineDownloadsSearchOverlay];
}

%new
- (void)ytmu_removeOfflineDownloadsSearchOverlay {
    YTMDownloads *downloadsVC = objc_getAssociatedObject(self, kYTMUOfflineDownloadsVCKey);
    if (!downloadsVC) return;

    [downloadsVC willMoveToParentViewController:nil];
    [downloadsVC.view removeFromSuperview];
    [downloadsVC removeFromParentViewController];
    objc_setAssociatedObject(self, kYTMUOfflineDownloadsVCKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%new
- (void)ytmu_updateOfflineDownloadsSearchOverlay {
    if (!YTMU(@"YTMUltimateIsEnabled") || !YTMU(@"offlineDownloadsSearch") || YTMUHasInternetConnection()) {
        [self ytmu_removeOfflineDownloadsSearchOverlay];
        return;
    }

    YTMDownloads *downloadsVC = objc_getAssociatedObject(self, kYTMUOfflineDownloadsVCKey);
    if (downloadsVC) {
        downloadsVC.view.frame = self.view.bounds;
        return;
    }

    downloadsVC = [[YTMDownloads alloc] init];
    downloadsVC.searchOnlyMode = YES;

    [self addChildViewController:downloadsVC];
    downloadsVC.view.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:downloadsVC.view];

    [NSLayoutConstraint activateConstraints:@[
        [downloadsVC.view.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [downloadsVC.view.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [downloadsVC.view.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [downloadsVC.view.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];

    [downloadsVC didMoveToParentViewController:self];
    objc_setAssociatedObject(self, kYTMUOfflineDownloadsVCKey, downloadsVC, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
%end

%hook YTPlayerViewController
- (void)playbackController:(id)arg1 didActivateVideo:(id)arg2 withPlaybackData:(id)arg3 {
    %orig;
    [[YTMUIntegrationsManager sharedManager] trackDidActivateForPlayer:self];
}

- (void)singleVideo:(id)video currentVideoTimeDidChange:(id)time {
    %orig;
    [[YTMUIntegrationsManager sharedManager] trackTimeDidChangeForPlayer:self];
}

- (void)potentiallyMutatedSingleVideo:(id)video currentVideoTimeDidChange:(id)time {
    %orig;
    [[YTMUIntegrationsManager sharedManager] trackTimeDidChangeForPlayer:self];
}
%end

%ctor {
    [YTMUIntegrationsManager initializeDefaultSettings];
}
