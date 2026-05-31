#import "../memory/VMHexEditorViewController.h"
#import "VMHexRowEditorViewController.h"
#import "../../utils/helpers/VMUIHelper.h"
#import "include/VMLocalization.h"
#import "include/VMMemoryEngine.h"
#include <mach/mach.h>
extern "C" kern_return_t mach_vm_write(vm_map_t, mach_vm_address_t, vm_offset_t,
                                   mach_msg_type_number_t);
#define TR(key) ([[VMLocalization shared] localizedString:key])
#define BYTES_PER_ROW 16
#define LOAD_CHUNK_ROWS 60
@interface VMMemoryEngine (HexAdditions)
- (BOOL)writeRawData:(NSData *)data toAddress:(uint64_t)address;
@end
@interface VMHexEditorViewController () <
    UITableViewDelegate, UITableViewDataSource, VMHexRowEditorDelegate>
@property(nonatomic, strong) UIStackView *mainStackView;
@property(nonatomic, strong) UIView *headerContainer;
@property(nonatomic, strong) UIView *dividerLine;
@property(nonatomic, strong) UISegmentedControl *viewModeSegment;
@property(nonatomic, strong) UITableView *hexTableView;
@property(nonatomic, strong) UITableView *asciiTableView;
@property(nonatomic, strong) UILabel *addressLabel;
@property(nonatomic, strong) NSLayoutConstraint *hexWidthConstraint;
@property(nonatomic, assign) uint64_t startAddress;
@property(nonatomic, strong) NSMutableData *memoryBuffer;
@property(nonatomic, assign) BOOL isLoading;
@property(nonatomic, assign) BOOL isHexScrolling;
@property(nonatomic, assign) BOOL isAsciiScrolling;
@property(nonatomic, assign) CGFloat currentFontSize;
@end
@implementation VMHexEditorViewController
- (void)viewDidLoad {
  [super viewDidLoad];
  self.title = TR(@"Hex_Title");
  self.view.backgroundColor = [UIColor systemBackgroundColor];

  self.currentFontSize = 14.0;
  self.memoryBuffer = [NSMutableData data];
  self.startAddress = self.address;
  [self loadInitialData];

  [self setupNavBar];
  [self setupLayout];
  [self updateNavBarButtons];

  [VMUIHelper addFixedFooterTo:self forTableView:nil];

  UIEdgeInsets inset = UIEdgeInsetsMake(0, 0, 30, 0); 
  self.hexTableView.contentInset = inset;
  self.hexTableView.scrollIndicatorInsets = inset;

  self.asciiTableView.contentInset = inset;
  self.asciiTableView.scrollIndicatorInsets = inset;
}

#pragma mark - 1. 导航栏
- (void)setupNavBar {
  NSArray *items =
      @[ TR(@"Hex_Mode_Hex"), TR(@"Hex_Mode_Split"), TR(@"Hex_Mode_Ascii") ];
  self.viewModeSegment = [[UISegmentedControl alloc] initWithItems:items];
  self.viewModeSegment.selectedSegmentIndex = 1;
  [self.viewModeSegment addTarget:self
                           action:@selector(viewModeChanged:)
                 forControlEvents:UIControlEventValueChanged];
  self.navigationItem.titleView = self.viewModeSegment;
}

- (void)updateNavBarButtons {
  UIBarButtonItem *jumpBtn = [[UIBarButtonItem alloc]
      initWithImage:[UIImage systemImageNamed:@"arrow.turn.down.right"]
              style:UIBarButtonItemStylePlain
             target:self
             action:@selector(promptJump)];
  self.navigationItem.rightBarButtonItems = @[ jumpBtn ];
}

#pragma mark - 2. 布局
- (void)setupLayout {
  UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
  self.headerContainer = [[UIView alloc] init];
  self.headerContainer.translatesAutoresizingMaskIntoConstraints = NO;
  [self.view addSubview:self.headerContainer];

  self.addressLabel = [[UILabel alloc] init];
  self.addressLabel.textAlignment = NSTextAlignmentCenter;
  self.addressLabel.font = [UIFont monospacedSystemFontOfSize:14
                                                       weight:UIFontWeightBold];
  self.addressLabel.text =
      [NSString stringWithFormat:TR(@"Hex_Start_Addr"), self.address];
  self.addressLabel.translatesAutoresizingMaskIntoConstraints = NO;
  [self.headerContainer addSubview:self.addressLabel];
  self.mainStackView = [[UIStackView alloc] init];
  self.mainStackView.axis = UILayoutConstraintAxisHorizontal;
  self.mainStackView.alignment = UIStackViewAlignmentFill;
  self.mainStackView.distribution = UIStackViewDistributionFill;
  self.mainStackView.spacing = 0;
  self.mainStackView.translatesAutoresizingMaskIntoConstraints = NO;
  [self.view addSubview:self.mainStackView];
  self.hexTableView = [self
      createTableViewWithID:@"HexCell"
                         bg:[UIColor secondarySystemGroupedBackgroundColor]];
  self.asciiTableView =
      [self createTableViewWithID:@"AsciiCell"
                               bg:[UIColor systemGroupedBackgroundColor]];

  self.dividerLine = [[UIView alloc] init];
  self.dividerLine.backgroundColor = [UIColor systemGray3Color];
  [self.dividerLine setContentHuggingPriority:UILayoutPriorityRequired
                                      forAxis:UILayoutConstraintAxisHorizontal];
  [self.dividerLine.widthAnchor constraintEqualToConstant:0.5].active = YES;

  [self.mainStackView addArrangedSubview:self.hexTableView];
  [self.mainStackView addArrangedSubview:self.dividerLine];
  [self.mainStackView addArrangedSubview:self.asciiTableView];

  self.hexWidthConstraint =
      [self.hexTableView.widthAnchor constraintEqualToConstant:260.0];
  self.hexWidthConstraint.active = YES;

  [NSLayoutConstraint activateConstraints:@[
    [self.headerContainer.topAnchor constraintEqualToAnchor:guide.topAnchor],
    [self.headerContainer.leadingAnchor
        constraintEqualToAnchor:guide.leadingAnchor],
    [self.headerContainer.trailingAnchor
        constraintEqualToAnchor:guide.trailingAnchor],
    [self.headerContainer.heightAnchor constraintEqualToConstant:30],

    [self.addressLabel.centerYAnchor
        constraintEqualToAnchor:self.headerContainer.centerYAnchor],
    [self.addressLabel.centerXAnchor
        constraintEqualToAnchor:self.headerContainer.centerXAnchor],

    [self.mainStackView.topAnchor
        constraintEqualToAnchor:self.headerContainer.bottomAnchor],
    [self.mainStackView.leadingAnchor
        constraintEqualToAnchor:guide.leadingAnchor],
    [self.mainStackView.trailingAnchor
        constraintEqualToAnchor:guide.trailingAnchor],
    [self.mainStackView.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor]
  ]];
}

- (void)viewDidLayoutSubviews {
  [super viewDidLayoutSubviews];

  CGFloat totalWidth = self.view.bounds.size.width;

  BOOL isWide = (totalWidth > 500);

  CGFloat newFontSize = isWide ? 17.0 : 13.0;
  CGFloat newRowHeight = isWide ? 28.0 : 22.0;

  CGFloat newHexWidth = isWide ? 340.0 : 260.0;

  if (self.viewModeSegment.selectedSegmentIndex != 1) {
    newFontSize += 2.0;
  }

  if (self.hexWidthConstraint.constant != newHexWidth) {
    self.hexWidthConstraint.constant = newHexWidth;
  }

  if (self.currentFontSize != newFontSize ||
      self.hexTableView.rowHeight != newRowHeight) {
    self.currentFontSize = newFontSize;
    self.hexTableView.rowHeight = newRowHeight;
    self.asciiTableView.rowHeight = newRowHeight;
    [self reloadBothTables];
  }
}

- (UITableView *)createTableViewWithID:(NSString *)cellID
                                    bg:(UIColor *)bgColor {
  UITableView *tb = [[UITableView alloc] initWithFrame:CGRectZero
                                                 style:UITableViewStylePlain];
  tb.delegate = self;
  tb.dataSource = self;
  tb.rowHeight = 22.0;
  tb.separatorStyle = UITableViewCellSeparatorStyleNone;
  tb.backgroundColor = bgColor;
  tb.showsVerticalScrollIndicator = NO;
  [tb registerClass:[UITableViewCell class] forCellReuseIdentifier:cellID];
  return tb;
}

#pragma mark - 3. 视图模式切换
- (void)viewModeChanged:(UISegmentedControl *)seg {
  NSInteger idx = seg.selectedSegmentIndex;

  [self.view setNeedsLayout];
  [self.view layoutIfNeeded];

  [UIView animateWithDuration:0.3
                   animations:^{
                     if (idx == 0) {
                       self.hexTableView.hidden = NO;
                       self.asciiTableView.hidden = YES;
                       self.dividerLine.hidden = YES;
                       self.hexWidthConstraint.active = NO;
                     } else if (idx == 1) {
                       self.hexTableView.hidden = NO;
                       self.asciiTableView.hidden = NO;
                       self.dividerLine.hidden = NO;
                       self.hexWidthConstraint.active = YES;
                     } else {
                       self.hexTableView.hidden = YES;
                       self.asciiTableView.hidden = NO;
                       self.dividerLine.hidden = YES;
                       self.hexWidthConstraint.active = NO;
                     }
                     [self.view layoutIfNeeded];
                   }];

  if (idx == 0)
    self.hexTableView.contentOffset = self.asciiTableView.contentOffset;
  if (idx == 2)
    self.asciiTableView.contentOffset = self.hexTableView.contentOffset;

  [self viewDidLayoutSubviews];
}

#pragma mark - 数据加载
- (void)loadInitialData {
  size_t size = BYTES_PER_ROW * LOAD_CHUNK_ROWS;
  NSData *data = [[VMMemoryEngine shared] readRawMemory:self.address
                                                 length:size];
  if (data)
    [self.memoryBuffer appendData:data];
}

- (void)loadMoreData:(BOOL)next {
  if (self.isLoading)
    return;
  self.isLoading = YES;

  size_t rowsToLoad = LOAD_CHUNK_ROWS;
  size_t bytesToLoad = BYTES_PER_ROW * rowsToLoad;

  if (next) {
    
    uint64_t nextAddr = self.startAddress + self.memoryBuffer.length;
    NSData *d = [[VMMemoryEngine shared] readRawMemory:nextAddr
                                                length:bytesToLoad];

    dispatch_async(dispatch_get_main_queue(), ^{
      if (d && d.length > 0) {
        [self.memoryBuffer appendData:d];
        [self reloadBothTables];
      }
      self.isLoading = NO;
    });

  } else {
    
    uint64_t prevAddr = self.startAddress - bytesToLoad;
    NSData *d = [[VMMemoryEngine shared] readRawMemory:prevAddr
                                                length:bytesToLoad];

    dispatch_async(dispatch_get_main_queue(), ^{
      if (d && d.length > 0) {
        
        NSUInteger addedRows = d.length / BYTES_PER_ROW;
        if (d.length % BYTES_PER_ROW != 0)
          addedRows++;

        NSMutableData *comb = [d mutableCopy];
        [comb appendData:self.memoryBuffer];
        self.memoryBuffer = comb;
        self.startAddress = prevAddr;

        NSMutableArray *indexPaths = [NSMutableArray arrayWithCapacity:addedRows];
        for (NSUInteger i = 0; i < addedRows; i++) {
          [indexPaths addObject:[NSIndexPath indexPathForRow:i inSection:0]];
        }

        [CATransaction begin];
        [CATransaction setDisableActions:YES];

        [self.hexTableView beginUpdates];
        [self.hexTableView insertRowsAtIndexPaths:indexPaths
                                 withRowAnimation:UITableViewRowAnimationNone];
        [self.hexTableView endUpdates];

        [self.asciiTableView beginUpdates];
        [self.asciiTableView insertRowsAtIndexPaths:indexPaths
                                   withRowAnimation:UITableViewRowAnimationNone];
        [self.asciiTableView endUpdates];

        [CATransaction commit];

        self.addressLabel.text = [NSString
            stringWithFormat:TR(@"Hex_Start_Addr"), self.startAddress];
      }
      self.isLoading = NO;
    });
  }
}

#pragma mark - Cell 配置
- (NSInteger)tableView:(UITableView *)tableView
    numberOfRowsInSection:(NSInteger)section {
  return self.memoryBuffer.length / BYTES_PER_ROW;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
  BOOL isHex = (tableView == self.hexTableView);
  NSString *cellID = isHex ? @"HexCell" : @"AsciiCell";
  UITableViewCell *cell =
      [tableView dequeueReusableCellWithIdentifier:cellID
                                      forIndexPath:indexPath];

  cell.layoutMargins = UIEdgeInsetsZero;
  cell.preservesSuperviewLayoutMargins = NO;
  cell.separatorInset = UIEdgeInsetsZero;
  cell.contentView.layoutMargins = UIEdgeInsetsZero;
  cell.accessoryType = UITableViewCellAccessoryNone;
  cell.selectionStyle = UITableViewCellSelectionStyleDefault;

  uint64_t rowAddr = self.startAddress + (indexPath.row * BYTES_PER_ROW);
  NSRange range = NSMakeRange(indexPath.row * BYTES_PER_ROW, BYTES_PER_ROW);
  if (range.location + range.length > self.memoryBuffer.length)
    return cell;

  NSData *rowData = [self.memoryBuffer subdataWithRange:range];
  const uint8_t *bytes = (const uint8_t *)rowData.bytes;

  cell.textLabel.font = [UIFont monospacedSystemFontOfSize:self.currentFontSize
                                                    weight:UIFontWeightRegular];
  cell.textLabel.adjustsFontSizeToFitWidth = YES;
  cell.textLabel.minimumScaleFactor = 0.5;

  if (isHex) {
    NSMutableString *hexStr = [NSMutableString string];
    for (int i = 0; i < rowData.length; i++)
      [hexStr appendFormat:@"%02X ", bytes[i]];
    cell.textLabel.text =
        [NSString stringWithFormat:@"%llX %@", rowAddr, hexStr];
    cell.textLabel.textColor = [UIColor labelColor];
  } else {
    NSMutableString *ascStr = [NSMutableString string];
    for (int i = 0; i < rowData.length; i++) {
      uint8_t b = bytes[i];

      NSString *fmt = @"%c  ";
      if (self.currentFontSize < 15.0 &&
          self.viewModeSegment.selectedSegmentIndex == 1) {
        fmt = @"%c ";
      }

      if (b >= 0x20 && b <= 0x7E)
        [ascStr appendFormat:fmt, b];
      else {
        NSString *ph = [fmt stringByReplacingOccurrencesOfString:@"%c"
                                                      withString:@"."];
        [ascStr appendFormat:@"%@", ph];
      }
    }

    if (self.viewModeSegment.selectedSegmentIndex == 1) {
      cell.textLabel.text = ascStr;
    } else {
      cell.textLabel.text =
          [NSString stringWithFormat:@"%llX  %@", rowAddr, ascStr];
    }
    cell.textLabel.textColor = [UIColor systemBlueColor];
  }

  cell.backgroundColor = [UIColor clearColor];
  return cell;
}

#pragma mark - 滚动同步
- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
  if (self.isLoading)
    return;

  if (self.viewModeSegment.selectedSegmentIndex == 1) {
    if (scrollView == self.hexTableView && !self.isAsciiScrolling) {
      self.isHexScrolling = YES;
      self.asciiTableView.contentOffset = self.hexTableView.contentOffset;
      self.isHexScrolling = NO;
    } else if (scrollView == self.asciiTableView && !self.isHexScrolling) {
      self.isAsciiScrolling = YES;
      self.hexTableView.contentOffset = self.asciiTableView.contentOffset;
      self.isAsciiScrolling = NO;
    }
  }

  CGFloat y = scrollView.contentOffset.y;
  CGFloat h = scrollView.frame.size.height;
  CGFloat contentH = scrollView.contentSize.height;
  
  CGFloat preloadThreshold = 200.0;
  if (contentH > 0) {
    if (y < preloadThreshold)
      [self loadMoreData:NO];
    if (y > contentH - h - preloadThreshold)
      [self loadMoreData:YES];
  }
}

- (void)reloadBothTables {
  [self.hexTableView reloadData];
  [self.asciiTableView reloadData];
}

- (void)promptJump {
  UIAlertController *alert =
      [UIAlertController alertControllerWithTitle:TR(@"Btn_Jump")
                                          message:TR(@"Prompt_Addr_Input")
                                   preferredStyle:UIAlertControllerStyleAlert];
  [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
    tf.keyboardType = UIKeyboardTypeASCIICapable;
  }];
  [alert
      addAction:[UIAlertAction
                    actionWithTitle:TR(@"Btn_Confirm")
                              style:UIAlertActionStyleDefault
                            handler:^(UIAlertAction *a) {
                              NSString *txt = alert.textFields.firstObject.text;

                              dispatch_after(
                                  dispatch_time(DISPATCH_TIME_NOW,
                                                (int64_t)(0.3 * NSEC_PER_SEC)),
                                  dispatch_get_main_queue(), ^{
                                    uint64_t addr =
                                        strtoull([txt UTF8String], NULL, 16);
                                    self.address = addr;
                                    self.startAddress = addr;
                                    self.memoryBuffer = [NSMutableData data];
                                    [self loadInitialData];
                                    [self reloadBothTables];
                                    self.addressLabel.text = [NSString
                                        stringWithFormat:TR(@"Hex_Start_Addr"),
                                                         self.startAddress];
                                  });
                            }]];
  [alert addAction:[UIAlertAction actionWithTitle:TR(@"Btn_Cancel")
                                            style:UIAlertActionStyleCancel
                                          handler:nil]];
  [self presentViewController:alert animated:YES completion:nil];
}

- (void)tableView:(UITableView *)tableView
    didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
  if (self.viewModeSegment.selectedSegmentIndex == 1) {
    UITableView *target = (tableView == self.hexTableView) ? self.asciiTableView
                                                           : self.hexTableView;
    [target selectRowAtIndexPath:indexPath
                        animated:NO
                  scrollPosition:UITableViewScrollPositionNone];
  }

  uint64_t rowAddr = self.startAddress + (indexPath.row * BYTES_PER_ROW);
  NSRange range = NSMakeRange(indexPath.row * BYTES_PER_ROW, BYTES_PER_ROW);
  NSData *rowData = [self.memoryBuffer subdataWithRange:range];

  VMHexRowEditorViewController *editor =
      [[VMHexRowEditorViewController alloc] init];
  editor.address = rowAddr;
  editor.originalData = rowData;
  editor.delegate = self;
  [self.navigationController pushViewController:editor animated:YES];
}

- (void)rowEditorDidSaveData:(NSData *)data atAddress:(uint64_t)address {
  BOOL isExec = [[VMMemoryEngine shared] isRegionExecutable:address];
  BOOL isJB = [[VMMemoryEngine shared] isDeviceJailbroken];

  if (isExec && !isJB) {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:TR(@"Alert_Exec_Warn_Title")
                         message:TR(@"Alert_Exec_Warn_Msg")
                  preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:[UIAlertAction actionWithTitle:TR(@"Btn_Cancel")
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];

    [alert addAction:[UIAlertAction
                         actionWithTitle:TR(@"Btn_Continue")
                                   style:UIAlertActionStyleDestructive
                                 handler:^(UIAlertAction *_Nonnull action) {
                                   [self performWriteData:data
                                                atAddress:address];
                                 }]];

    [self presentViewController:alert animated:YES completion:nil];
  } else {
    [self performWriteData:data atAddress:address];
  }
}

- (void)performWriteData:(NSData *)data atAddress:(uint64_t)address {
  BOOL success = NO;
  if ([[VMMemoryEngine shared] respondsToSelector:@selector(writeRawData:
                                                               toAddress:)]) {
    success = [[VMMemoryEngine shared] writeRawData:data toAddress:address];
  } else {
    kern_return_t kr = mach_vm_write([VMMemoryEngine shared].targetTask,
                                     address, (vm_offset_t)data.bytes,
                                     (mach_msg_type_number_t)data.length);
    success = (kr == KERN_SUCCESS);
  }

  if (success) {
    long offset = address - self.startAddress;
    if (offset >= 0 && offset + data.length <= self.memoryBuffer.length) {
      [self.memoryBuffer replaceBytesInRange:NSMakeRange(offset, data.length)
                                   withBytes:data.bytes];
      [self reloadBothTables];
      UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc]
          initWithStyle:UIImpactFeedbackStyleLight];
      [gen impactOccurred];
    }
  } else {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:TR(@"Alert_Fail")
                         message:TR(@"Err_Write_Permission")
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:TR(@"Btn_OK")
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
  }
}

@end
