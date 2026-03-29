#import "IntegrationSettingsController.h"
#import "../Utils/YTMUIntegrationsManager.h"
#import "../Utils/YTMUDebugLogger.h"
#import "YTMUDebugLogViewController.h"

@interface IntegrationSettingsController ()
@property (nonatomic, assign) BOOL discordStatusExpanded;
@property (nonatomic, assign) BOOL discordDisplayExpanded;
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

    self.navigationItem.rightBarButtonItem = self.editButtonItem;

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

- (void)setEditing:(BOOL)editing animated:(BOOL)animated {
    [super setEditing:editing animated:animated];
    [self.tableView setEditing:editing animated:animated];
}

- (NSArray<NSString *> *)defaultDiscordTextOrder {
    return @[@"title", @"artist", @"album"];
}

- (NSArray<NSString *> *)discordTextOrderFromPrefs:(NSDictionary *)prefs {
    NSArray<NSString *> *fallback = [self defaultDiscordTextOrder];
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

    for (NSString *token in fallback) {
        if (![ordered containsObject:token]) [ordered addObject:token];
    }
    return ordered.array;
}

- (void)setDiscordTextOrder:(NSArray<NSString *> *)order {
    [self setPrefValue:order forKey:@"discordPresenceTextOrder"];
}

- (NSString *)discordOrderRowKeyForItem:(NSString *)item {
    return [NSString stringWithFormat:@"display_order_%@", item ?: @""];
}

- (NSString *)discordItemForOrderRowKey:(NSString *)rowKey {
    if (![rowKey hasPrefix:@"display_order_"]) return @"";
    return [rowKey substringFromIndex:@"display_order_".length];
}

- (NSString *)discordDisplayLabelForItem:(NSString *)item {
    if ([item isEqualToString:@"title"]) return @"Track title";
    if ([item isEqualToString:@"artist"]) return @"Artist";
    if ([item isEqualToString:@"album"]) return @"Album";
    return item ?: @"";
}

- (BOOL)isDiscordDisplaySwitchRow:(NSString *)row {
    return [row hasPrefix:@"display_toggle_"];
}

- (NSString *)discordPrefKeyForDisplaySwitchRow:(NSString *)row {
    NSDictionary<NSString *, NSString *> *mapping = @{
        @"display_toggle_show_text": @"discordPresenceShowText",
        @"display_toggle_show_title": @"discordPresenceShowTitle",
        @"display_toggle_show_artist": @"discordPresenceShowArtist",
        @"display_toggle_show_album": @"discordPresenceShowAlbum",
        @"display_toggle_enable_text_links": @"discordPresenceEnableTextLinks",
        @"display_toggle_link_title": @"discordPresenceLinkTitle",
        @"display_toggle_link_artist": @"discordPresenceLinkArtist",
        @"display_toggle_link_album": @"discordPresenceLinkAlbum",
        @"display_toggle_enable_artwork_link": @"discordPresenceEnableArtworkLink",
        @"display_toggle_show_buttons": @"discordPresenceShowButtons"
    };
    return mapping[row] ?: @"";
}

- (NSRange)discordOrderRowRangeForRows:(NSArray<NSString *> *)rows {
    NSInteger first = NSNotFound;
    NSInteger last = NSNotFound;
    for (NSInteger i = 0; i < (NSInteger)rows.count; i++) {
        if ([rows[i] hasPrefix:@"display_order_"]) {
            if (first == NSNotFound) first = i;
            last = i;
        }
    }

    if (first == NSNotFound || last == NSNotFound) return NSMakeRange(NSNotFound, 0);
    return NSMakeRange((NSUInteger)first, (NSUInteger)(last - first + 1));
}

- (NSArray<NSString *> *)discordRows {
    NSMutableDictionary *prefs = [self prefs];
    NSMutableArray<NSString *> *rows = [NSMutableArray arrayWithArray:@[@"enable", @"display_settings", @"status"]];

    if (self.discordDisplayExpanded) {
        [rows addObject:@"display_order_hint"];
        for (NSString *item in [self discordTextOrderFromPrefs:prefs]) {
            [rows addObject:[self discordOrderRowKeyForItem:item]];
        }
        [rows addObjectsFromArray:@[
            @"display_toggle_show_text",
            @"display_toggle_show_title",
            @"display_toggle_show_artist",
            @"display_toggle_show_album",
            @"display_toggle_enable_text_links",
            @"display_toggle_link_title",
            @"display_toggle_link_artist",
            @"display_toggle_link_album",
            @"display_toggle_enable_artwork_link",
            @"display_toggle_show_buttons"
        ]];
    }

    if (self.discordStatusExpanded) {
        [rows addObjectsFromArray:@[@"status_user", @"status_scope", @"status_error"]];
    }
    [rows addObjectsFromArray:@[@"open_oauth", @"complete_oauth", @"disconnect", @"debug"]];
    return rows;
}

#pragma mark - Table view
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 1;
    if (section == 1) return [self discordRows].count;
    return 10;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return LOC(@"OFFLINE_SEARCH");
    if (section == 1) return LOC(@"DISCORD_PRESENCE");
    return LOC(@"LASTFM_SCROBBLING");
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 1) {
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

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    return UITableViewCellEditingStyleNone;
}

- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath {
    return NO;
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
        NSArray<NSString *> *rows = [self discordRows];
        NSString *row = rows[indexPath.row];

        if ([row isEqualToString:@"enable"]) {
            cell.textLabel.text = LOC(@"DISCORD_ENABLE");
            cell.detailTextLabel.text = LOC(@"DISCORD_ENABLE_DESC");
            cell.detailTextLabel.numberOfLines = 0;

            UISwitch *switchControl = [[NSClassFromString(@"ABCSwitch") alloc] init];
            switchControl.on = [prefs[@"discordPresenceEnabled"] boolValue];
            switchControl.tag = 1100;
            [switchControl addTarget:self action:@selector(toggleSwitch:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = switchControl;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            return cell;
        }

        if ([row isEqualToString:@"display_settings"]) {
            cell.textLabel.text = @"Rich Presence display options";
            cell.detailTextLabel.text = self.discordDisplayExpanded ? @"Tap to collapse advanced layout controls." : @"Tap to configure text order, links, and buttons.";
            cell.detailTextLabel.numberOfLines = 2;
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            return cell;
        }

        if ([row isEqualToString:@"display_order_hint"]) {
            cell.textLabel.text = @"Text order";
            cell.detailTextLabel.text = @"Use Edit, then drag the handle to reorder top-to-bottom text lines.";
            cell.detailTextLabel.numberOfLines = 2;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            cell.textLabel.textColor = [UIColor secondaryLabelColor];
            return cell;
        }

        if ([row hasPrefix:@"display_order_"]) {
            NSString *item = [self discordItemForOrderRowKey:row];
            cell.textLabel.text = [self discordDisplayLabelForItem:item];
            cell.detailTextLabel.text = @"Drag to change where this text appears.";
            cell.detailTextLabel.numberOfLines = 0;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            return cell;
        }

        if ([self isDiscordDisplaySwitchRow:row]) {
            NSString *prefKey = [self discordPrefKeyForDisplaySwitchRow:row];
            NSString *title = @"";
            NSString *subtitle = @"";

            if ([row isEqualToString:@"display_toggle_show_text"]) {
                title = @"Show text";
                subtitle = @"Master toggle for title/artist/album lines.";
            } else if ([row isEqualToString:@"display_toggle_show_title"]) {
                title = @"Show title text";
                subtitle = @"Include the track title in rich presence text.";
            } else if ([row isEqualToString:@"display_toggle_show_artist"]) {
                title = @"Show artist text";
                subtitle = @"Include the artist name in rich presence text.";
            } else if ([row isEqualToString:@"display_toggle_show_album"]) {
                title = @"Show album text";
                subtitle = @"Include the album name in rich presence text.";
            } else if ([row isEqualToString:@"display_toggle_enable_text_links"]) {
                title = @"Enable text links";
                subtitle = @"Allow rich presence text to open URLs when tapped.";
            } else if ([row isEqualToString:@"display_toggle_link_title"]) {
                title = @"Link title text";
                subtitle = @"Use the track URL when title text is clickable.";
            } else if ([row isEqualToString:@"display_toggle_link_artist"]) {
                title = @"Link artist text";
                subtitle = @"Use the artist page URL when artist text is clickable.";
            } else if ([row isEqualToString:@"display_toggle_link_album"]) {
                title = @"Link album text";
                subtitle = @"Use the album URL when album text is clickable.";
            } else if ([row isEqualToString:@"display_toggle_enable_artwork_link"]) {
                title = @"Link cover image";
                subtitle = @"Open the track URL when album artwork is tapped.";
            } else if ([row isEqualToString:@"display_toggle_show_buttons"]) {
                title = @"Show buttons";
                subtitle = @"Show Listen/Album buttons on rich presence.";
            }

            cell.textLabel.text = title;
            cell.detailTextLabel.text = subtitle;
            cell.detailTextLabel.numberOfLines = 0;

            UISwitch *switchControl = [[NSClassFromString(@"ABCSwitch") alloc] init];
            switchControl.on = [prefs[prefKey] boolValue];
            switchControl.accessibilityIdentifier = prefKey;
            [switchControl addTarget:self action:@selector(toggleSwitch:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = switchControl;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            return cell;
        }

        if ([row isEqualToString:@"status"]) {
            NSString *discordUser = prefs[@"discordConnectedUser"];
            NSString *presenceError = prefs[@"discordPresenceLastError"];
            NSString *statusSummary = discordUser.length > 0 ? [NSString stringWithFormat:LOC(@"DISCORD_CONNECTED_AS"), discordUser] : @"Not connected";
            if (presenceError.length > 0) {
                statusSummary = [statusSummary stringByAppendingString:@" • Error detected"];
            }
            cell.textLabel.text = @"Connection Status";
            cell.detailTextLabel.text = statusSummary;
            cell.detailTextLabel.numberOfLines = 2;
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            cell.textLabel.textColor = [UIColor labelColor];
            return cell;
        }

        if ([row isEqualToString:@"status_user"]) {
            NSString *discordUser = prefs[@"discordConnectedUser"];
            cell.textLabel.text = @"Connected User";
            cell.detailTextLabel.text = discordUser.length > 0 ? discordUser : @"Not connected";
            cell.detailTextLabel.numberOfLines = 0;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            return cell;
        }

        if ([row isEqualToString:@"status_scope"]) {
            NSString *authorizedScope = prefs[@"discordAuthorizedScope"];
            cell.textLabel.text = @"OAuth Scope";
            cell.detailTextLabel.text = authorizedScope.length > 0 ? authorizedScope : @"Not authorized";
            cell.detailTextLabel.numberOfLines = 2;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            return cell;
        }

        if ([row isEqualToString:@"status_error"]) {
            NSString *presenceError = prefs[@"discordPresenceLastError"];
            cell.textLabel.text = @"Last Sync Error";
            cell.detailTextLabel.text = presenceError.length > 0 ? presenceError : @"None";
            cell.detailTextLabel.numberOfLines = 0;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            return cell;
        }

        if ([row isEqualToString:@"open_oauth"]) {
            cell.textLabel.text = LOC(@"DISCORD_OPEN_OAUTH");
            cell.detailTextLabel.text = LOC(@"DISCORD_OPEN_OAUTH_DESC");
            cell.detailTextLabel.numberOfLines = 0;
            cell.textLabel.textColor = [UIColor systemBlueColor];
            return cell;
        }

        if ([row isEqualToString:@"complete_oauth"]) {
            cell.textLabel.text = LOC(@"DISCORD_COMPLETE_OAUTH");
            cell.detailTextLabel.text = LOC(@"DISCORD_COMPLETE_OAUTH_DESC");
            cell.detailTextLabel.numberOfLines = 0;
            cell.textLabel.textColor = [UIColor systemBlueColor];
            return cell;
        }

        if ([row isEqualToString:@"disconnect"]) {
            cell.textLabel.text = LOC(@"DISCORD_DISCONNECT");
            cell.detailTextLabel.text = LOC(@"DISCORD_DISCONNECT_DESC");
            cell.detailTextLabel.numberOfLines = 0;
            cell.textLabel.textColor = [UIColor systemRedColor];
            return cell;
        }

        if ([row isEqualToString:@"debug"]) {
            cell.textLabel.text = @"Debug";
            cell.detailTextLabel.text = @"Open Discord integration logs.";
            cell.detailTextLabel.numberOfLines = 0;
            cell.textLabel.textColor = [UIColor systemBlueColor];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
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

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section != 1) return NO;
    NSArray<NSString *> *rows = [self discordRows];
    if (indexPath.row < 0 || indexPath.row >= (NSInteger)rows.count) return NO;
    return [rows[indexPath.row] hasPrefix:@"display_order_"];
}

- (NSIndexPath *)tableView:(UITableView *)tableView targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)sourceIndexPath toProposedIndexPath:(NSIndexPath *)proposedDestinationIndexPath {
    if (sourceIndexPath.section != 1) return sourceIndexPath;

    NSArray<NSString *> *rows = [self discordRows];
    NSRange orderRange = [self discordOrderRowRangeForRows:rows];
    if (orderRange.location == NSNotFound) return sourceIndexPath;
    if (![rows[sourceIndexPath.row] hasPrefix:@"display_order_"]) return sourceIndexPath;
    if (proposedDestinationIndexPath.section != 1) return sourceIndexPath;

    NSInteger minRow = (NSInteger)orderRange.location;
    NSInteger maxRow = (NSInteger)(NSMaxRange(orderRange) - 1);
    NSInteger clampedRow = MAX(minRow, MIN(maxRow, proposedDestinationIndexPath.row));
    return [NSIndexPath indexPathForRow:clampedRow inSection:1];
}

- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)sourceIndexPath toIndexPath:(NSIndexPath *)destinationIndexPath {
    if (sourceIndexPath.section != 1 || destinationIndexPath.section != 1) return;

    NSArray<NSString *> *rows = [self discordRows];
    NSRange orderRange = [self discordOrderRowRangeForRows:rows];
    if (orderRange.location == NSNotFound) return;

    NSInteger start = (NSInteger)orderRange.location;
    NSInteger end = (NSInteger)(NSMaxRange(orderRange) - 1);
    if (sourceIndexPath.row < start || sourceIndexPath.row > end) return;
    if (destinationIndexPath.row < start || destinationIndexPath.row > end) return;

    NSMutableDictionary *prefs = [self prefs];
    NSMutableArray<NSString *> *order = [[self discordTextOrderFromPrefs:prefs] mutableCopy];
    NSInteger fromOrderIndex = sourceIndexPath.row - start;
    NSInteger toOrderIndex = destinationIndexPath.row - start;
    if (fromOrderIndex < 0 || fromOrderIndex >= (NSInteger)order.count) return;

    NSString *movedItem = order[fromOrderIndex];
    [order removeObjectAtIndex:fromOrderIndex];
    toOrderIndex = MAX(0, MIN(toOrderIndex, (NSInteger)order.count));
    [order insertObject:movedItem atIndex:toOrderIndex];
    [self setDiscordTextOrder:order];
}

- (NSString *)maskedString:(NSString *)value {
    if (value.length == 0) return LOC(@"NOT_SET");
    if (value.length <= 8) return @"********";
    NSString *suffix = [value substringFromIndex:value.length - 4];
    return [NSString stringWithFormat:@"********%@", suffix];
}

- (BOOL)tableView:(UITableView *)tableView shouldHighlightRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) return NO;
    if (indexPath.section == 1) {
        NSString *row = [self discordRows][indexPath.row];
        if ([row isEqualToString:@"display_settings"] || [row isEqualToString:@"status"] || [row isEqualToString:@"open_oauth"] || [row isEqualToString:@"complete_oauth"] || [row isEqualToString:@"disconnect"] || [row isEqualToString:@"debug"]) {
            return YES;
        }
        if ([row hasPrefix:@"display_order_"] || [row isEqualToString:@"display_order_hint"] || [self isDiscordDisplaySwitchRow:row]) {
            return NO;
        }
        if ([row isEqualToString:@"enable"] ||
            [row isEqualToString:@"status_user"] ||
            [row isEqualToString:@"status_scope"] ||
            [row isEqualToString:@"status_error"]) {
            return NO;
        }
    }
    if (indexPath.section == 2 && (indexPath.row == 0 || indexPath.row == 1 || indexPath.row == 8)) return NO;
    return YES;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 1) {
        NSString *row = [self discordRows][indexPath.row];
        if ([row isEqualToString:@"display_settings"]) {
            self.discordDisplayExpanded = !self.discordDisplayExpanded;
            [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:1] withRowAnimation:UITableViewRowAnimationAutomatic];
        } else if ([row isEqualToString:@"status"]) {
            self.discordStatusExpanded = !self.discordStatusExpanded;
            [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:1] withRowAnimation:UITableViewRowAnimationAutomatic];
        } else if ([row isEqualToString:@"open_oauth"]) {
            NSError *error = nil;
            NSURL *oauthURL = [[YTMUIntegrationsManager sharedManager] discordAuthorizationURLWithError:&error];
            if (!oauthURL) {
                [self showMessage:error.localizedDescription ?: @"Failed to create OAuth URL." title:LOC(@"WARNING")];
            } else {
                [[UIApplication sharedApplication] openURL:oauthURL options:@{} completionHandler:nil];
            }
        } else if ([row isEqualToString:@"complete_oauth"]) {
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
        } else if ([row isEqualToString:@"disconnect"]) {
            [[YTMUIntegrationsManager sharedManager] disconnectDiscord];
            [self showMessage:LOC(@"DISCORD_DISCONNECTED") title:LOC(@"DONE")];
            [self.tableView reloadData];
        } else if ([row isEqualToString:@"debug"]) {
            YTMUDebugLogViewController *controller = [[YTMUDebugLogViewController alloc] init];
            [self.navigationController pushViewController:controller animated:YES];
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
    if (sender.accessibilityIdentifier.length > 0) {
        [self setPrefValue:@(sender.on) forKey:sender.accessibilityIdentifier];
        return;
    }

    if (sender.tag == 1000) {
        [self setPrefValue:@(sender.on) forKey:@"offlineDownloadsSearch"];
        return;
    }

    NSArray<NSString *> *discordKeys = @[@"discordPresenceEnabled"];
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
