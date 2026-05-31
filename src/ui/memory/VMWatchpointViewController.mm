 
#import "VMWatchpointViewController.h"
#import "../../core/VMDebugEngine.h"
#import "../../utils/helpers/VMUIHelper.h"
#import "include/VMLocalization.h"
#import "include/VMMemoryEngine.h"
#import "include/VMRVAPatch.h"
#import <objc/runtime.h>
#include <mach/mach.h>

extern "C" kern_return_t mach_vm_protect(vm_map_t, mach_vm_address_t,
                                         mach_vm_size_t, boolean_t, vm_prot_t);

#define TR(key) ([[VMLocalization shared] localizedString:key])

#pragma mark - Main ViewController

@interface VMWatchpointViewController () <UITableViewDelegate, UITableViewDataSource>

@property (nonatomic, strong) UISegmentedControl *segControl;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIView *headerCard;

@property (nonatomic, strong) NSMutableArray<VMWatchHit *> *hits;
@property (nonatomic, assign) BOOL isAttached;

@property (nonatomic, strong) UIView *inspectorOverlay;
@property (nonatomic, assign) CGFloat inspectorPanelOriginY;
@end

@implementation VMWatchpointViewController

- (void)viewDidLoad {
  [super viewDidLoad];
  self.title = TR(@"WP_Page_Title");
  self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
  self.hits = [NSMutableArray array];

  self.navigationItem.rightBarButtonItem =
      [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"info.circle"]
                                       style:UIBarButtonItemStylePlain
                                      target:self
                                      action:@selector(showHelp)];

  [self setupUI];
  [self setupHitCallback];

  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleProcessDetached)
                                               name:@"VMProcessChangedNotification" object:nil];

  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillShow:)
                                               name:UIKeyboardWillShowNotification object:nil];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillHide:)
                                               name:UIKeyboardWillHideNotification object:nil];

  if (self.initialAddress != 0) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
      VMDebugEngine *engine = [VMDebugEngine shared];

      mach_port_t currentTask = [VMMemoryEngine shared].targetTask;
      if (engine.isAttached && currentTask != engine.currentTask) {
        [engine detach];
      }

      if (!engine.isAttached) {
        if (currentTask == MACH_PORT_NULL) {
          [self showToast:TR(@"Err_Not_Connected")];
          return;
        }
        if (![engine attach]) {
          [self showToast:TR(@"WP_Attach_Fail")];
          return;
        }
        [self updateUI];
        [self.tableView reloadData];
      }
      
      [self addWatchForAddress:self.initialAddress];
    });
  }
}

- (void)viewWillDisappear:(BOOL)animated {
  [super viewWillDisappear:animated];
  
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  
  [VMDebugEngine shared].hitCallback = nil;
}

- (void)handleProcessDetached {
  VMDebugEngine *engine = [VMDebugEngine shared];
  if (engine.isAttached) {
    [engine detach];
  }
  [self.hits removeAllObjects];
  [self updateUI];
  [self.tableView reloadData];
}

#pragma mark - UI Setup

- (void)setupUI {
  
  self.headerCard = [self makeCard];
  [self.view addSubview:self.headerCard];
  self.headerCard.translatesAutoresizingMaskIntoConstraints = NO;

  self.statusLabel = [[UILabel alloc] init];
  self.statusLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightMedium];
  self.statusLabel.textColor = [UIColor secondaryLabelColor];
  self.statusLabel.numberOfLines = 2;
  self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
  [self.headerCard addSubview:self.statusLabel];

  UIButton *attachBtn = [UIButton buttonWithType:UIButtonTypeSystem];
  attachBtn.tag = 100;
  attachBtn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
  attachBtn.layer.cornerRadius = 8;
  attachBtn.translatesAutoresizingMaskIntoConstraints = NO;
  [attachBtn addTarget:self action:@selector(toggleAttach) forControlEvents:UIControlEventTouchUpInside];
  [self.headerCard addSubview:attachBtn];

  [NSLayoutConstraint activateConstraints:@[
    [self.headerCard.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:12],
    [self.headerCard.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
    [self.headerCard.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
    [self.headerCard.heightAnchor constraintEqualToConstant:64],
    [self.statusLabel.leadingAnchor constraintEqualToAnchor:self.headerCard.leadingAnchor constant:14],
    [self.statusLabel.centerYAnchor constraintEqualToAnchor:self.headerCard.centerYAnchor],
    [self.statusLabel.trailingAnchor constraintEqualToAnchor:attachBtn.leadingAnchor constant:-8],
    [attachBtn.trailingAnchor constraintEqualToAnchor:self.headerCard.trailingAnchor constant:-14],
    [attachBtn.centerYAnchor constraintEqualToAnchor:self.headerCard.centerYAnchor],
    [attachBtn.widthAnchor constraintEqualToConstant:80],
    [attachBtn.heightAnchor constraintEqualToConstant:34],
  ]];

  self.segControl = [[UISegmentedControl alloc] initWithItems:@[
    TR(@"WP_Seg_Slots"), TR(@"WP_Seg_Hits")
  ]];
  self.segControl.selectedSegmentIndex = 0;
  self.segControl.translatesAutoresizingMaskIntoConstraints = NO;
  [self.segControl addTarget:self action:@selector(segChanged) forControlEvents:UIControlEventValueChanged];
  [self.view addSubview:self.segControl];

  UIStackView *btnRow = [[UIStackView alloc] init];
  btnRow.axis = UILayoutConstraintAxisHorizontal;
  btnRow.spacing = 10;
  btnRow.distribution = UIStackViewDistributionFillEqually;
  btnRow.translatesAutoresizingMaskIntoConstraints = NO;
  [self.view addSubview:btnRow];

  UIButton *addBtn = [self actionButton:TR(@"WP_Add") color:[UIColor systemBlueColor] action:@selector(addWatch)];
  UIButton *clearBtn = [self actionButton:TR(@"WP_Clear") color:[UIColor systemRedColor] action:@selector(clearAll)];
  [btnRow addArrangedSubview:addBtn];
  [btnRow addArrangedSubview:clearBtn];

  self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
  self.tableView.delegate = self;
  self.tableView.dataSource = self;
  self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
  self.tableView.backgroundColor = [UIColor clearColor];
  [self.view addSubview:self.tableView];

  [NSLayoutConstraint activateConstraints:@[
    [self.segControl.topAnchor constraintEqualToAnchor:self.headerCard.bottomAnchor constant:12],
    [self.segControl.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
    [self.segControl.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
    [btnRow.topAnchor constraintEqualToAnchor:self.segControl.bottomAnchor constant:10],
    [btnRow.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
    [btnRow.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
    [btnRow.heightAnchor constraintEqualToConstant:38],
    [self.tableView.topAnchor constraintEqualToAnchor:btnRow.bottomAnchor constant:8],
    [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
  ]];

  [self updateUI];
}

- (UIView *)makeCard {
  UIView *card = [[UIView alloc] init];
  card.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
  card.layer.cornerRadius = 12;
  return card;
}

- (UIButton *)actionButton:(NSString *)title color:(UIColor *)color action:(SEL)sel {
  UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
  [btn setTitle:title forState:UIControlStateNormal];
  [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
  btn.backgroundColor = color;
  btn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
  btn.layer.cornerRadius = 10;
  [btn addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
  return btn;
}

#pragma mark - State Management

- (void)setupHitCallback {
  __weak VMWatchpointViewController *ws = self;
  [VMDebugEngine shared].hitCallback = ^(VMWatchHit *hit) {
    VMWatchpointViewController *ss = ws;
    if (!ss) return;
    [ss.hits insertObject:hit atIndex:0];
    if (ss.hits.count > 200) {
      [ss.hits removeObjectsInRange:NSMakeRange(200, ss.hits.count - 200)];
    }
    [ss updateUI];
    if (ss.segControl.selectedSegmentIndex == 1) {
      [ss.tableView reloadData];
    } else {
      
      [ss.tableView reloadData];
    }
  };
}

- (void)updateUI {
  VMDebugEngine *engine = [VMDebugEngine shared];
  self.isAttached = engine.isAttached;

  UIButton *attachBtn = [self.headerCard viewWithTag:100];
  if (self.isAttached) {
    [attachBtn setTitle:TR(@"WP_Detach") forState:UIControlStateNormal];
    [attachBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    attachBtn.backgroundColor = [UIColor systemOrangeColor];
    self.statusLabel.text = [NSString stringWithFormat:@"%@ %u/%u  |  %@ %lu",
      TR(@"WP_Active"), engine.activeCount, engine.maxSlots,
      TR(@"WP_Hits_Label"), (unsigned long)self.hits.count];
  } else {
    [attachBtn setTitle:TR(@"WP_Attach") forState:UIControlStateNormal];
    [attachBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    attachBtn.backgroundColor = [UIColor systemGreenColor];
    self.statusLabel.text = TR(@"WP_Status_Idle");
  }
}

- (void)segChanged {
  [self.tableView reloadData];
}

#pragma mark - Actions

- (void)toggleAttach {
  VMDebugEngine *engine = [VMDebugEngine shared];
  if (engine.isAttached) {
    [engine detach];
    [self.hits removeAllObjects];
    [self updateUI];
    [self.tableView reloadData];
    [self showToast:TR(@"WP_Detached")];
    return;
  }
  if ([VMMemoryEngine shared].targetTask == MACH_PORT_NULL) {
    [self showToast:TR(@"Err_Not_Connected")];
    return;
  }
  if ([engine attach]) {
    [self updateUI];
    [self.tableView reloadData];
    [self showToast:TR(@"WP_Attached")];
  } else {
    [self showToast:TR(@"WP_Attach_Fail")];
  }
}

- (void)addWatch {
  VMDebugEngine *engine = [VMDebugEngine shared];
  if (!engine.isAttached) {
    [self showToast:TR(@"WP_Not_Attached")];
    return;
  }
  if (engine.activeCount >= engine.maxSlots) {
    [self showToast:TR(@"WP_Max_Slots")];
    return;
  }

  UIAlertController *ac = [UIAlertController alertControllerWithTitle:TR(@"WP_Add")
    message:TR(@"WP_Add_Msg") preferredStyle:UIAlertControllerStyleAlert];

  [ac addTextFieldWithConfigurationHandler:^(UITextField *tf) {
    tf.placeholder = @"0x...";
    tf.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightRegular];
    tf.keyboardType = UIKeyboardTypeASCIICapable;
  }];

  [ac addAction:[UIAlertAction actionWithTitle:TR(@"Btn_Cancel") style:UIAlertActionStyleCancel handler:nil]];
  [ac addAction:[UIAlertAction actionWithTitle:TR(@"Btn_OK") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
    NSString *addrStr = ac.textFields[0].text;
    uint64_t addr = strtoull(addrStr.UTF8String, NULL, 16);
    if (addr == 0) { [self showToast:TR(@"WP_Err_Addr")]; return; }

    int slot = [engine addWatchpoint:addr type:VMWatchTypeWrite size:VMWatchSizeByte4];
    if (slot >= 0) {
      [self showToast:[NSString stringWithFormat:@"%@ [%d] 0x%llX", TR(@"WP_Added"), slot, addr]];
      [self updateUI];
      [self.tableView reloadData];
    } else {
      [self showToast:TR(@"WP_Add_Fail")];
    }
  }]];
  [self presentViewController:ac animated:YES completion:nil];
}

- (void)addWatchForAddress:(uint64_t)addr {
  VMDebugEngine *engine = [VMDebugEngine shared];
  if (!engine.isAttached) return;
  if (engine.activeCount >= engine.maxSlots) {
    [self showToast:TR(@"WP_Max_Slots")];
    return;
  }
  int slot = [engine addWatchpoint:addr type:VMWatchTypeWrite size:VMWatchSizeByte4];
  if (slot >= 0) {
    [self showToast:[NSString stringWithFormat:@"%@ [%d] 0x%llX", TR(@"WP_Added"), slot, addr]];
    [self updateUI];
    [self.tableView reloadData];
  }
}

- (void)clearAll {
  UIAlertController *ac = [UIAlertController alertControllerWithTitle:TR(@"WP_Clear")
    message:TR(@"WP_Clear_Msg") preferredStyle:UIAlertControllerStyleAlert];
  [ac addAction:[UIAlertAction actionWithTitle:TR(@"Btn_Cancel") style:UIAlertActionStyleCancel handler:nil]];
  [ac addAction:[UIAlertAction actionWithTitle:TR(@"Btn_Confirm") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
    [[VMDebugEngine shared] removeAllWatchpoints];
    [self.hits removeAllObjects];
    [self updateUI];
    [self.tableView reloadData];
    [self showToast:TR(@"WP_Cleared")];
  }]];
  [self presentViewController:ac animated:YES completion:nil];
}

- (void)removeSlot:(UIButton *)sender {
  NSNumber *idx = objc_getAssociatedObject(sender, "slotIdx");
  if (!idx) return;
  [[VMDebugEngine shared] removeWatchpoint:[idx unsignedIntValue]];
  [self updateUI];
  [self.tableView reloadData];
  [self showToast:TR(@"WP_Removed")];
}

- (void)showHelp {
  UIAlertController *ac = [UIAlertController alertControllerWithTitle:TR(@"WP_Page_Title")
    message:TR(@"WP_Help_Msg") preferredStyle:UIAlertControllerStyleAlert];
  [ac addAction:[UIAlertAction actionWithTitle:TR(@"Btn_OK") style:UIAlertActionStyleDefault handler:nil]];
  [self presentViewController:ac animated:YES completion:nil];
}

#pragma mark - TableView DataSource

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
  if (tv == self.tableView) {
    if (self.segControl.selectedSegmentIndex == 0) return [VMDebugEngine shared].maxSlots;
    return self.hits.count;
  }
  
  NSArray *lines = objc_getAssociatedObject(tv, "dasmLines");
  return lines ? (NSInteger)lines.count : 0;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
  
  if (tv != self.tableView) return [self dasmCellForTable:tv indexPath:ip];

  if (self.segControl.selectedSegmentIndex == 0) return [self slotCellForIndex:ip];
  return [self hitCellForIndex:ip];
}

- (UITableViewCell *)slotCellForIndex:(NSIndexPath *)ip {
  UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:@"Slot"];
  if (!cell) {
    cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"Slot"];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.textLabel.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightBold];
    cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    UIButton *del = [UIButton buttonWithType:UIButtonTypeSystem];
    del.tag = 200;
    [del setImage:[UIImage systemImageNamed:@"xmark.circle.fill"] forState:UIControlStateNormal];
    del.tintColor = [UIColor systemRedColor];
    [del addTarget:self action:@selector(removeSlot:) forControlEvents:UIControlEventTouchUpInside];
    del.translatesAutoresizingMaskIntoConstraints = NO;
    [cell.contentView addSubview:del];
    [NSLayoutConstraint activateConstraints:@[
      [del.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16],
      [del.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
      [del.widthAnchor constraintEqualToConstant:28],
      [del.heightAnchor constraintEqualToConstant:28],
    ]];
  }

  uint32_t idx = (uint32_t)ip.row;
  VMDebugEngine *engine = [VMDebugEngine shared];
  BOOL active = [engine isSlotActive:idx];
  UIButton *del = [cell.contentView viewWithTag:200];

  if (active) {
    uint64_t addr = [engine slotAddress:idx];
    NSArray *hits = [engine hitsForSlot:idx];
    cell.textLabel.text = [NSString stringWithFormat:@"[%u] 0x%llX", idx, addr];
    cell.textLabel.textColor = [UIColor systemBlueColor];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ %lu", TR(@"WP_Hits_Label"), (unsigned long)hits.count];
    del.hidden = NO;
  } else {
    cell.textLabel.text = [NSString stringWithFormat:@"[%u] %@", idx, TR(@"WP_Empty")];
    cell.textLabel.textColor = [UIColor tertiaryLabelColor];
    cell.detailTextLabel.text = @"--";
    del.hidden = YES;
  }
  objc_setAssociatedObject(del, "slotIdx", @(idx), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  return cell;
}

- (UITableViewCell *)hitCellForIndex:(NSIndexPath *)ip {
  UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:@"Hit"];
  if (!cell) {
    cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"Hit"];
    cell.textLabel.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightBold];
    cell.textLabel.textColor = [UIColor systemBlueColor];
    cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    cell.detailTextLabel.numberOfLines = 2;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
  }
  if (ip.row < (NSInteger)self.hits.count) {
    VMWatchHit *hit = self.hits[ip.row];
    cell.textLabel.text = [NSString stringWithFormat:@"%@ + 0x%llX", hit.imageName, hit.offset];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"PC: 0x%llX | Val: %llu (0x%llX)\nAddr: 0x%llX | Slot: %u",
      hit.pc, hit.newValue, hit.newValue, hit.address, hit.slotIndex];
  }
  return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
  if (tv != self.tableView) {
    
    [self dasmTableDidSelect:tv indexPath:ip];
    return;
  }

  if (self.segControl.selectedSegmentIndex == 0) {
    
    [tv deselectRowAtIndexPath:ip animated:YES];
    uint32_t slotIdx = (uint32_t)ip.row;
    if (![[VMDebugEngine shared] isSlotActive:slotIdx]) return;
    
    NSInteger hitRow = -1;
    for (NSInteger i = 0; i < (NSInteger)self.hits.count; i++) {
      if (self.hits[i].slotIndex == slotIdx) { hitRow = i; break; }
    }
    if (hitRow < 0) {
      [self showToast:TR(@"WP_No_Hits_Yet")];
      return;
    }
    
    self.segControl.selectedSegmentIndex = 1;
    [self.tableView reloadData];
    [self.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:hitRow inSection:0]
                          atScrollPosition:UITableViewScrollPositionMiddle animated:YES];
    return;
  }

  if (ip.row >= (NSInteger)self.hits.count) return;
  [tv deselectRowAtIndexPath:ip animated:YES];
  [self showInspectorForHit:self.hits[ip.row]];
}

- (CGFloat)tableView:(UITableView *)tv heightForRowAtIndexPath:(NSIndexPath *)ip {
  if (tv != self.tableView) return 26; 
  return (self.segControl.selectedSegmentIndex == 0) ? 52 : 60;
}

#pragma mark - Disassembly Inspector

- (void)showInspectorForHit:(VMWatchHit *)hit {
  NSArray<NSDictionary *> *lines = [[VMDebugEngine shared] disassembleFunctionAt:hit.pc
                                                                      moduleName:hit.imageName];

  UIView *overlay = [[UIView alloc] initWithFrame:self.view.bounds];
  overlay.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.5];
  overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  self.inspectorOverlay = overlay;

  CGFloat sw = self.view.bounds.size.width;
  CGFloat sh = self.view.bounds.size.height;
  CGFloat pw = MIN(sw - 24, 520);
  CGFloat ph = MIN(sh - 40, 680);
  
  if (sh < sw) ph = MAX(sh - 20, 320);

  UIView *panel = [[UIView alloc] initWithFrame:CGRectMake((sw-pw)/2, (sh-ph)/2, pw, ph)];
  panel.backgroundColor = [UIColor systemBackgroundColor];
  panel.layer.cornerRadius = 16;
  panel.layer.shadowColor = [UIColor blackColor].CGColor;
  panel.layer.shadowRadius = 20;
  panel.layer.shadowOpacity = 0.3;
  panel.layer.shadowOffset = CGSizeMake(0, 4);
  panel.clipsToBounds = NO;
  panel.tag = 500;
  [overlay addSubview:panel];

  UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
  closeBtn.frame = CGRectMake(pw - 44, 4, 40, 40);
  [closeBtn setImage:[UIImage systemImageNamed:@"xmark.circle.fill"] forState:UIControlStateNormal];
  closeBtn.tintColor = [UIColor secondaryLabelColor];
  [closeBtn addTarget:self action:@selector(dismissInspector) forControlEvents:UIControlEventTouchUpInside];
  [panel addSubview:closeBtn];

  UILabel *titleLbl = [[UILabel alloc] initWithFrame:CGRectMake(16, 10, pw - 60, 20)];
  titleLbl.text = TR(@"WP_Inspector_Title");
  titleLbl.font = [UIFont systemFontOfSize:15 weight:UIFontWeightBold];
  titleLbl.textColor = [UIColor labelColor];
  [panel addSubview:titleLbl];

  UILabel *infoLbl = [[UILabel alloc] initWithFrame:CGRectMake(16, 32, pw - 32, 36)];
  infoLbl.numberOfLines = 2;
  infoLbl.font = [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];
  infoLbl.textColor = [UIColor secondaryLabelColor];
  infoLbl.text = [NSString stringWithFormat:@"%@ + 0x%llX  PC: 0x%llX\nValue: %llu (0x%llX)  Addr: 0x%llX",
    hit.imageName, hit.offset, hit.pc, hit.newValue, hit.newValue, hit.address];
  [panel addSubview:infoLbl];

  CGFloat tableTop = 72;
  CGFloat toolbarH = 90;
  CGFloat bottomH = 44;
  CGFloat tableH = ph - tableTop - toolbarH - bottomH - 12;

  UITableView *dasmTable = [[UITableView alloc] initWithFrame:CGRectMake(8, tableTop, pw - 16, tableH)
                                                        style:UITableViewStylePlain];
  dasmTable.backgroundColor = [UIColor secondarySystemBackgroundColor];
  dasmTable.separatorStyle = UITableViewCellSeparatorStyleNone;
  dasmTable.layer.cornerRadius = 10;
  dasmTable.clipsToBounds = YES;
  dasmTable.tag = 501;
  dasmTable.delegate = self;
  dasmTable.dataSource = self;
  objc_setAssociatedObject(dasmTable, "dasmLines", lines, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  objc_setAssociatedObject(dasmTable, "dasmHit", hit, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  [panel addSubview:dasmTable];

  NSInteger pcRow = -1;
  for (NSInteger i = 0; i < (NSInteger)lines.count; i++) {
    if ([lines[i][@"isPC"] boolValue]) { pcRow = i; break; }
  }
  if (pcRow >= 0) {
    dispatch_async(dispatch_get_main_queue(), ^{
      [dasmTable scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:pcRow inSection:0]
                       atScrollPosition:UITableViewScrollPositionMiddle animated:NO];
    });
  }

  CGFloat tbY = tableTop + tableH + 4;
  UIView *toolbar = [[UIView alloc] initWithFrame:CGRectMake(8, tbY, pw - 16, toolbarH)];
  toolbar.backgroundColor = [UIColor tertiarySystemBackgroundColor];
  toolbar.layer.cornerRadius = 10;
  toolbar.tag = 502;
  [panel addSubview:toolbar];

  UILabel *selLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 4, toolbar.bounds.size.width - 20, 16)];
  selLabel.tag = 503;
  selLabel.font = [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];
  selLabel.textColor = [UIColor tertiaryLabelColor];
  selLabel.text = TR(@"WP_Tap_Instruction");
  selLabel.userInteractionEnabled = YES;
  UITapGestureRecognizer *selTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onSelLabelTapped:)];
  [selLabel addGestureRecognizer:selTap];
  [toolbar addSubview:selLabel];

  CGFloat inputW = toolbar.bounds.size.width - 90;
  UITextField *patchField = [[UITextField alloc] initWithFrame:CGRectMake(10, 24, inputW, 30)];
  patchField.tag = 504;
  patchField.placeholder = @"HEX (e.g. 1F2003D5)";
  patchField.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
  patchField.textColor = [UIColor labelColor];
  patchField.backgroundColor = [UIColor systemBackgroundColor];
  patchField.layer.cornerRadius = 8;
  patchField.layer.borderWidth = 0.5;
  patchField.layer.borderColor = [UIColor separatorColor].CGColor;
  patchField.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 8, 30)];
  patchField.leftViewMode = UITextFieldViewModeAlways;
  patchField.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
  patchField.autocorrectionType = UITextAutocorrectionTypeNo;
  patchField.enabled = NO;
  
  UIToolbar *kbToolbar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, 320, 44)];
  kbToolbar.barStyle = UIBarStyleDefault;
  UIBarButtonItem *flex = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
  UIBarButtonItem *doneItem = [[UIBarButtonItem alloc] initWithTitle:TR(@"Common_Done") style:UIBarButtonItemStyleDone target:patchField action:@selector(resignFirstResponder)];
  kbToolbar.items = @[flex, doneItem];
  patchField.inputAccessoryView = kbToolbar;
  [toolbar addSubview:patchField];

  UIButton *applyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
  applyBtn.frame = CGRectMake(toolbar.bounds.size.width - 74, 24, 64, 30);
  applyBtn.tag = 505;
  [applyBtn setTitle:TR(@"Btn_Apply") forState:UIControlStateNormal];
  [applyBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
  applyBtn.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightBold];
  applyBtn.backgroundColor = [UIColor systemBlueColor];
  applyBtn.layer.cornerRadius = 8;
  applyBtn.enabled = NO;
  applyBtn.alpha = 0.4;
  [applyBtn addTarget:self action:@selector(onApplyPatch:) forControlEvents:UIControlEventTouchUpInside];
  [toolbar addSubview:applyBtn];

  CGFloat qY = 60;
  NSInteger qCount = 5;
  CGFloat qBtnW = (toolbar.bounds.size.width - 20 - (qCount - 1) * 4) / qCount;
  NSArray *qTitles = @[@"NOP", @"RET", @"MOV W0,#0", @"MOV W0,#1", TR(@"WP_Copy_Hex")];
  for (NSInteger i = 0; i < qCount; i++) {
    UIButton *qBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    qBtn.frame = CGRectMake(10 + i * (qBtnW + 4), qY, qBtnW, 24);
    qBtn.tag = 510 + i;
    [qBtn setTitle:qTitles[i] forState:UIControlStateNormal];
    qBtn.titleLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightSemibold];
    qBtn.titleLabel.adjustsFontSizeToFitWidth = YES;
    qBtn.titleLabel.minimumScaleFactor = 0.6;
    qBtn.layer.cornerRadius = 6;
    qBtn.layer.borderWidth = 0.5;
    qBtn.layer.borderColor = [UIColor separatorColor].CGColor;
    qBtn.enabled = NO;
    qBtn.alpha = 0.4;
    [qBtn addTarget:self action:@selector(onQuickAction:) forControlEvents:UIControlEventTouchUpInside];
    [toolbar addSubview:qBtn];
  }

  objc_setAssociatedObject(toolbar, "dasmTable", dasmTable, OBJC_ASSOCIATION_ASSIGN);
  objc_setAssociatedObject(toolbar, "dasmHit", hit, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  objc_setAssociatedObject(toolbar, "panel", panel, OBJC_ASSOCIATION_ASSIGN);
  objc_setAssociatedObject(applyBtn, "toolbar", toolbar, OBJC_ASSOCIATION_ASSIGN);
  for (NSInteger i = 510; i <= 514; i++) {
    UIButton *q = [toolbar viewWithTag:i];
    objc_setAssociatedObject(q, "toolbar", toolbar, OBJC_ASSOCIATION_ASSIGN);
  }

  CGFloat barY = ph - bottomH - 4;
  CGFloat btnW = (pw - 48) / 4;

  UIButton *copyAllBtn = [self bottomBarButton:TR(@"WP_Copy_Disasm") frame:CGRectMake(12, barY, btnW, 36)];
  objc_setAssociatedObject(copyAllBtn, "dasmLines", lines, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  objc_setAssociatedObject(copyAllBtn, "dasmHit", hit, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  [copyAllBtn addTarget:self action:@selector(onCopyAllDisasm:) forControlEvents:UIControlEventTouchUpInside];
  [panel addSubview:copyAllBtn];

  UIButton *copyOffBtn = [self bottomBarButton:TR(@"WP_Copy_Offset") frame:CGRectMake(16 + btnW, barY, btnW, 36)];
  objc_setAssociatedObject(copyOffBtn, "dasmHit", hit, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  [copyOffBtn addTarget:self action:@selector(onCopyOffset:) forControlEvents:UIControlEventTouchUpInside];
  [panel addSubview:copyOffBtn];

  UIButton *rvaBtn = [self bottomBarButton:TR(@"WP_Send_RVA") frame:CGRectMake(20 + btnW * 2, barY, btnW, 36)];
  objc_setAssociatedObject(rvaBtn, "dasmHit", hit, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  [rvaBtn addTarget:self action:@selector(onSendToRVA:) forControlEvents:UIControlEventTouchUpInside];
  [panel addSubview:rvaBtn];

  UIButton *armBtn = [self bottomBarButton:@"ARM Converter" frame:CGRectMake(24 + btnW * 3, barY, btnW, 36)];
  [armBtn setImage:[UIImage systemImageNamed:@"safari"] forState:UIControlStateNormal];
  armBtn.tintColor = [UIColor systemBlueColor];
  [armBtn addTarget:self action:@selector(onOpenARMConverter) forControlEvents:UIControlEventTouchUpInside];
  [panel addSubview:armBtn];

  UITapGestureRecognizer *bgTap = [[UITapGestureRecognizer alloc] initWithTarget:overlay action:@selector(endEditing:)];
  bgTap.cancelsTouchesInView = NO;
  [overlay addGestureRecognizer:bgTap];
  [self.view addSubview:overlay];
  panel.transform = CGAffineTransformMakeScale(0.92, 0.92);
  overlay.alpha = 0;
  [UIView animateWithDuration:0.25 animations:^{
    overlay.alpha = 1;
    panel.transform = CGAffineTransformIdentity;
  }];
}

- (UIButton *)bottomBarButton:(NSString *)title frame:(CGRect)frame {
  UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
  btn.frame = frame;
  [btn setTitle:title forState:UIControlStateNormal];
  btn.titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
  btn.titleLabel.adjustsFontSizeToFitWidth = YES;
  btn.titleLabel.minimumScaleFactor = 0.6;
  btn.layer.cornerRadius = 10;
  btn.layer.borderWidth = 0.5;
  btn.layer.borderColor = [UIColor separatorColor].CGColor;
  btn.backgroundColor = [UIColor secondarySystemBackgroundColor];
  return btn;
}

- (void)dismissInspector {
  UIView *overlay = self.inspectorOverlay;
  if (!overlay) return;
  
  [overlay endEditing:YES];
  [UIView animateWithDuration:0.2 animations:^{
    overlay.alpha = 0;
  } completion:^(BOOL f) {
    [overlay removeFromSuperview];
    self.inspectorOverlay = nil;
  }];
}

#pragma mark - Keyboard Avoidance

- (void)keyboardWillShow:(NSNotification *)note {
  UIView *overlay = self.inspectorOverlay;
  if (!overlay) return;
  UIView *panel = [overlay viewWithTag:500];
  if (!panel) return;

  CGRect kbFrame = [note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
  CGFloat kbTop = kbFrame.origin.y;
  CGFloat panelBottom = panel.frame.origin.y + panel.frame.size.height;
  if (panelBottom > kbTop) {
    CGFloat shift = panelBottom - kbTop + 8;
    NSTimeInterval dur = [note.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    [UIView animateWithDuration:dur animations:^{
      panel.transform = CGAffineTransformMakeTranslation(0, -shift);
    }];
  }
}

- (void)keyboardWillHide:(NSNotification *)note {
  UIView *overlay = self.inspectorOverlay;
  if (!overlay) return;
  UIView *panel = [overlay viewWithTag:500];
  if (!panel) return;
  NSTimeInterval dur = [note.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
  [UIView animateWithDuration:dur animations:^{
    panel.transform = CGAffineTransformIdentity;
  }];
}

- (void)onSelLabelTapped:(UITapGestureRecognizer *)tap {
  UILabel *selLabel = (UILabel *)tap.view;
  UIView *toolbar = selLabel.superview;
  if (!toolbar) return;
  NSString *selHex = objc_getAssociatedObject(toolbar, "selHex");
  if (!selHex.length) return;
  UITextField *pf = [toolbar viewWithTag:504];
  pf.text = selHex;
}

#pragma mark - Disasm Table Cells

- (UITableViewCell *)dasmCellForTable:(UITableView *)tv indexPath:(NSIndexPath *)ip {
  UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"Dasm"];
  if (!cell) {
    cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"Dasm"];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.textLabel.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    cell.textLabel.numberOfLines = 1;
    cell.textLabel.adjustsFontSizeToFitWidth = YES;
    cell.textLabel.minimumScaleFactor = 0.6;
  }
  NSArray<NSDictionary *> *lines = objc_getAssociatedObject(tv, "dasmLines");
  if (ip.row < (NSInteger)lines.count) {
    NSDictionary *l = lines[ip.row];
    BOOL isPC = [l[@"isPC"] boolValue];
    NSNumber *selIdx = objc_getAssociatedObject(tv, "selIdx");
    BOOL isSel = (selIdx && [selIdx integerValue] == ip.row);
    NSString *marker = isPC ? @">" : (isSel ? @"*" : @" ");
    cell.textLabel.text = [NSString stringWithFormat:@"%@ %08llX  %@  %@",
      marker, [l[@"offset"] unsignedLongLongValue], l[@"hex"], l[@"mnemonic"]];
    if (isSel) {
      cell.backgroundColor = [[UIColor systemBlueColor] colorWithAlphaComponent:0.12];
      cell.textLabel.textColor = [UIColor labelColor];
    } else if (isPC) {
      cell.backgroundColor = [[UIColor systemOrangeColor] colorWithAlphaComponent:0.1];
      cell.textLabel.textColor = [UIColor labelColor];
    } else {
      cell.backgroundColor = [UIColor clearColor];
      cell.textLabel.textColor = [UIColor secondaryLabelColor];
    }
  }
  return cell;
}

- (void)dasmTableDidSelect:(UITableView *)tv indexPath:(NSIndexPath *)ip {
  NSArray<NSDictionary *> *lines = objc_getAssociatedObject(tv, "dasmLines");
  if (!lines || ip.row >= (NSInteger)lines.count) return;

  objc_setAssociatedObject(tv, "selIdx", @(ip.row), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  [tv reloadData];

  NSDictionary *line = lines[ip.row];
  
  UIView *panel = tv.superview;
  UIView *toolbar = [panel viewWithTag:502];
  if (!toolbar) return;

  objc_setAssociatedObject(toolbar, "selOffset", line[@"offset"], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  objc_setAssociatedObject(toolbar, "selHex", line[@"hex"], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  objc_setAssociatedObject(toolbar, "selLine", line, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

  UILabel *selLabel = [toolbar viewWithTag:503];
  selLabel.text = [NSString stringWithFormat:@"* 0x%llX  %@  %@",
    [line[@"offset"] unsignedLongLongValue], line[@"hex"], line[@"mnemonic"]];
  selLabel.textColor = [UIColor labelColor];

  UITextField *pf = [toolbar viewWithTag:504];
  pf.enabled = YES;
  UIButton *ab = (UIButton *)[toolbar viewWithTag:505];
  ab.enabled = YES; ab.alpha = 1.0;
  for (NSInteger i = 510; i <= 514; i++) {
    UIButton *q = (UIButton *)[toolbar viewWithTag:i];
    q.enabled = YES; q.alpha = 1.0;
  }
}

#pragma mark - Toolbar Actions

- (void)onApplyPatch:(UIButton *)sender {
  UIView *toolbar = objc_getAssociatedObject(sender, "toolbar");
  if (!toolbar) return;
  UITextField *pf = [toolbar viewWithTag:504];
  NSString *input = [pf.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
  if (!input.length) return;

  NSNumber *offNum = objc_getAssociatedObject(toolbar, "selOffset");
  VMWatchHit *hit = objc_getAssociatedObject(toolbar, "dasmHit");
  if (!offNum || !hit) return;

  NSString *hex = input;
  NSString *upper = [input uppercaseString];
  if ([upper isEqualToString:@"NOP"]) hex = @"1F2003D5";
  else if ([upper isEqualToString:@"RET"]) hex = @"C0035FD6";

  [self patchAtOffset:[offNum unsignedLongLongValue] hex:hex moduleName:hit.imageName];
  pf.text = @"";
  [pf resignFirstResponder];

  [self refreshDisasmInPanel:toolbar.superview hit:hit];
}

- (void)onQuickAction:(UIButton *)sender {
  UIView *toolbar = objc_getAssociatedObject(sender, "toolbar");
  if (!toolbar) return;
  NSNumber *offNum = objc_getAssociatedObject(toolbar, "selOffset");
  NSString *selHex = objc_getAssociatedObject(toolbar, "selHex");
  VMWatchHit *hit = objc_getAssociatedObject(toolbar, "dasmHit");
  if (!offNum || !hit) return;

  UITextField *pf = [toolbar viewWithTag:504];

  switch (sender.tag) {
    case 510: pf.text = @"1F2003D5"; break; 
    case 511: pf.text = @"C0035FD6"; break; 
    case 512: pf.text = @"00008052"; break; 
    case 513: pf.text = @"20008052"; break; 
    case 514: { 
      if (selHex) {
        [UIPasteboard generalPasteboard].string = selHex;
        [self showToast:[NSString stringWithFormat:@"%@ %@", TR(@"Msg_Copy_Success"), selHex]];
      }
      break;
    }
  }
}

#pragma mark - Cross-Process Patching

- (void)patchAtOffset:(uint64_t)offset hex:(NSString *)hexStr moduleName:(NSString *)moduleName {
  mach_port_t task = [VMMemoryEngine shared].targetTask;
  if (task == MACH_PORT_NULL) {
    [self showToast:TR(@"Err_Not_Connected")];
    return;
  }

  uint64_t base = [[VMMemoryEngine shared] findModuleBaseAddress:moduleName];
  if (base == 0) {
    [self showToast:TR(@"WP_Err_Module")];
    return;
  }
  uint64_t absAddr = base + offset;

  NSString *clean = [[hexStr stringByReplacingOccurrencesOfString:@" " withString:@""]
                      uppercaseString];
  if (clean.length == 0 || clean.length % 2 != 0) {
    [self showToast:TR(@"Patch_Hex_Err")];
    return;
  }

  NSMutableData *data = [NSMutableData dataWithCapacity:clean.length / 2];
  for (NSUInteger i = 0; i < clean.length; i += 2) {
    unsigned int byte;
    NSString *byteStr = [clean substringWithRange:NSMakeRange(i, 2)];
    if (![[NSScanner scannerWithString:byteStr] scanHexInt:&byte]) {
      [self showToast:TR(@"Patch_Hex_Err")];
      return;
    }
    uint8_t b = (uint8_t)byte;
    [data appendBytes:&b length:1];
  }

  mach_vm_size_t patchLen = data.length;
  kern_return_t kr = mach_vm_protect(task, absAddr, patchLen, FALSE,
                                     VM_PROT_READ | VM_PROT_WRITE | VM_PROT_EXECUTE);
  if (kr != KERN_SUCCESS) {
    kr = mach_vm_protect(task, absAddr, patchLen, FALSE,
                         VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
  }

  kr = vm_write(task, (vm_address_t)absAddr, (vm_offset_t)data.bytes, (mach_msg_type_number_t)patchLen);
  if (kr == KERN_SUCCESS) {
    
    mach_vm_protect(task, absAddr, patchLen, FALSE,
                    VM_PROT_READ | VM_PROT_EXECUTE);
    [self showToast:TR(@"WP_Patched")];
  } else {
    [self showToast:TR(@"WP_Patch_Fail")];
  }
}

- (void)refreshDisasmInPanel:(UIView *)panel hit:(VMWatchHit *)hit {
  if (!panel) return;
  UITableView *dasmTable = [panel viewWithTag:501];
  if (!dasmTable) return;

  NSArray<NSDictionary *> *newLines = [[VMDebugEngine shared] disassembleFunctionAt:hit.pc
                                                                          moduleName:hit.imageName];
  objc_setAssociatedObject(dasmTable, "dasmLines", newLines, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

  NSNumber *selIdx = objc_getAssociatedObject(dasmTable, "selIdx");
  [dasmTable reloadData];

  if (selIdx && [selIdx integerValue] < (NSInteger)newLines.count) {
    [dasmTable scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:[selIdx integerValue] inSection:0]
                     atScrollPosition:UITableViewScrollPositionMiddle animated:NO];
  }

  UIView *toolbar = [panel viewWithTag:502];
  if (toolbar && selIdx) {
    NSInteger idx = [selIdx integerValue];
    if (idx < (NSInteger)newLines.count) {
      NSDictionary *line = newLines[idx];
      objc_setAssociatedObject(toolbar, "selOffset", line[@"offset"], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
      objc_setAssociatedObject(toolbar, "selHex", line[@"hex"], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
      objc_setAssociatedObject(toolbar, "selLine", line, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

      UILabel *selLabel = [toolbar viewWithTag:503];
      selLabel.text = [NSString stringWithFormat:@"* 0x%llX  %@  %@",
        [line[@"offset"] unsignedLongLongValue], line[@"hex"], line[@"mnemonic"]];
    }
  }

  for (UIView *sub in panel.subviews) {
    if ([sub isKindOfClass:[UIButton class]]) {
      VMWatchHit *btnHit = objc_getAssociatedObject(sub, "dasmHit");
      if (btnHit) {
        NSArray *oldLines = objc_getAssociatedObject(sub, "dasmLines");
        if (oldLines) {
          objc_setAssociatedObject(sub, "dasmLines", newLines, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
      }
    }
  }
}

#pragma mark - Bottom Bar Actions

- (void)onCopyAllDisasm:(UIButton *)sender {
  NSArray<NSDictionary *> *lines = objc_getAssociatedObject(sender, "dasmLines");
  VMWatchHit *hit = objc_getAssociatedObject(sender, "dasmHit");
  if (!lines.count) {
    [self showToast:TR(@"Msg_Nothing_Copy")];
    return;
  }

  NSMutableString *text = [NSMutableString string];
  [text appendFormat:@"// %@ + 0x%llX  PC: 0x%llX\n", hit.imageName, hit.offset, hit.pc];
  for (NSDictionary *l in lines) {
    BOOL isPC = [l[@"isPC"] boolValue];
    [text appendFormat:@"%@ %08llX  %@  %@\n",
      isPC ? @">" : @" ",
      [l[@"offset"] unsignedLongLongValue],
      l[@"hex"], l[@"mnemonic"]];
  }
  [UIPasteboard generalPasteboard].string = text;
  [self showToast:TR(@"Msg_Copy_Success")];
}

- (void)onCopyOffset:(UIButton *)sender {
  VMWatchHit *hit = objc_getAssociatedObject(sender, "dasmHit");
  if (!hit) return;
  NSString *offStr = [NSString stringWithFormat:@"0x%llX", hit.offset];
  [UIPasteboard generalPasteboard].string = offStr;
  [self showToast:[NSString stringWithFormat:@"%@ %@", TR(@"Msg_Copy_Success"), offStr]];
}

- (void)onSendToRVA:(UIButton *)sender {
  VMWatchHit *hit = objc_getAssociatedObject(sender, "dasmHit");
  if (!hit) return;

  UIView *panel = [self.inspectorOverlay viewWithTag:500];
  UIView *toolbar = panel ? [panel viewWithTag:502] : nil;
  NSString *selHex = toolbar ? objc_getAssociatedObject(toolbar, "selHex") : nil;
  NSNumber *selOffset = toolbar ? objc_getAssociatedObject(toolbar, "selOffset") : nil;

  uint64_t offset = selOffset ? [selOffset unsignedLongLongValue] : hit.offset;

  [self sendToRVAWithOffset:offset moduleName:hit.imageName hex:selHex];
}

#pragma mark - Send to RVA (Save Dialog)

- (void)onOpenARMConverter {
  NSURL *url = [NSURL URLWithString:@"https://armconverter.com"];
  [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
}

- (void)sendToRVAWithOffset:(uint64_t)offset moduleName:(NSString *)moduleName hex:(NSString *)hex {
  VMMemoryEngine *engine = [VMMemoryEngine shared];
  NSString *currentBid = engine.currentBundleID;

  uint64_t base = [engine findModuleBaseAddress:moduleName];
  NSString *detectedOrigHex = nil;
  if (base > 0) {
    NSString *cleanHex = [[[hex stringByReplacingOccurrencesOfString:@" " withString:@""] uppercaseString]
                           stringByReplacingOccurrencesOfString:@"0X" withString:@""];
    NSUInteger byteLen = cleanHex.length / 2;
    if (byteLen > 0) {
      uint64_t absAddr = base + offset;
      NSData *origData = [engine readRawMemory:absAddr length:byteLen];
      if (origData && origData.length == byteLen) {
        detectedOrigHex = [engine hexStringFromData:origData];
      }
    }
  }

  VMRVAPatch *existingPatch = nil;
  for (VMRVAPatch *p in engine.rvaPatches) {
    BOOL bidMatch = (!p.bundleID || [p.bundleID isEqualToString:currentBid]);
    if (bidMatch && [p.moduleName isEqualToString:moduleName] && p.offset == offset) {
      existingPatch = p;
      break;
    }
  }
  if (existingPatch && existingPatch.isOn && existingPatch.originalHex.length > 0) {
    detectedOrigHex = existingPatch.originalHex;
  }


  UIAlertController *alert =
      [UIAlertController alertControllerWithTitle:TR(@"Title_Save_Patch")
                                          message:nil
                                   preferredStyle:UIAlertControllerStyleAlert];

  NSString *defaultNote = existingPatch ? existingPatch.note
      : [NSString stringWithFormat:@"%@ + 0x%llX", moduleName, offset];

  [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
    tf.placeholder = defaultNote;
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 60, 30)];
    l.text = TR(@"Lock_Label_Note");
    l.font = [UIFont systemFontOfSize:12];
    tf.leftView = l;
    tf.leftViewMode = UITextFieldViewModeAlways;
  }];

  [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
    tf.text = hex ?: @"";
    tf.placeholder = TR(@"RVA_Patch_Hex_Placeholder");
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 60, 30)];
    l.text = TR(@"RVA_Modify_Label");
    l.font = [UIFont systemFontOfSize:12];
    l.textColor = [UIColor systemGreenColor];
    tf.leftView = l;
    tf.leftViewMode = UITextFieldViewModeAlways;
  }];

  [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
    tf.text = detectedOrigHex ?: @"???";
    tf.placeholder = TR(@"RVA_Original_Hex_Placeholder");
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 60, 30)];
    l.text = TR(@"RVA_Origin_Label");
    l.font = [UIFont systemFontOfSize:12];
    l.textColor = [UIColor systemRedColor];
    tf.leftView = l;
    tf.leftViewMode = UITextFieldViewModeAlways;
  }];

  [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
    tf.text = existingPatch ? existingPatch.author : @"";
    tf.placeholder = TR(@"Placeholder_Author");
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 60, 30)];
    l.text = TR(@"Lock_Label_Author");
    l.font = [UIFont systemFontOfSize:12];
    tf.leftView = l;
    tf.leftViewMode = UITextFieldViewModeAlways;

  }];

  [alert addAction:[UIAlertAction actionWithTitle:TR(@"Btn_Cancel") style:UIAlertActionStyleCancel handler:nil]];

  [alert addAction:[UIAlertAction actionWithTitle:TR(@"Btn_Confirm")
    style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
      NSString *note = alert.textFields[0].text.length > 0 ? alert.textFields[0].text : alert.textFields[0].placeholder;
      NSString *finalPatchHex = alert.textFields[1].text;
      NSString *finalOrigHex = alert.textFields[2].text;
      NSString *author = alert.textFields[3].text.length > 0 ? alert.textFields[3].text : alert.textFields[3].placeholder;

      if (finalPatchHex.length == 0 || finalOrigHex.length == 0) return;

      NSString *appName = nil;
      NSString *appVersion = nil;
      if (currentBid.length > 0) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        id proxy = [NSClassFromString(@"LSApplicationProxy")
            performSelector:NSSelectorFromString(@"applicationProxyForIdentifier:")
                 withObject:currentBid];
        if (proxy) {
          appName = [proxy performSelector:NSSelectorFromString(@"localizedName")];
          appVersion = [proxy performSelector:NSSelectorFromString(@"shortVersionString")];
        }
#pragma clang diagnostic pop
      }

      VMRVAPatch *currentExisting = nil;
      NSInteger currentIndex = NSNotFound;
      for (NSInteger i = 0; i < (NSInteger)engine.rvaPatches.count; i++) {
        VMRVAPatch *p = engine.rvaPatches[i];
        BOOL bidMatch = (!p.bundleID || [p.bundleID isEqualToString:currentBid]);
        if (bidMatch && [p.moduleName isEqualToString:moduleName] && p.offset == offset) {
          currentExisting = p;
          currentIndex = i;
          break;
        }
      }

      if (currentExisting && currentIndex != NSNotFound) {
        
        VMRVAPatch *patch = [[VMRVAPatch alloc] init];
        patch.moduleName = moduleName;
        patch.offset = offset;
        patch.patchHex = finalPatchHex;
        patch.originalHex = finalOrigHex;
        patch.note = note;
        patch.author = author;
        patch.isImported = currentExisting.isImported;
        patch.bundleID = currentBid;
        patch.isOn = currentExisting.isOn;
        patch.createdAt = currentExisting.createdAt;
        patch.appName = appName;
        patch.appVersion = appVersion;
        [engine.rvaPatches replaceObjectAtIndex:currentIndex withObject:patch];
      } else {
        
        VMRVAPatch *patch = [[VMRVAPatch alloc] init];
        patch.moduleName = moduleName;
        patch.offset = offset;
        patch.patchHex = finalPatchHex;
        patch.originalHex = finalOrigHex;
        patch.isOn = NO;
        patch.note = note;
        patch.author = author;
        patch.isImported = NO;
        patch.bundleID = currentBid;
        patch.createdAt = [[NSDate date] timeIntervalSince1970] + 0.001;
        patch.appName = appName;
        patch.appVersion = appVersion;
        [engine.rvaPatches addObject:patch];
      }

      [engine saveRVAPatches];
      [self showToast:TR(@"Alert_Success")];
  }]];

  void (^presentBlock)(void) = ^{
    [self presentViewController:alert animated:YES completion:nil];
  };
  if (self.presentedViewController) {
    [self.presentedViewController dismissViewControllerAnimated:NO completion:presentBlock];
  } else {
    presentBlock();
  }
}

#pragma mark - Toast

- (void)showToast:(NSString *)msg {
  void (^showBlock)(void) = ^{
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:nil
                                                               message:msg
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:ac animated:YES completion:nil];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
      [ac dismissViewControllerAnimated:YES completion:nil];
    });
  };
  if (self.presentedViewController) {
    [self.presentedViewController dismissViewControllerAnimated:NO completion:showBlock];
  } else {
    showBlock();
  }
}

@end
