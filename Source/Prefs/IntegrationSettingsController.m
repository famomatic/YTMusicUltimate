#import "IntegrationSettingsController.h"
#import "../Utils/YTMUIntegrationsManager.h"

@interface IntegrationSettingsController ()
@end

@implementation IntegrationSettingsController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = LOC(@"INTEGRATIONS_SETTINGS");
    [YTMUIntegrationsManager initializeDefaultSettings];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.view addSubview:self.tableView];

    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.tableView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [self.tableView.widthAnchor constraintEqualToAnchor:self.view.widthAnchor],
        [self.tableView.heightAnchor constraintEqualToAnchor:self.view.heightAnchor]
    ]];
}

- (NSMutableDictionary *)prefs {
    NSDictionary *dict = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"YTMUltimate"] ?: @{};
    return [NSMutableDictionary dictionaryWithDictionary:dict];
}

- (void)setPrefValue:(id)value forKey:(NSString *)key {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary *prefs = [self prefs];
    if (value) {
        prefs[key] = value;
    } else {
        [prefs removeObjectForKey:key];
    }
    [defaults setObject:prefs forKey:@"YTMUltimate"];
}

#pragma mark - Table view
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 1;
    if (section == 1) return 9;
    return 10;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return LOC(@"OFFLINE_SEARCH");
    if (section == 1) return LOC(@"DISCORD_PRESENCE");
    return LOC(@"LASTFM_SCROBBLING");
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    NSMutableDictionary *prefs = [self prefs];
    if (section == 1) {
        NSString *discordUser = prefs[@"discordConnectedUser"];
        if (discordUser.length > 0) {
            return [NSString stringWithFormat:LOC(@"DISCORD_CONNECTED_AS"), discordUser];
        }
        return LOC(@"DISCORD_OAUTH_FOOTER");
    }

    if (section == 2) {
        return LOC(@"LASTFM_FOOTER");
    }

    return nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return UITableViewAutomaticDimension;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell"];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"cell"];
    }

    NSMutableDictionary *prefs = [self prefs];
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessoryView = nil;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    cell.textLabel.textColor = [UIColor labelColor];

    if (indexPath.section == 0 && indexPath.row == 0) {
        cell.textLabel.text = LOC(@"OFFLINE_SEARCH_DOWNLOADS_ONLY");
        cell.detailTextLabel.text = LOC(@"OFFLINE_SEARCH_DOWNLOADS_ONLY_DESC");
        cell.detailTextLabel.numberOfLines = 0;

        UISwitch *switchControl = [[NSClassFromString(@"ABCSwitch") alloc] init];
        switchControl.on = [prefs[@"offlineDownloadsSearch"] boolValue];
        switchControl.tag = 1000;
        [switchControl addTarget:self action:@selector(toggleSwitch:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = switchControl;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }

    if (indexPath.section == 1) {
        if (indexPath.row == 0 || indexPath.row == 1 || indexPath.row == 2) {
            NSArray *rows = @[
                @{@"title": LOC(@"DISCORD_ENABLE"), @"desc": LOC(@"DISCORD_ENABLE_DESC"), @"key": @"discordPresenceEnabled"},
                @{@"title": LOC(@"DISCORD_SHOW_ARTIST"), @"desc": LOC(@"DISCORD_SHOW_ARTIST_DESC"), @"key": @"discordShowArtist"},
                @{@"title": LOC(@"DISCORD_SHOW_PROGRESS"), @"desc": LOC(@"DISCORD_SHOW_PROGRESS_DESC"), @"key": @"discordShowProgress"}
            ];
            NSDictionary *row = rows[indexPath.row];
            cell.textLabel.text = row[@"title"];
            cell.detailTextLabel.text = row[@"desc"];
            cell.detailTextLabel.numberOfLines = 0;

            UISwitch *switchControl = [[NSClassFromString(@"ABCSwitch") alloc] init];
            switchControl.on = [prefs[row[@"key"]] boolValue];
            switchControl.tag = 1100 + indexPath.row;
            [switchControl addTarget:self action:@selector(toggleSwitch:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = switchControl;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            return cell;
        }

        if (indexPath.row == 3) {
            cell.textLabel.text = LOC(@"DISCORD_STATUS_PREFIX");
            cell.detailTextLabel.text = prefs[@"discordStatusPrefix"] ?: @"Listening to";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            return cell;
        }

        if (indexPath.row == 4) {
            cell.textLabel.text = LOC(@"DISCORD_CLIENT_ID");
            NSString *clientID = prefs[@"discordClientID"];
            cell.detailTextLabel.text = clientID.length > 0 ? clientID : LOC(@"NOT_SET");
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            return cell;
        }

        if (indexPath.row == 5) {
            cell.textLabel.text = LOC(@"DISCORD_REDIRECT_URI");
            NSString *redirectURI = prefs[@"discordRedirectURI"];
            cell.detailTextLabel.text = redirectURI.length > 0 ? redirectURI : @"https://localhost/ytmusicultimate-discord-callback";
            cell.detailTextLabel.numberOfLines = 2;
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            return cell;
        }

        if (indexPath.row == 6) {
            cell.textLabel.text = LOC(@"DISCORD_OPEN_OAUTH");
            cell.detailTextLabel.text = LOC(@"DISCORD_OPEN_OAUTH_DESC");
            cell.detailTextLabel.numberOfLines = 0;
            cell.textLabel.textColor = [UIColor systemBlueColor];
            return cell;
        }

        if (indexPath.row == 7) {
            cell.textLabel.text = LOC(@"DISCORD_COMPLETE_OAUTH");
            cell.detailTextLabel.text = LOC(@"DISCORD_COMPLETE_OAUTH_DESC");
            cell.detailTextLabel.numberOfLines = 0;
            cell.textLabel.textColor = [UIColor systemBlueColor];
            return cell;
        }

        if (indexPath.row == 8) {
            cell.textLabel.text = LOC(@"DISCORD_DISCONNECT");
            cell.detailTextLabel.text = LOC(@"DISCORD_DISCONNECT_DESC");
            cell.detailTextLabel.numberOfLines = 0;
            cell.textLabel.textColor = [UIColor systemRedColor];
            return cell;
        }
    }

    if (indexPath.section == 2) {
        if (indexPath.row == 0 || indexPath.row == 1) {
            NSArray *rows = @[
                @{@"title": LOC(@"LASTFM_ENABLE"), @"desc": LOC(@"LASTFM_ENABLE_DESC"), @"key": @"lastfmScrobbleEnabled"},
                @{@"title": LOC(@"LASTFM_NOWPLAYING"), @"desc": LOC(@"LASTFM_NOWPLAYING_DESC"), @"key": @"lastfmUpdateNowPlaying"}
            ];
            NSDictionary *row = rows[indexPath.row];
            cell.textLabel.text = row[@"title"];
            cell.detailTextLabel.text = row[@"desc"];
            cell.detailTextLabel.numberOfLines = 0;

            UISwitch *switchControl = [[NSClassFromString(@"ABCSwitch") alloc] init];
            switchControl.on = [prefs[row[@"key"]] boolValue];
            switchControl.tag = 1200 + indexPath.row;
            [switchControl addTarget:self action:@selector(toggleSwitch:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = switchControl;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            return cell;
        }

        if (indexPath.row == 2) {
            cell.textLabel.text = LOC(@"LASTFM_API_KEY");
            cell.detailTextLabel.text = [self maskedString:prefs[@"lastfmApiKey"]];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            return cell;
        }

        if (indexPath.row == 3) {
            cell.textLabel.text = LOC(@"LASTFM_API_SECRET");
            cell.detailTextLabel.text = [self maskedString:prefs[@"lastfmApiSecret"]];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            return cell;
        }

        if (indexPath.row == 4) {
            cell.textLabel.text = LOC(@"LASTFM_SESSION_KEY");
            cell.detailTextLabel.text = [self maskedString:prefs[@"lastfmSessionKey"]];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            return cell;
        }

        if (indexPath.row == 5) {
            cell.textLabel.text = LOC(@"LASTFM_USERNAME");
            NSString *username = prefs[@"lastfmUsername"];
            cell.detailTextLabel.text = username.length > 0 ? username : LOC(@"NOT_SET");
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            return cell;
        }

        if (indexPath.row == 6) {
            cell.textLabel.text = LOC(@"LASTFM_START_LOGIN");
            cell.detailTextLabel.text = LOC(@"LASTFM_START_LOGIN_DESC");
            cell.detailTextLabel.numberOfLines = 0;
            cell.textLabel.textColor = [UIColor systemBlueColor];
            return cell;
        }

        if (indexPath.row == 7) {
            cell.textLabel.text = LOC(@"LASTFM_COMPLETE_LOGIN");
            cell.detailTextLabel.text = LOC(@"LASTFM_COMPLETE_LOGIN_DESC");
            cell.detailTextLabel.numberOfLines = 0;
            cell.textLabel.textColor = [UIColor systemBlueColor];
            return cell;
        }

        if (indexPath.row == 8) {
            cell.textLabel.text = LOC(@"LASTFM_MIN_PERCENT");
            UISegmentedControl *control = [[UISegmentedControl alloc] initWithItems:@[@"30%", @"50%", @"70%", @"90%"]];
            NSArray<NSNumber *> *values = @[@30, @50, @70, @90];
            NSInteger stored = [prefs[@"lastfmMinPercent"] integerValue];
            NSInteger selected = 1;
            for (NSInteger i = 0; i < values.count; i++) {
                if ([values[i] integerValue] == stored) {
                    selected = i;
                    break;
                }
            }
            control.selectedSegmentIndex = selected;
            [control addTarget:self action:@selector(minPercentChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = control;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            return cell;
        }

        if (indexPath.row == 9) {
            cell.textLabel.text = LOC(@"LASTFM_MIN_SECONDS");
            NSNumber *minSeconds = prefs[@"lastfmMinSeconds"] ?: @30;
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%ld", (long)minSeconds.integerValue];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            return cell;
        }
    }

    return cell;
}

- (NSString *)maskedString:(NSString *)value {
    if (value.length == 0) return LOC(@"NOT_SET");
    if (value.length <= 8) return @"********";
    NSString *suffix = [value substringFromIndex:value.length - 4];
    return [NSString stringWithFormat:@"********%@", suffix];
}

- (BOOL)tableView:(UITableView *)tableView shouldHighlightRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) return NO;
    if (indexPath.section == 1 && indexPath.row <= 2) return NO;
    if (indexPath.section == 2 && (indexPath.row == 0 || indexPath.row == 1 || indexPath.row == 8)) return NO;
    return YES;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 1) {
        if (indexPath.row == 3) {
            [self promptForKey:@"discordStatusPrefix" title:LOC(@"DISCORD_STATUS_PREFIX") placeholder:@"Listening to" secure:NO keyboard:UIKeyboardTypeDefault];
        } else if (indexPath.row == 4) {
            [self promptForKey:@"discordClientID" title:LOC(@"DISCORD_CLIENT_ID") placeholder:@"123456789012345678" secure:NO keyboard:UIKeyboardTypeASCIICapable];
        } else if (indexPath.row == 5) {
            [self promptForKey:@"discordRedirectURI" title:LOC(@"DISCORD_REDIRECT_URI") placeholder:@"https://localhost/ytmusicultimate-discord-callback" secure:NO keyboard:UIKeyboardTypeURL];
        } else if (indexPath.row == 6) {
            NSError *error = nil;
            NSURL *oauthURL = [[YTMUIntegrationsManager sharedManager] discordAuthorizationURLWithError:&error];
            if (!oauthURL) {
                [self showMessage:error.localizedDescription ?: @"Failed to create OAuth URL." title:LOC(@"WARNING")];
            } else {
                [[UIApplication sharedApplication] openURL:oauthURL options:@{} completionHandler:nil];
            }
        } else if (indexPath.row == 7) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:LOC(@"DISCORD_COMPLETE_OAUTH") message:LOC(@"DISCORD_CODE_PROMPT") preferredStyle:UIAlertControllerStyleAlert];
            [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
                textField.placeholder = @"Authorization code";
                textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
                textField.autocorrectionType = UITextAutocorrectionTypeNo;
            }];

            [alert addAction:[UIAlertAction actionWithTitle:LOC(@"CANCEL") style:UIAlertActionStyleCancel handler:nil]];
            [alert addAction:[UIAlertAction actionWithTitle:LOC(@"YES") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                NSString *code = alert.textFields.firstObject.text ?: @"";
                [[YTMUIntegrationsManager sharedManager] exchangeDiscordCode:code completion:^(BOOL success, NSString *message) {
                    [self showMessage:message title:success ? LOC(@"DONE") : LOC(@"WARNING")];
                    [self.tableView reloadData];
                }];
            }]];
            [self presentViewController:alert animated:YES completion:nil];
        } else if (indexPath.row == 8) {
            [[YTMUIntegrationsManager sharedManager] disconnectDiscord];
            [self showMessage:LOC(@"DISCORD_DISCONNECTED") title:LOC(@"DONE")];
            [self.tableView reloadData];
        }
    }

    if (indexPath.section == 2) {
        if (indexPath.row == 2) {
            [self promptForKey:@"lastfmApiKey" title:LOC(@"LASTFM_API_KEY") placeholder:@"Your Last.fm API Key" secure:NO keyboard:UIKeyboardTypeASCIICapable];
        } else if (indexPath.row == 3) {
            [self promptForKey:@"lastfmApiSecret" title:LOC(@"LASTFM_API_SECRET") placeholder:@"Your Last.fm API Secret" secure:YES keyboard:UIKeyboardTypeASCIICapable];
        } else if (indexPath.row == 4) {
            [self promptForKey:@"lastfmSessionKey" title:LOC(@"LASTFM_SESSION_KEY") placeholder:@"Your Last.fm Session Key" secure:YES keyboard:UIKeyboardTypeASCIICapable];
        } else if (indexPath.row == 5) {
            [self promptForKey:@"lastfmUsername" title:LOC(@"LASTFM_USERNAME") placeholder:@"username" secure:NO keyboard:UIKeyboardTypeDefault];
        } else if (indexPath.row == 6) {
            [[YTMUIntegrationsManager sharedManager] startLastFMLoginWithCompletion:^(BOOL success, NSString *message, NSURL *authURL) {
                [self showMessage:message title:success ? LOC(@"DONE") : LOC(@"WARNING")];
                if (success && authURL) {
                    [[UIApplication sharedApplication] openURL:authURL options:@{} completionHandler:nil];
                }
                [self.tableView reloadData];
            }];
        } else if (indexPath.row == 7) {
            [[YTMUIntegrationsManager sharedManager] completeLastFMLoginWithCompletion:^(BOOL success, NSString *message) {
                [self showMessage:message title:success ? LOC(@"DONE") : LOC(@"WARNING")];
                [self.tableView reloadData];
            }];
        } else if (indexPath.row == 9) {
            [self promptForKey:@"lastfmMinSeconds" title:LOC(@"LASTFM_MIN_SECONDS") placeholder:@"30" secure:NO keyboard:UIKeyboardTypeNumberPad];
        }
    }

    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (void)toggleSwitch:(UISwitch *)sender {
    if (sender.tag == 1000) {
        [self setPrefValue:@(sender.on) forKey:@"offlineDownloadsSearch"];
        return;
    }

    NSArray<NSString *> *discordKeys = @[@"discordPresenceEnabled", @"discordShowArtist", @"discordShowProgress"];
    if (sender.tag >= 1100 && sender.tag < 1100 + (NSInteger)discordKeys.count) {
        [self setPrefValue:@(sender.on) forKey:discordKeys[sender.tag - 1100]];
        return;
    }

    NSArray<NSString *> *lastFMKeys = @[@"lastfmScrobbleEnabled", @"lastfmUpdateNowPlaying"];
    if (sender.tag >= 1200 && sender.tag < 1200 + (NSInteger)lastFMKeys.count) {
        [self setPrefValue:@(sender.on) forKey:lastFMKeys[sender.tag - 1200]];
    }
}

- (void)minPercentChanged:(UISegmentedControl *)sender {
    NSArray<NSNumber *> *values = @[@30, @50, @70, @90];
    NSInteger index = MAX(0, MIN(sender.selectedSegmentIndex, (NSInteger)values.count - 1));
    [self setPrefValue:values[index] forKey:@"lastfmMinPercent"];
}

- (void)promptForKey:(NSString *)key title:(NSString *)title placeholder:(NSString *)placeholder secure:(BOOL)secure keyboard:(UIKeyboardType)keyboardType {
    NSMutableDictionary *prefs = [self prefs];
    NSString *currentValue = [prefs[key] description] ?: @"";

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.text = currentValue;
        textField.placeholder = placeholder;
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
        textField.keyboardType = keyboardType;
        textField.secureTextEntry = secure;
    }];

    [alert addAction:[UIAlertAction actionWithTitle:LOC(@"CANCEL") style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:LOC(@"YES") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        NSString *newValue = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([key isEqualToString:@"lastfmMinSeconds"]) {
            NSInteger parsed = MAX(1, [newValue integerValue]);
            [self setPrefValue:@(parsed) forKey:key];
        } else {
            [self setPrefValue:newValue forKey:key];
        }
        [self.tableView reloadData];
    }]];

    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showMessage:(NSString *)message title:(NSString *)title {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:LOC(@"YES") style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
