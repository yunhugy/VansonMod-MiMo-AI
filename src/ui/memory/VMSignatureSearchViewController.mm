#import <UIKit/UIKit.h>

#import "../../utils/helpers/VMUIHelper.h"
#import "../memory/VMModuleListViewController.h"
#import "../memory/VMSignatureSearchViewController.h"
#import "VMMemoryActionSheet.h"
#import "include/VMLocalization.h"
#import "include/VMLockManager.h"
#import "include/VMMemoryEngine.h"
#import "include/VMSignatureModel.h"
#import <sys/sysctl.h>

#define TR(key) ([[VMLocalization shared] localizedString:key])

@interface VMByteCell : UICollectionViewCell
@property(nonatomic, strong) UILabel *label;
@property(nonatomic, assign) BOOL isCenterCell;
@property(nonatomic, assign) BOOL isMaskedCell;
@end

@implementation VMByteCell
- (instancetype)initWithFrame:(CGRect)frame {
  if (self = [super initWithFrame:frame]) {
    self.contentView.layer.cornerRadius = 4;
    self.contentView.layer.borderWidth = 1.0;

    _label = [[UILabel alloc] initWithFrame:self.contentView.bounds];
    _label.autoresizingMask =
        UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _label.textAlignment = NSTextAlignmentCenter;
    _label.font = [UIFont fontWithName:@"Menlo-Bold" size:12];
    _label.adjustsFontSizeToFitWidth = YES;
    [self.contentView addSubview:_label];
  }
  return self;
}

- (void)configureWithByte:(NSString *)byte
                 isMasked:(BOOL)masked
                 isCenter:(BOOL)isCenter {
  self.label.text = byte;
  self.isMaskedCell = masked;
  self.isCenterCell = isCenter;
  [self updateColors];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
  [super traitCollectionDidChange:previousTraitCollection];
  if ([self.traitCollection
          hasDifferentColorAppearanceComparedToTraitCollection:
              previousTraitCollection]) {
    [self updateColors];
  }
}

- (void)updateColors {
  if (self.isCenterCell) {
    self.contentView.layer.borderWidth = 2.0;
    self.contentView.layer.borderColor = [UIColor systemBlueColor].CGColor;
  } else {
    self.contentView.layer.borderWidth = 1.0;
    self.contentView.layer.borderColor = [UIColor opaqueSeparatorColor].CGColor;
  }

  if (self.isMaskedCell) {
    self.contentView.backgroundColor =
        [[UIColor systemRedColor] colorWithAlphaComponent:0.15];
    if (!self.isCenterCell)
      self.contentView.layer.borderColor = [UIColor systemRedColor].CGColor;
    self.label.textColor = [UIColor systemRedColor];
  } else {
    self.contentView.backgroundColor =
        [UIColor secondarySystemGroupedBackgroundColor];
    self.label.textColor = [UIColor labelColor];
  }
}
@end

@interface VMSignatureSearchViewController () <
    UICollectionViewDelegate, UICollectionViewDataSource,
    UICollectionViewDelegateFlowLayout, UITableViewDelegate,
    UITableViewDataSource>

@property(nonatomic, strong) UIStackView *rootStackView;

@property(nonatomic, strong) UIScrollView *configScrollView;
@property(nonatomic, strong) UIStackView *configStackView;

@property(nonatomic, strong) UIView *fixedActionContainer;

@property(nonatomic, strong) UITableView *resultsTableView;

@property(nonatomic, strong) UILabel *targetAddrLabel;
@property(nonatomic, strong) UISegmentedControl *rangeSegment;
@property(nonatomic, strong) UITextField *moduleField; 
@property(nonatomic, strong) UILabel *moduleDetailLabel; 

@property(nonatomic, strong) UICollectionView *byteCollectionView;
@property(nonatomic, strong) UIButton *btnSmartMask;
@property(nonatomic, strong) UIButton *btnRevert;

@property(nonatomic, strong) UILabel *statusLabel;
@property(nonatomic, strong) UIButton *verifyButton;
@property(nonatomic, strong) UIButton *saveButton;
@property(nonatomic, strong) UIButton *resetButton;
@property(nonatomic, strong) UIActivityIndicatorView *verifySpinner;

@property(nonatomic, strong) NSMutableArray<NSString *> *originalBytes;
@property(nonatomic, strong) NSMutableArray<NSString *> *currentBytes;
@property(nonatomic, assign) NSRange targetValueRange;
@property(nonatomic, strong) NSArray<VMScanResultItem *> *scanResults;

@property(nonatomic, assign) NSUInteger successCount;
@property(nonatomic, assign) uint64_t currentScanStartAddr;
@property(nonatomic, assign) int currentOffsetFromStart;
@property(nonatomic, assign) uint64_t lastFoundAddress;
@property(nonatomic, copy) NSString *targetBundleID;
@property(nonatomic, copy) NSString *originalModuleName;
@property(nonatomic, assign) BOOL hasVerifiedOnce;

@end

@implementation VMSignatureSearchViewController

- (void)viewDidLoad {
  [super viewDidLoad];
  self.title = TR(@"Sig_Title_Analyzer");
  self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];

  self.originalBytes = [NSMutableArray array];
  self.currentBytes = [NSMutableArray array];
  self.scanResults = @[];
  self.targetBundleID = [[VMMemoryEngine shared] currentBundleID];
  self.hasVerifiedOnce = NO;

  [self setupLayout];

  [VMUIHelper addFixedFooterTo:self forTableView:self.resultsTableView];

  self.rangeSegment.selectedSegmentIndex = 1;

  dispatch_after(
      dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)),
      dispatch_get_main_queue(), ^{
        [self reloadMemoryData];
      });
}

- (void)viewDidLayoutSubviews {
  [super viewDidLayoutSubviews];
  [self updateOrientationLayout];
}

#pragma mark - 1. 布局架构 (Fixed Layout)

- (void)setupLayout {
  UILayoutGuide *g = self.view.safeAreaLayoutGuide;

  self.rootStackView = [[UIStackView alloc] init];
  self.rootStackView.axis = UILayoutConstraintAxisVertical;
  self.rootStackView.spacing = 0;
  self.rootStackView.alignment = UIStackViewAlignmentFill;
  self.rootStackView.distribution = UIStackViewDistributionFill;
  self.rootStackView.translatesAutoresizingMaskIntoConstraints = NO;
  [self.view addSubview:self.rootStackView];

  [NSLayoutConstraint activateConstraints:@[
    [self.rootStackView.topAnchor constraintEqualToAnchor:g.topAnchor],
    [self.rootStackView.leadingAnchor constraintEqualToAnchor:g.leadingAnchor],
    [self.rootStackView.trailingAnchor
        constraintEqualToAnchor:g.trailingAnchor],
    [self.rootStackView.bottomAnchor
        constraintEqualToAnchor:self.view.bottomAnchor]
  ]];

  self.configScrollView = [[UIScrollView alloc] init];
  self.configScrollView.backgroundColor =
      [UIColor systemGroupedBackgroundColor];
  self.configScrollView.alwaysBounceVertical = YES;

  self.configStackView = [[UIStackView alloc] init];
  self.configStackView.axis = UILayoutConstraintAxisVertical;
  self.configStackView.spacing = 16;
  self.configStackView.alignment = UIStackViewAlignmentFill;
  self.configStackView.layoutMargins = UIEdgeInsetsMake(12, 16, 12, 16);
  self.configStackView.layoutMarginsRelativeArrangement = YES;
  self.configStackView.translatesAutoresizingMaskIntoConstraints = NO;

  [self.configScrollView addSubview:self.configStackView];

  [NSLayoutConstraint activateConstraints:@[
    [self.configStackView.topAnchor
        constraintEqualToAnchor:self.configScrollView.contentLayoutGuide
                                    .topAnchor],
    [self.configStackView.bottomAnchor
        constraintEqualToAnchor:self.configScrollView.contentLayoutGuide
                                    .bottomAnchor],
    [self.configStackView.leadingAnchor
        constraintEqualToAnchor:self.configScrollView.contentLayoutGuide
                                    .leadingAnchor],
    [self.configStackView.trailingAnchor
        constraintEqualToAnchor:self.configScrollView.contentLayoutGuide
                                    .trailingAnchor],
    [self.configStackView.widthAnchor
        constraintEqualToAnchor:self.configScrollView.frameLayoutGuide
                                    .widthAnchor]
  ]];

  [self.rootStackView addArrangedSubview:self.configScrollView];

  NSLayoutConstraint *heightLimit = [self.configScrollView.heightAnchor
      constraintLessThanOrEqualToAnchor:g.heightAnchor
                             multiplier:0.45];
  heightLimit.priority = UILayoutPriorityRequired;
  NSLayoutConstraint *heightMatch = [self.configScrollView.heightAnchor
      constraintEqualToAnchor:self.configStackView.heightAnchor];
  heightMatch.priority = UILayoutPriorityDefaultLow;
  NSLayoutConstraint *minHeight = [self.configScrollView.heightAnchor
      constraintGreaterThanOrEqualToConstant:150];

  [NSLayoutConstraint
      activateConstraints:@[ heightLimit, heightMatch, minHeight ]];

  [self buildSection1];
  [self buildSection2];

  self.fixedActionContainer = [[UIView alloc] init];
  self.fixedActionContainer.backgroundColor =
      [UIColor secondarySystemGroupedBackgroundColor];
  self.fixedActionContainer.layer.shadowColor = [UIColor blackColor].CGColor;
  self.fixedActionContainer.layer.shadowOffset = CGSizeMake(0, -1);
  self.fixedActionContainer.layer.shadowOpacity = 0.05;
  self.fixedActionContainer.layer.shadowRadius = 2;
  self.fixedActionContainer.layer.zPosition = 10;

  [self.rootStackView addArrangedSubview:self.fixedActionContainer];
  [self buildFixedActionSection];

  self.resultsTableView =
      [[UITableView alloc] initWithFrame:CGRectZero
                                   style:UITableViewStyleInsetGrouped];
  self.resultsTableView.delegate = self;
  self.resultsTableView.dataSource = self;
  self.resultsTableView.rowHeight = UITableViewAutomaticDimension;
  self.resultsTableView.estimatedRowHeight = 44;
  self.resultsTableView.contentInset = UIEdgeInsetsMake(0, 0, 40, 0);

  [self.rootStackView addArrangedSubview:self.resultsTableView];
}

- (void)updateOrientationLayout {
  CGSize size = self.view.bounds.size;
  BOOL isLandscape = size.width > size.height;
  UILayoutGuide *g = self.view.safeAreaLayoutGuide;

  if (isLandscape) {
    if (self.rootStackView.axis != UILayoutConstraintAxisHorizontal) {
      self.rootStackView.axis = UILayoutConstraintAxisHorizontal;

      NSLayoutConstraint *w = [self.configScrollView.widthAnchor
          constraintEqualToAnchor:g.widthAnchor
                       multiplier:0.4];
      w.priority = UILayoutPriorityRequired;
      w.active = YES;

      [self.configScrollView.widthAnchor
          constraintGreaterThanOrEqualToConstant:300]
          .active = YES;

      self.configScrollView.alwaysBounceVertical = YES;
    }
  } else {
    if (self.rootStackView.axis != UILayoutConstraintAxisVertical) {
      self.rootStackView.axis = UILayoutConstraintAxisVertical;
      
    }
  }
}

#pragma mark - Sections

- (void)buildSection1 {
  UIView *card = [self createCardView];
  UIStackView *vStack = [[UIStackView alloc] init];
  vStack.axis = UILayoutConstraintAxisVertical;
  vStack.spacing = 10;
  vStack.translatesAutoresizingMaskIntoConstraints = NO;
  [card addSubview:vStack];

  self.targetAddrLabel = [self createLabel:@""
                                     color:[UIColor labelColor]
                                      font:15
                                      bold:YES];
  self.targetAddrLabel.text =
      [NSString stringWithFormat:TR(@"Sig_Target_Label"), self.initialAddress];
  self.targetAddrLabel.textAlignment = NSTextAlignmentCenter;

  self.rangeSegment = [[UISegmentedControl alloc]
      initWithItems:@[ @"±8", @"±16", @"±32", @"±64" ]];
  [self.rangeSegment addTarget:self
                        action:@selector(reloadMemoryData)
              forControlEvents:UIControlEventValueChanged];

  [vStack addArrangedSubview:self.targetAddrLabel];
  [vStack addArrangedSubview:self.rangeSegment];

  [self pinStack:vStack toView:card padding:12];
  [self.configStackView addArrangedSubview:card];
}

- (void)buildSection2 {
  UIView *container = [[UIView alloc] init];
  UIStackView *vStack = [[UIStackView alloc] init];
  vStack.axis = UILayoutConstraintAxisVertical;
  vStack.spacing = 8;
  vStack.translatesAutoresizingMaskIntoConstraints = NO;
  [container addSubview:vStack];

  UILabel *title = [self createLabel:TR(@"Sig_Hex_Label")
                               color:[UIColor secondaryLabelColor]
                                font:12
                                bold:NO];
  [vStack addArrangedSubview:title];

  UICollectionViewFlowLayout *layout =
      [[UICollectionViewFlowLayout alloc] init];
  layout.minimumInteritemSpacing = 4;
  layout.minimumLineSpacing = 6;
  layout.itemSize = CGSizeMake(34, 34);
  layout.scrollDirection = UICollectionViewScrollDirectionVertical;

  self.byteCollectionView = [[UICollectionView alloc] initWithFrame:CGRectZero
                                               collectionViewLayout:layout];
  self.byteCollectionView.backgroundColor =
      [UIColor secondarySystemGroupedBackgroundColor];
  self.byteCollectionView.layer.cornerRadius = 8;
  self.byteCollectionView.delegate = self;
  self.byteCollectionView.dataSource = self;
  self.byteCollectionView.scrollEnabled = YES;
  self.byteCollectionView.translatesAutoresizingMaskIntoConstraints = NO;
  [self.byteCollectionView registerClass:[VMByteCell class]
              forCellWithReuseIdentifier:@"ByteCell"];

  [self.byteCollectionView.heightAnchor constraintEqualToConstant:120].active =
      YES;
  [vStack addArrangedSubview:self.byteCollectionView];

  UIStackView *toolRow = [[UIStackView alloc] init];
  toolRow.axis = UILayoutConstraintAxisHorizontal;
  toolRow.spacing = 10;
  toolRow.distribution = UIStackViewDistributionFillEqually;

  self.btnSmartMask = [self createSmallButton:TR(@"Sig_Btn_SmartMask")
                                       action:@selector(smartMaskAction)
                                        color:[UIColor systemPurpleColor]];
  self.btnRevert = [self createSmallButton:TR(@"Sig_Btn_Revert")
                                    action:@selector(revertManualAction)
                                     color:[UIColor systemOrangeColor]];

  [toolRow addArrangedSubview:self.btnSmartMask];
  [toolRow addArrangedSubview:self.btnRevert];
  [vStack addArrangedSubview:toolRow];

  [self pinStack:vStack toView:container padding:0];
  [self.configStackView addArrangedSubview:container];
}

- (void)buildFixedActionSection {
  UIStackView *vStack = [[UIStackView alloc] init];
  vStack.axis = UILayoutConstraintAxisVertical;
  vStack.spacing = 10;
  vStack.translatesAutoresizingMaskIntoConstraints = NO;
  [self.fixedActionContainer addSubview:vStack];

  [NSLayoutConstraint activateConstraints:@[
    [vStack.topAnchor
        constraintEqualToAnchor:self.fixedActionContainer.topAnchor
                       constant:12],
    [vStack.bottomAnchor
        constraintEqualToAnchor:self.fixedActionContainer.bottomAnchor
                       constant:-12],
    [vStack.leadingAnchor
        constraintEqualToAnchor:self.fixedActionContainer.leadingAnchor
                       constant:16],
    [vStack.trailingAnchor
        constraintEqualToAnchor:self.fixedActionContainer.trailingAnchor
                       constant:-16]
  ]];

  self.statusLabel = [self createLabel:TR(@"Sig_Status_Default")
                                 color:[UIColor secondaryLabelColor]
                                  font:13
                                  bold:NO];
  self.statusLabel.numberOfLines = 0;
  self.statusLabel.textAlignment = NSTextAlignmentCenter;
  [vStack addArrangedSubview:self.statusLabel];

  UIStackView *btnRow = [[UIStackView alloc] init];
  btnRow.axis = UILayoutConstraintAxisHorizontal;
  btnRow.spacing = 12;
  btnRow.distribution = UIStackViewDistributionFillEqually;

  self.verifyButton =
      [VMUIHelper createButtonWithTitle:TR(@"Sig_Btn_Verify")
                                  color:[UIColor systemBlueColor]
                                 target:self
                                 action:@selector(verifyAction)];
  self.saveButton = [VMUIHelper createButtonWithTitle:TR(@"Btn_Save")
                                                color:[UIColor systemGreenColor]
                                               target:self
                                               action:@selector(saveAction)];
  self.resetButton = [VMUIHelper createButtonWithTitle:TR(@"Btn_Reset")
                                                 color:[UIColor systemRedColor]
                                                target:self
                                                action:@selector(resetAction)];

  [btnRow addArrangedSubview:self.verifyButton];
  [btnRow addArrangedSubview:self.saveButton];
  [btnRow addArrangedSubview:self.resetButton];

  [btnRow.heightAnchor constraintEqualToConstant:36].active = YES;
  [vStack addArrangedSubview:btnRow];

  self.verifySpinner = [[UIActivityIndicatorView alloc]
      initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
  self.verifySpinner.color = [UIColor whiteColor];
  self.verifySpinner.hidesWhenStopped = YES;
  self.verifySpinner.translatesAutoresizingMaskIntoConstraints = NO;

  [self.verifyButton addSubview:self.verifySpinner];
  [NSLayoutConstraint activateConstraints:@[
    [self.verifySpinner.centerXAnchor
        constraintEqualToAnchor:self.verifyButton.centerXAnchor],
    [self.verifySpinner.centerYAnchor
        constraintEqualToAnchor:self.verifyButton.centerYAnchor]
  ]];
}

#pragma mark - Logic: Reload & Verify

- (void)reloadMemoryData {
  if ([VMMemoryEngine shared].targetTask == MACH_PORT_NULL)
    return;

  int radius = 8;
  switch (self.rangeSegment.selectedSegmentIndex) {
  case 0:
    radius = 8;
    break;
  case 1:
    radius = 16;
    break;
  case 2:
    radius = 32;
    break;
  case 3:
    radius = 64;
    break;
  }

  int totalLen = radius * 2;
  uint64_t startAddr = self.initialAddress - radius;

  self.currentScanStartAddr = startAddr;
  self.currentOffsetFromStart = radius;

  NSData *data = [[VMMemoryEngine shared] readRawMemory:startAddr
                                                 length:totalLen];
  if (!data) {
    self.statusLabel.text = TR(@"Sig_Read_Failed");
    return;
  }

  NSString *hex = [[VMMemoryEngine shared] hexStringFromData:data];

  [self.originalBytes removeAllObjects];
  [self.currentBytes removeAllObjects];

  for (int i = 0; i < hex.length; i += 2) {
    if (i + 2 <= hex.length) {
      NSString *byte = [hex substringWithRange:NSMakeRange(i, 2)];
      [self.originalBytes addObject:byte];
      [self.currentBytes addObject:byte];
    }
  }

  int targetSize = [self getSizeForType:self.targetType];
  int startIndex = radius;

  if (startIndex + targetSize <= self.currentBytes.count) {
    self.targetValueRange = NSMakeRange(startIndex, targetSize);
    for (int i = 0; i < targetSize; i++) {
      self.currentBytes[startIndex + i] = @"??";
    }
  }

  [self.byteCollectionView reloadData];

  self.successCount = 0;
  self.statusLabel.text =
      [NSString stringWithFormat:TR(@"Sig_Scope_Info"), radius, radius];
  self.statusLabel.textColor = [UIColor secondaryLabelColor];
}

- (void)verifyAction {
  NSString *sig = [self.currentBytes componentsJoinedByString:@" "];
  if (sig.length == 0)
    return;

  [self.verifyButton setTitle:@"" forState:UIControlStateNormal];
  self.verifyButton.enabled = NO;
  [self.verifySpinner startAnimating];
  self.view.userInteractionEnabled = NO;

  self.statusLabel.text = TR(@"Sig_Status_Scanning");
  self.statusLabel.textColor = [UIColor systemBlueColor];

  self.scanStartTime = [NSDate date];

  __weak VMSignatureSearchViewController *weakSelf = self;
  void (^handler)(NSArray *) = ^(NSArray *results) {
    dispatch_async(dispatch_get_main_queue(), ^{
      [weakSelf.verifySpinner stopAnimating];

      weakSelf.hasVerifiedOnce = YES;
      [weakSelf.verifyButton setTitle:TR(@"Verifier_Btn_ReVerify")
                             forState:UIControlStateNormal];

      weakSelf.verifyButton.enabled = YES;
      weakSelf.view.userInteractionEnabled = YES;

      weakSelf.scanResults = results ?: @[];
      [weakSelf.resultsTableView reloadData];

      NSTimeInterval duration =
          [[NSDate date] timeIntervalSinceDate:weakSelf.scanStartTime];
      NSString *timeStr = [NSString stringWithFormat:@"%.3fs", duration];

      if (results.count == 1) {
        weakSelf.successCount++;
        VMScanResultItem *item = results.firstObject;
        weakSelf.lastFoundAddress = item.address;
        weakSelf.statusLabel.text = [NSString
            stringWithFormat:@"%@ (%@)", TR(@"Sig_Unique_Match"), timeStr];
        weakSelf.statusLabel.textColor = [UIColor systemGreenColor];
        UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc]
            initWithStyle:UIImpactFeedbackStyleMedium];
        [gen impactOccurred];
      } else if (results.count > 1) {
        weakSelf.statusLabel.text =
            [NSString stringWithFormat:TR(@"Sig_Multiple_Matches"),
                                       (unsigned long)results.count];
        weakSelf.statusLabel.textColor = [UIColor systemOrangeColor];
      } else {
        weakSelf.statusLabel.text = TR(@"Sig_No_Match");
        weakSelf.statusLabel.textColor = [UIColor systemRedColor];
      }
    });
  };

  [[VMMemoryEngine shared] scanSignature:sig
                              rangeStart:0
                                rangeEnd:0
                              completion:handler];
}

#pragma mark - Module Selection

- (NSString *)getModuleDisplayName {
  if (self.originalModuleName) {
    return [NSString stringWithFormat:@"[Module] %@", self.originalModuleName];
  } else {
    return TR(@"Mod_Search_All_Regions") ?: @"All Regions";
  }
}

- (void)showModuleSelector {
  VMModuleListViewController *moduleVC =
      [[VMModuleListViewController alloc] init];

  __weak VMSignatureSearchViewController *weakSelf = self;
  moduleVC.selectionHandler = ^(VMModuleInfo *selectedModule) {
    if (selectedModule) {
      weakSelf.originalModuleName = selectedModule.name;
    } else {
      weakSelf.originalModuleName = nil; 
    }

    weakSelf.moduleField.text = [weakSelf getModuleDisplayName];

    weakSelf.hasVerifiedOnce = NO;
    weakSelf.scanResults = @[];
    [weakSelf.resultsTableView reloadData];
    weakSelf.statusLabel.text = TR(@"Sig_Status_Default");
    weakSelf.statusLabel.textColor = [UIColor secondaryLabelColor];
    [weakSelf.verifyButton setTitle:TR(@"Sig_Btn_Verify")
                           forState:UIControlStateNormal];
  };

  [self.navigationController pushViewController:moduleVC animated:YES];
}

#pragma mark - Logic: Actions (Restored)

- (void)smartMaskAction {
  BOOL changed = NO;
  
  for (int i = 0; i < (int)self.originalBytes.count - 3; i += 4) {
    unsigned int byte3 = 0;
    
    NSScanner *scanner =
        [NSScanner scannerWithString:self.originalBytes[i + 3]];
    [scanner scanHexInt:&byte3];

    if ((byte3 & 0xFC) == 0x94 || (byte3 & 0x9F) == 0x90) {
      
      for (int k = 0; k < 3; k++) {
        if (i + k < self.currentBytes.count) {
          if (![self.currentBytes[i + k] isEqualToString:@"??"]) {
            self.currentBytes[i + k] = @"??";
            changed = YES;
          }
        }
      }
    }
  }

  if (changed) {
    [self.byteCollectionView reloadData];
    UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc]
        initWithStyle:UIImpactFeedbackStyleMedium];
    [gen impactOccurred];
    [self showToast:TR(@"Sig_Auto_Mask_Applied")];
  } else {
    [self showToast:TR(@"Sig_SmartMask_NoLogic")];
  }
}

- (void)revertManualAction {
  self.currentBytes = [self.originalBytes mutableCopy];

  [self.byteCollectionView reloadData];
}

- (void)resetAction {
  [self reloadMemoryData];
  self.scanResults = @[];
  self.hasVerifiedOnce = NO;
  [self.verifyButton setTitle:TR(@"Sig_Btn_Verify")
                     forState:UIControlStateNormal];
  [self.resultsTableView reloadData];
  [self showToast:TR(@"Msg_Reset_Done")];
}

- (void)saveAction {
  NSString *defaultNote = TR(@"Sig_Default_Note");
  NSString *defaultAuth = TR(@"Sig_Author_Default");
  NSString *sigStr = [self.currentBytes componentsJoinedByString:@" "];


  UIAlertController *alert =

      [UIAlertController alertControllerWithTitle:TR(@"Sig_Btn_Save_Toolbox")
                                          message:nil
                                   preferredStyle:UIAlertControllerStyleAlert];

  [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
    tf.placeholder = TR(@"Placeholder_Note");
    tf.text = defaultNote;
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 60, 30)];
    l.text = TR(@"Lab_Note_Colon");
    l.font = [UIFont systemFontOfSize:12];
    l.textColor = [UIColor systemGrayColor];
    tf.leftView = l;
    tf.leftViewMode = UITextFieldViewModeAlways;
  }];

  [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
    tf.text = sigStr;
    tf.font = [UIFont fontWithName:@"Menlo" size:12];
    tf.textColor = [UIColor systemBlueColor];
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 60, 30)];
    l.text = TR(@"Sig_Label_Sig");
    l.font = [UIFont systemFontOfSize:12];
    l.textColor = [UIColor systemGrayColor];
    tf.leftView = l;
    tf.leftViewMode = UITextFieldViewModeAlways;
  }];

  [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
    tf.placeholder = TR(@"Placeholder_Author");
    tf.text = defaultAuth;
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 60, 30)];
    l.text = TR(@"Lab_Auth_Colon");
    l.font = [UIFont systemFontOfSize:12];
    l.textColor = [UIColor systemGrayColor];
    tf.leftView = l;
    tf.leftViewMode = UITextFieldViewModeAlways;

  }];

  [alert
      addAction:[UIAlertAction
                    actionWithTitle:TR(@"Btn_Confirm")
                              style:UIAlertActionStyleDefault
                            handler:^(UIAlertAction *a) {
                              VMSignatureModel *sig = [[VMSignatureModel alloc] init];
                              NSString *note = alert.textFields[0].text;
                              NSString *finalSig = alert.textFields[1].text;
                              NSString *auth = alert.textFields[2].text;

                              sig.note = (note.length > 0) ? note : defaultNote;
                              sig.signature = (finalSig.length > 0) ? finalSig : sigStr;
                              sig.author = (auth.length > 0) ? auth : defaultAuth;
                              sig.bundleID = self.targetBundleID;
                              sig.createdAt = [[NSDate date] timeIntervalSince1970];
                              sig.isImported = NO;

                              uint64_t targetAddr = self.initialAddress;
                              uint64_t matchAddr = self.lastFoundAddress;
                              if (matchAddr == 0) matchAddr = self.currentScanStartAddr;

                              long long diff = (long long)targetAddr - (long long)matchAddr;
                              sig.offset = (int)diff;

                              VMModuleMatch *match = [[VMMemoryEngine shared] findModuleForAddress:targetAddr];
                              if (match) sig.moduleName = match.moduleName;
                              else sig.moduleName = nil;

                              [[VMLockManager shared] addSignatureToLock:sig];
                              
                              NSString *fileName;
                              if (self.targetBundleID.length > 0) {
                                fileName = [NSString stringWithFormat:@"%@-signatures.vmsig", self.targetBundleID];
                              } else {
                                fileName = @"signatures.vmsig";
                              }
                              [self showSuccessAlertWithFileName:fileName];
                            }]];

  [alert addAction:[UIAlertAction actionWithTitle:TR(@"Btn_Cancel")
                                            style:UIAlertActionStyleCancel
                                          handler:nil]];

  if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
    alert.popoverPresentationController.sourceView = self.saveButton;
    alert.popoverPresentationController.sourceRect = self.saveButton.bounds;
  }
  [self presentViewController:alert animated:YES completion:nil];
}

- (void)showSuccessAlertWithFileName:(NSString *)fileName {
  UIAlertController *alert =
      [UIAlertController alertControllerWithTitle:TR(@"Sig_Save_Title")
                                          message:TR(@"Sig_Save_Msg")
                                   preferredStyle:UIAlertControllerStyleAlert];
  [alert addAction:[UIAlertAction actionWithTitle:TR(@"Btn_OK")
                                            style:UIAlertActionStyleCancel
                                          handler:nil]];
  __weak VMSignatureSearchViewController *weakSelf = self;
  [alert addAction:[UIAlertAction actionWithTitle:TR(@"Btn_Go_Toolbox") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
    UITabBarController *tabBar = weakSelf.tabBarController;
    if (tabBar && tabBar.viewControllers.count > 3) {
      tabBar.selectedIndex = 3;
      UINavigationController *nav = (UINavigationController *)tabBar.selectedViewController;
      [nav popToRootViewControllerAnimated:NO];
      if ([nav.topViewController isKindOfClass:NSClassFromString(@"VMLockListViewController")]) {
        id lockVC = nav.topViewController;
        NSDictionary *pending = @{@"targetTab": @(4), @"bundleID": weakSelf.targetBundleID ?: @"", @"fileName": fileName ?: @"", @"toast": TR(@"Msg_Saved")};
        [lockVC setValue:pending forKey:@"pendingJumpInfo"];
        if ([lockVC respondsToSelector:@selector(processPendingJump)]) [lockVC performSelector:@selector(processPendingJump)];
      }
    }
  }]];
  [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - CollectionView DataSource

- (NSInteger)collectionView:(UICollectionView *)collectionView
     numberOfItemsInSection:(NSInteger)section {
  return self.currentBytes.count;
}

- (__kindof UICollectionViewCell *)collectionView:
                                       (UICollectionView *)collectionView
                           cellForItemAtIndexPath:(NSIndexPath *)indexPath {
  VMByteCell *cell =
      [collectionView dequeueReusableCellWithReuseIdentifier:@"ByteCell"
                                                forIndexPath:indexPath];
  if (indexPath.item < self.currentBytes.count) {
    NSString *byte = self.currentBytes[indexPath.item];
    BOOL isMasked = [byte isEqualToString:@"??"];
    BOOL isCenter = NSLocationInRange(indexPath.item, self.targetValueRange);
    [cell configureWithByte:byte isMasked:isMasked isCenter:isCenter];
  }
  return cell;
}

- (void)collectionView:(UICollectionView *)collectionView
    didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
  if (indexPath.item >= self.currentBytes.count)
    return;
  NSString *curr = self.currentBytes[indexPath.item];
  if ([curr isEqualToString:@"??"]) {
    self.currentBytes[indexPath.item] = self.originalBytes[indexPath.item];
  } else {
    self.currentBytes[indexPath.item] = @"??";
  }
  [UIView performWithoutAnimation:^{
    [collectionView reloadItemsAtIndexPaths:@[ indexPath ]];
  }];
  UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc]
      initWithStyle:UIImpactFeedbackStyleLight];
  [gen impactOccurred];
}

#pragma mark - TableView Delegate

- (NSInteger)tableView:(UITableView *)tableView
    numberOfRowsInSection:(NSInteger)section {
  return self.scanResults.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
  UITableViewCell *cell =
      [tableView dequeueReusableCellWithIdentifier:@"ResultCell"];
  if (!cell) {
    cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
                                  reuseIdentifier:@"ResultCell"];
    cell.textLabel.font =
        [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
    cell.detailTextLabel.font =
        [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightBold];
  }

  VMScanResultItem *item = self.scanResults[indexPath.row];
  uint64_t valAddress = item.address + self.currentOffsetFromStart;
  NSString *valStr = [[VMMemoryEngine shared] readAddress:valAddress
                                                     type:self.targetType];

  cell.textLabel.text = [NSString
      stringWithFormat:@"[%ld] 0x%llX", (long)indexPath.row + 1, valAddress];
  NSString *typeStr = [self typeNameForType:self.targetType];
  cell.detailTextLabel.text =
      [NSString stringWithFormat:@"%@ -> %@", typeStr, valStr ?: @"--"];
  cell.detailTextLabel.textColor = [UIColor systemBlueColor];

  return cell;
}

- (void)tableView:(UITableView *)tableView
    didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
  [tableView deselectRowAtIndexPath:indexPath animated:YES];
  VMScanResultItem *item = self.scanResults[indexPath.row];
  uint64_t valAddress = item.address + self.currentOffsetFromStart;
  self.lastFoundAddress = item.address;

  NSString *val = [[VMMemoryEngine shared] readAddress:valAddress
                                                  type:self.targetType];
  CGRect rect = [tableView rectForRowAtIndexPath:indexPath];

  [VMMemoryActionSheet showActionSheetForAddress:valAddress
                                           value:val
                                        dataType:self.targetType
                              fromViewController:self
                                      sourceView:tableView
                                      sourceRect:rect
                                       extraItem:nil];
}

- (void)pinStack:(UIStackView *)stack
          toView:(UIView *)view
         padding:(CGFloat)pad {
  [NSLayoutConstraint activateConstraints:@[
    [stack.topAnchor constraintEqualToAnchor:view.topAnchor constant:pad],
    [stack.bottomAnchor constraintEqualToAnchor:view.bottomAnchor
                                       constant:-pad],
    [stack.leadingAnchor constraintEqualToAnchor:view.leadingAnchor
                                        constant:pad],
    [stack.trailingAnchor constraintEqualToAnchor:view.trailingAnchor
                                         constant:-pad]
  ]];
}
- (UIView *)createCardView {
  UIView *v = [[UIView alloc] init];
  v.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
  v.layer.cornerRadius = 10;
  v.clipsToBounds = YES;
  return v;
}
- (UILabel *)createLabel:(NSString *)text
                   color:(UIColor *)color
                    font:(CGFloat)size
                    bold:(BOOL)bold {
  UILabel *l = [UILabel new];
  l.text = text;
  l.textColor = color;
  l.font = bold ? [UIFont boldSystemFontOfSize:size]
                : [UIFont systemFontOfSize:size];
  l.translatesAutoresizingMaskIntoConstraints = NO;
  return l;
}
- (UIButton *)createSmallButton:(NSString *)title
                         action:(SEL)sel
                          color:(UIColor *)color {
  UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
  [btn setTitle:title forState:UIControlStateNormal];
  [btn setTitleColor:color forState:UIControlStateNormal];
  btn.backgroundColor = [color colorWithAlphaComponent:0.1];
  btn.layer.cornerRadius = 6;
  btn.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
  [btn addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
  return btn;
}
- (UITextField *)createTextField:(NSString *)ph {
  UITextField *tf = [UITextField new];
  tf.borderStyle = UITextBorderStyleRoundedRect;
  tf.placeholder = ph;
  tf.font = [UIFont fontWithName:@"Menlo" size:14];
  tf.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
  tf.keyboardType = UIKeyboardTypeASCIICapable;
  [tf.heightAnchor constraintEqualToConstant:40].active = YES;
  return tf;
}
- (void)showToast:(NSString *)msg {
  UIAlertController *ac =
      [UIAlertController alertControllerWithTitle:nil
                                          message:msg
                                   preferredStyle:UIAlertControllerStyleAlert];
  [self presentViewController:ac animated:YES completion:nil];
  dispatch_after(
      dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
      dispatch_get_main_queue(), ^{
        [ac dismissViewControllerAnimated:YES completion:nil];
      });
}
- (int)getSizeForType:(VMDataType)type {
  switch (type) {
  case VMDataTypeInt8:
    return 1;
  case VMDataTypeInt16:
    return 2;
  case VMDataTypeInt32:
    return 4;
  case VMDataTypeInt64:
    return 8;
  case VMDataTypeFloat:
    return 4;
  case VMDataTypeDouble:
    return 8;
  default:
    return 4;
  }
}
- (NSString *)typeNameForType:(VMDataType)type {
  switch (type) {
  case VMDataTypeInt8:
    return @"i8";
  case VMDataTypeInt16:
    return @"i16";
  case VMDataTypeInt32:
    return @"i32";
  case VMDataTypeInt64:
    return @"i64";
  case VMDataTypeUInt8:
    return @"u8";
  case VMDataTypeUInt16:
    return @"u16";
  case VMDataTypeUInt32:
    return @"u32";
  case VMDataTypeUInt64:
    return @"u64";
  case VMDataTypeFloat:
    return @"f32";
  case VMDataTypeDouble:
    return @"f64";
  case VMDataTypeString:
    return @"str";
  default:
    return @"??";
  }
}

@end
