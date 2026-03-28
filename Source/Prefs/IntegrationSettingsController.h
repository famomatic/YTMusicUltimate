#import <UIKit/UIKit.h>
#import "../Headers/Localization.h"

@interface IntegrationSettingsController : UIViewController <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) UITableView *tableView;
@end
