#import "VMRootViewController.h"
#import "../../include/VMLocalization.h"
#import "../../include/VMMemoryEngine.h"
#import "../ui/main/VMAppSelectViewController.h"
#import "../ui/main/VMLockListViewController.h"
#import "../ui/main/VMModifierViewController.h"
#import "../ui/main/VMSettingsViewController.h"
#import "../ui/patch/VMPatcherViewController.h"
#import "../ui/pointer/VMPointerSearchViewController.h"
#import "../ui/pointer/VMSavedPointersViewController.h"
#import "../utils/managers/VMUpdateManager.h"
#define TR(key) ([[VMLocalization shared] localizedString:key])

static NSString *const kVMTabOrderKey = @"vm_bottom_tab_order";

@interface VMTabReorderCell : UITableViewCell
@end
@implementation VMTabReorderCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)rid {
  if (self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:rid]) {
    self.textLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    self.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
  }
  return self;
}
@end

@interface VMTabReorderViewController : UITableViewController
@property(nonatomic, strong) NSMutableArray<NSDictionary *> *tabDescriptors;
@property(nonatomic, copy) void (^onDone)(NSArray<NSNumber *> *newOrder);
@end

@implementation VMTabReorderViewController

- (void)viewDidLoad {
  [super viewDidLoad];
  self.title = TR(@"Set_Tab_Reorder");
  self.tableView.editing = YES;
  self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
  [self.tableView registerClass:[VMTabReorderCell class] forCellReuseIdentifier:@"Cell"];
  
  self.navigationItem.rightBarButtonItem =
      [[UIBarButtonItem alloc] initWithTitle:TR(@"Btn_OK")
                                       style:UIBarButtonItemStyleDone
                                      target:self
                                      action:@selector(doneTapped)];
  self.navigationItem.leftBarButtonItem =
      [[UIBarButtonItem alloc] initWithTitle:TR(@"Btn_Restore_Default")
                                       style:UIBarButtonItemStylePlain
                                      target:self
                                      action:@selector(resetTapped)];
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
  return self.tabDescriptors.count;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
  VMTabReorderCell *cell = [tv dequeueReusableCellWithIdentifier:@"Cell" forIndexPath:ip];
  NSDictionary *desc = self.tabDescriptors[ip.row];
  cell.textLabel.text = desc[@"title"];
  cell.imageView.image = [UIImage systemImageNamed:desc[@"icon"]];
  cell.imageView.tintColor = [UIColor systemBlueColor];
  cell.showsReorderControl = YES;
  return cell;
}

- (BOOL)tableView:(UITableView *)tv canMoveRowAtIndexPath:(NSIndexPath *)ip { return YES; }
- (BOOL)tableView:(UITableView *)tv canEditRowAtIndexPath:(NSIndexPath *)ip { return YES; }
- (UITableViewCellEditingStyle)tableView:(UITableView *)tv editingStyleForRowAtIndexPath:(NSIndexPath *)ip {
  return UITableViewCellEditingStyleNone;
}
- (BOOL)tableView:(UITableView *)tv shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)ip { return NO; }

- (void)tableView:(UITableView *)tv moveRowAtIndexPath:(NSIndexPath *)from toIndexPath:(NSIndexPath *)to {
  NSDictionary *item = self.tabDescriptors[from.row];
  [self.tabDescriptors removeObjectAtIndex:from.row];
  [self.tabDescriptors insertObject:item atIndex:to.row];
}

- (void)doneTapped {
  NSMutableArray<NSNumber *> *order = [NSMutableArray array];
  for (NSDictionary *d in self.tabDescriptors) {
    [order addObject:d[@"tag"]];
  }
  [[NSUserDefaults standardUserDefaults] setObject:order forKey:kVMTabOrderKey];
  [[NSUserDefaults standardUserDefaults] synchronize];
  if (self.onDone) self.onDone(order);
  [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)resetTapped {
  
  NSArray *defaultOrder = @[@0, @1, @2, @3, @4];
  self.tabDescriptors = [NSMutableArray array];
  
  NSArray *allDescs = [self defaultDescriptors];
  for (NSNumber *tag in defaultOrder) {
    for (NSDictionary *d in allDescs) {
      if ([d[@"tag"] isEqual:tag]) {
        [self.tabDescriptors addObject:d];
        break;
      }
    }
  }
  [self.tableView reloadData];
}

- (NSArray *)defaultDescriptors {
  return @[
    @{@"tag": @0, @"title": TR(@"Tab_App"),     @"icon": @"list.bullet"},
    @{@"tag": @1, @"title": TR(@"Tab_Mod"),     @"icon": @"hammer"},
    @{@"tag": @2, @"title": TR(@"Tab_Patch"),   @"icon": @"cpu"},
    @{@"tag": @3, @"title": TR(@"Tab_Toolbox"), @"icon": @"briefcase"},
    @{@"tag": @4, @"title": TR(@"Tab_Set"),     @"icon": @"gear"},
  ];
}

@end

@interface VMRootViewController () <UITabBarControllerDelegate>
@property(nonatomic, strong) NSArray<UINavigationController *> *allNavControllers;
@end
@implementation VMRootViewController
- (void)viewDidLoad {
  [super viewDidLoad];
  VMAppSelectViewController *vc1 = [[VMAppSelectViewController alloc] init];
  UINavigationController *nav1 =
      [[UINavigationController alloc] initWithRootViewController:vc1];
  nav1.tabBarItem = [[UITabBarItem alloc]
      initWithTitle:TR(@"Tab_App")
              image:[UIImage systemImageNamed:@"list.bullet"]
                tag:0];

  VMModifierViewController *vc2 = [[VMModifierViewController alloc] init];
  UINavigationController *nav2 =
      [[UINavigationController alloc] initWithRootViewController:vc2];
  nav2.tabBarItem =
      [[UITabBarItem alloc] initWithTitle:TR(@"Tab_Mod")
                                    image:[UIImage systemImageNamed:@"hammer"]
                                      tag:1];

  VMPatcherViewController *vcPatch = [[VMPatcherViewController alloc] init];
  UINavigationController *navPatch =
      [[UINavigationController alloc] initWithRootViewController:vcPatch];
  navPatch.tabBarItem =
      [[UITabBarItem alloc] initWithTitle:TR(@"Tab_Patch")
                                    image:[UIImage systemImageNamed:@"cpu"]
                                      tag:2];

  VMLockListViewController *vc4 = [[VMLockListViewController alloc] init];
  UINavigationController *nav4 =
      [[UINavigationController alloc] initWithRootViewController:vc4];
  nav4.tabBarItem = [[UITabBarItem alloc]
      initWithTitle:TR(@"Tab_Toolbox")
              image:[UIImage systemImageNamed:@"briefcase"]
                tag:3];

  VMSettingsViewController *vc5 = [[VMSettingsViewController alloc] init];
  UINavigationController *nav5 =
      [[UINavigationController alloc] initWithRootViewController:vc5];
  nav5.tabBarItem =
      [[UITabBarItem alloc] initWithTitle:TR(@"Tab_Set")
                                    image:[UIImage systemImageNamed:@"gear"]
                                      tag:4];

  self.allNavControllers = @[ nav1, nav2, navPatch, nav4, nav5 ];
  
  [self applyTabOrder];
  self.delegate = self;

  if ([[VMMemoryEngine shared] respondsToSelector:@selector(switchContext:)]) {
    [[VMMemoryEngine shared] switchContext:@"mod"];
  }

  [[NSNotificationCenter defaultCenter]
      addObserver:self
         selector:@selector(handleUpdateBadge)
             name:kVMUpdateAvailableNotification
           object:nil];
  
  [[NSNotificationCenter defaultCenter]
      addObserver:self
         selector:@selector(handleJumpToTab:)
             name:@"VM_JUMP_TO_TAB"
           object:nil];
  
  UILongPressGestureRecognizer *lp =
      [[UILongPressGestureRecognizer alloc] initWithTarget:self
                                                    action:@selector(handleTabBarLongPress:)];
  lp.minimumPressDuration = 0.5;
  [self.tabBar addGestureRecognizer:lp];
  
  [[VMUpdateManager shared] performAutoCheck];
}

- (BOOL)shouldAutorotate {
  return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
  if ([[UIDevice currentDevice] userInterfaceIdiom] ==
      UIUserInterfaceIdiomPad) {
    return UIInterfaceOrientationMaskAll;
  }
  return UIInterfaceOrientationMaskAll;
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - [v2.6] Tab 排序

- (void)applyTabOrder {
  NSArray<NSNumber *> *savedOrder = [[NSUserDefaults standardUserDefaults] arrayForKey:kVMTabOrderKey];
  if (!savedOrder || savedOrder.count != self.allNavControllers.count) {
    
    self.viewControllers = [self.allNavControllers copy];
    return;
  }
  NSMutableArray *ordered = [NSMutableArray arrayWithCapacity:savedOrder.count];
  for (NSNumber *tag in savedOrder) {
    NSInteger t = tag.integerValue;
    if (t >= 0 && t < (NSInteger)self.allNavControllers.count) {
      [ordered addObject:self.allNavControllers[t]];
    }
  }
  if (ordered.count == self.allNavControllers.count) {
    self.viewControllers = ordered;
  } else {
    self.viewControllers = [self.allNavControllers copy];
  }
}

- (void)handleTabBarLongPress:(UILongPressGestureRecognizer *)gesture {
  if (gesture.state != UIGestureRecognizerStateBegan) return;
  
  UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
  [gen impactOccurred];
  
  [self showTabReorder];
}

- (void)showTabReorder {
  VMTabReorderViewController *reorderVC = [[VMTabReorderViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
  
  NSMutableArray<NSDictionary *> *descs = [NSMutableArray array];
  for (UIViewController *vc in self.viewControllers) {
    NSInteger tag = vc.tabBarItem.tag;
    NSString *title = vc.tabBarItem.title ?: @"";
    NSString *icon = @"questionmark";
    switch (tag) {
      case 0: icon = @"list.bullet"; break;
      case 1: icon = @"hammer"; break;
      case 2: icon = @"cpu"; break;
      case 3: icon = @"briefcase"; break;
      case 4: icon = @"gear"; break;
    }
    [descs addObject:@{@"tag": @(tag), @"title": title, @"icon": icon}];
  }
  reorderVC.tabDescriptors = descs;
  
  __weak VMRootViewController *weakSelf = self;
  reorderVC.onDone = ^(NSArray<NSNumber *> *newOrder) {
    [weakSelf applyTabOrder];
    
    [weakSelf handleUpdateBadge];
  };
  
  UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:reorderVC];
  nav.modalPresentationStyle = UIModalPresentationFormSheet;
  if (@available(iOS 15.0, *)) {
    nav.sheetPresentationController.detents = @[
      UISheetPresentationControllerDetent.mediumDetent,
      UISheetPresentationControllerDetent.largeDetent
    ];
    nav.sheetPresentationController.prefersGrabberVisible = YES;
  }
  [self presentViewController:nav animated:YES completion:nil];
}

- (NSInteger)indexForTabTag:(NSInteger)tag {
  for (NSInteger i = 0; i < (NSInteger)self.viewControllers.count; i++) {
    if (self.viewControllers[i].tabBarItem.tag == tag) return i;
  }
  return NSNotFound;
}

- (void)handleUpdateBadge {
  dispatch_async(dispatch_get_main_queue(), ^{
    if ([VMUpdateManager shared].hasNewVersion) {
      
      NSInteger settingsIdx = [self indexForTabTag:4];
      if (settingsIdx != NSNotFound && settingsIdx < (NSInteger)self.tabBar.items.count) {
        UITabBarItem *settingsItem = self.tabBar.items[settingsIdx];
        settingsItem.badgeValue = @"1";
        settingsItem.badgeColor = [UIColor systemRedColor];
      }
    }
  });
}

- (void)handleJumpToTab:(NSNotification *)notification {
  NSDictionary *info = notification.userInfo;
  NSInteger targetTab = [info[@"targetTab"] integerValue];
  
  dispatch_async(dispatch_get_main_queue(), ^{
    
    if (targetTab >= 2 && targetTab <= 6) {
      
      NSInteger toolboxIdx = [self indexForTabTag:3];
      if (toolboxIdx != NSNotFound) {
        self.selectedIndex = toolboxIdx;
      }
    }
  });
}

- (void)viewDidAppear:(BOOL)animated {
  [super viewDidAppear:animated];
  [self showDisclaimerIfNeeded];
}

- (void)showDisclaimerIfNeeded {
  
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  if ([defaults boolForKey:@"has_agreed_disclaimer"]) {
    return; 
  }

  NSString *disTitle = TR(@"Dis_Title");
  NSString *disMsg = TR(@"Dis_Msg");

  CGFloat fontSize = 13.0;
  NSMutableParagraphStyle *paragraphStyle =
      [[NSMutableParagraphStyle alloc] init];
  paragraphStyle.alignment = NSTextAlignmentLeft;
  paragraphStyle.lineBreakMode = NSLineBreakByWordWrapping;

  NSDictionary *attrDict = @{
    NSForegroundColorAttributeName : [UIColor labelColor],
    NSParagraphStyleAttributeName : paragraphStyle,
    NSFontAttributeName : [UIFont systemFontOfSize:fontSize
                                            weight:UIFontWeightRegular]
  };
  NSAttributedString *attributedMsg =
      [[NSAttributedString alloc] initWithString:disMsg attributes:attrDict];

  UIAlertController *alert =
      [UIAlertController alertControllerWithTitle:disTitle
                                          message:@""
                                   preferredStyle:UIAlertControllerStyleAlert];
  [alert setValue:attributedMsg forKey:@"attributedMessage"];

  [alert addAction:[UIAlertAction
                       actionWithTitle:TR(@"Dis_Agree")
                                 style:UIAlertActionStyleDefault
                               handler:^(UIAlertAction *action) {
                                 
                                 [defaults setBool:YES
                                            forKey:@"has_agreed_disclaimer"];
                                 [defaults synchronize];
                               }]];
  [alert addAction:[UIAlertAction actionWithTitle:TR(@"Dis_Exit")
                                            style:UIAlertActionStyleDestructive
                                          handler:^(UIAlertAction *action) {
                                            exit(0);
                                          }]];

  [self presentViewController:alert animated:YES completion:nil];
}

- (void)showDisclaimer:(BOOL)isReadOnly {
  NSString *disTitle = TR(@"Dis_Title");
  NSString *disMsg = TR(@"Dis_Msg");

  CGFloat fontSize = 13.0;
  NSMutableParagraphStyle *paragraphStyle =
      [[NSMutableParagraphStyle alloc] init];
  paragraphStyle.alignment = NSTextAlignmentLeft;
  paragraphStyle.lineBreakMode = NSLineBreakByWordWrapping;

  NSDictionary *attrDict = @{
    NSForegroundColorAttributeName : [UIColor labelColor],
    NSParagraphStyleAttributeName : paragraphStyle,
    NSFontAttributeName : [UIFont systemFontOfSize:fontSize
                                            weight:UIFontWeightRegular]
  };
  NSAttributedString *attributedMsg =
      [[NSAttributedString alloc] initWithString:disMsg attributes:attrDict];

  UIAlertController *alert =
      [UIAlertController alertControllerWithTitle:disTitle
                                          message:@""
                                   preferredStyle:UIAlertControllerStyleAlert];
  [alert setValue:attributedMsg forKey:@"attributedMessage"];

  if (isReadOnly) {
    
    [alert addAction:[UIAlertAction actionWithTitle:TR(@"Btn_OK")
                                              style:UIAlertActionStyleDefault
                                            handler:nil]];
  } else {
    
    [alert addAction:[UIAlertAction
                         actionWithTitle:TR(@"Dis_Agree")
                                   style:UIAlertActionStyleDefault
                                 handler:^(UIAlertAction *action) {
                                   NSUserDefaults *defaults =
                                       [NSUserDefaults standardUserDefaults];
                                   [defaults setBool:YES
                                              forKey:@"has_agreed_disclaimer"];
                                   [defaults synchronize];
                                 }]];
    [alert
        addAction:[UIAlertAction actionWithTitle:TR(@"Dis_Exit")
                                           style:UIAlertActionStyleDestructive
                                         handler:^(UIAlertAction *action) {
                                           exit(0);
                                         }]];
  }

  [self presentViewController:alert animated:YES completion:nil];
}

- (void)tabBarController:(UITabBarController *)tabBarController
    didSelectViewController:(UIViewController *)viewController {
  
  NSInteger tag = viewController.tabBarItem.tag;
  if (tag == 0) {
    UINavigationController *nav = (UINavigationController *)viewController;
    if ([nav.topViewController
            isKindOfClass:[VMAppSelectViewController class]]) {
      VMAppSelectViewController *appVC =
          (VMAppSelectViewController *)nav.topViewController;
      if ([appVC respondsToSelector:@selector(loadProcesses)]) {
        [appVC performSelector:@selector(loadProcesses)];
      }
    }
  }
}

@end
