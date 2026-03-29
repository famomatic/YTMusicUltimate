#import "YTMUDebugLogViewController.h"
#import "../Utils/YTMUDebugLogger.h"
#import "../Headers/Localization.h"

@interface YTMUDebugLogViewController ()
@property (nonatomic, copy) NSArray<NSString *> *entries;
@end

@implementation YTMUDebugLogViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Debug";
    self.entries = @[];

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

    UIBarButtonItem *copyAllButton = [[UIBarButtonItem alloc] initWithTitle:@"Copy All"
                                                                       style:UIBarButtonItemStylePlain
                                                                      target:self
                                                                      action:@selector(copyAllTapped)];
    UIBarButtonItem *clearButton = [[UIBarButtonItem alloc] initWithTitle:@"Clear"
                                                                     style:UIBarButtonItemStylePlain
                                                                    target:self
                                                                    action:@selector(clearTapped)];
    self.navigationItem.rightBarButtonItems = @[clearButton, copyAllButton];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadEntries];
}

- (void)reloadEntries {
    self.entries = [YTMUDebugLogger formattedEntriesWithLimit:0];
    [self.tableView reloadData];
}

- (void)copyAllTapped {
    if (self.entries.count == 0) {
        [self showMessage:@"No debug logs yet." title:LOC(@"WARNING")];
        return;
    }

    [UIPasteboard generalPasteboard].string = [self.entries componentsJoinedByString:@"\n"];
    [self showMessage:@"Copied all debug logs." title:LOC(@"DONE")];
}

- (void)clearTapped {
    [YTMUDebugLogger clear];
    [self reloadEntries];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return MAX(1, (NSInteger)self.entries.count);
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return UITableViewAutomaticDimension;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"debugCell"];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"debugCell"];
    }

    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.textLabel.numberOfLines = 0;
    cell.textLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    cell.textLabel.textColor = [UIColor labelColor];

    if (self.entries.count == 0) {
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.font = [UIFont systemFontOfSize:14];
        cell.textLabel.textColor = [UIColor secondaryLabelColor];
        cell.textLabel.text = @"No debug logs yet.";
        return cell;
    }

    cell.textLabel.text = self.entries[indexPath.row];
    return cell;
}

- (BOOL)tableView:(UITableView *)tableView shouldHighlightRowAtIndexPath:(NSIndexPath *)indexPath {
    return self.entries.count > 0;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row < self.entries.count) {
        [UIPasteboard generalPasteboard].string = self.entries[indexPath.row];
        [self showMessage:@"Copied log line." title:LOC(@"DONE")];
    }
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (void)showMessage:(NSString *)message title:(NSString *)title {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:LOC(@"YES") style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
