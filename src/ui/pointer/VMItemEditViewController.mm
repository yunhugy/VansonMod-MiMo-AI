#import "VMItemEditViewController.h"
#import "../../utils/helpers/VMUIHelper.h"
#import "../../utils/models/VMScriptModel.h"
#import "../main/VMScriptViewController.h"
#import "include/VMLocalization.h"
#import "include/VMMemoryEngine.h"
#import "include/VMPointerChain.h"
#import "include/VMRVAPatch.h"
#import "include/VMSignatureModel.h"

#define TR(key) ([[VMLocalization shared] localizedString:key])

#define CYAN_COLOR [UIColor colorWithRed:0.0 green:0.8 blue:1.0 alpha:1.0]

@interface VMItemEditViewController () <
    UITableViewDelegate, UITableViewDataSource, UITextFieldDelegate>

@property(nonatomic, strong) UITableView *tableView;
@property(nonatomic, strong) UITextField *noteField;
@property(nonatomic, strong) UITextField *authorField;
@property(nonatomic, strong) UITextField *valueField;
@property(nonatomic, strong) UITextField *minField;
@property(nonatomic, strong) UITextField *maxField;
@property(nonatomic, strong) UISegmentedControl *modeSegment;
@property(nonatomic, strong) UITextField *sigField;
@property(nonatomic, strong) UITextField *offsetField;
@property(nonatomic, strong) UITextField *rvaHexField;
@property(nonatomic, strong) UITextField *rvaOrigHexField; 
@property(nonatomic, strong) UITextField *scriptContentField;
@property(nonatomic, strong) UISegmentedControl *typeSegment;

@property(nonatomic, strong) UITextField *switchOnField;
@property(nonatomic, strong) UITextField *switchOffField;
@property(nonatomic, strong) UITextField *resultTitleField;

@property(nonatomic, copy) void (^onSaveGeneral)(id updatedModel);

@end

@implementation VMItemEditViewController

+ (void)presentInController:(UIViewController *)vc
                      model:(id)model
                     onSave:(void (^)(id updatedModel))onSave {
  VMItemEditViewController *editVC = [VMItemEditViewController new];
  editVC.model = model;
  editVC.onSaveGeneral = onSave;

  UINavigationController *nav =
      [[UINavigationController alloc] initWithRootViewController:editVC];
  if (@available(iOS 15.0, *)) {
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    UISheetPresentationController *sheet = nav.sheetPresentationController;
    sheet.detents = @[
      UISheetPresentationControllerDetent.mediumDetent,
      UISheetPresentationControllerDetent.largeDetent
    ];
    sheet.prefersGrabberVisible = YES;
  } else {
    nav.modalPresentationStyle = UIModalPresentationFormSheet;
  }

  [vc presentViewController:nav animated:YES completion:nil];
}

- (void)viewDidLoad {
  [super viewDidLoad];

  if ([self.model isKindOfClass:NSClassFromString(@"VMPointerChain")]) {
    self.title = TR(@"Title_Edit_Ptr_Info");
  } else if ([self.model isKindOfClass:NSClassFromString(@"VMRVAPatch")]) {
    self.title = TR(@"Title_Edit_RVA_Info");
  } else if ([self.model
                 isKindOfClass:NSClassFromString(@"VMSignatureModel")]) {
    self.title = TR(@"Title_Edit_Sig_Info");
  } else if ([self.model isKindOfClass:NSClassFromString(@"VMScriptModel")]) {
    self.title = TR(@"Title_Edit_Script_Info");
  }

  self.view.backgroundColor = [UIColor systemBackgroundColor];

  self.navigationItem.leftBarButtonItem =
      [[UIBarButtonItem alloc] initWithTitle:TR(@"Btn_Cancel")
                                       style:UIBarButtonItemStylePlain
                                      target:self
                                      action:@selector(onCancel)];
  self.navigationItem.rightBarButtonItem =
      [[UIBarButtonItem alloc] initWithTitle:TR(@"Btn_Confirm")
                                       style:UIBarButtonItemStyleDone
                                      target:self
                                      action:@selector(onSaveBtn)];
  self.navigationItem.rightBarButtonItem.tintColor = CYAN_COLOR;

  [self setupTableView];
}

- (void)setupTableView {
  self.tableView =
      [[UITableView alloc] initWithFrame:self.view.bounds
                                   style:UITableViewStyleInsetGrouped];
  self.tableView.delegate = self;
  self.tableView.dataSource = self;
  self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
  self.tableView.autoresizingMask =
      UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  [self.view addSubview:self.tableView];

  self.tableView.tableFooterView =
      [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, CGFLOAT_MIN)];
  self.tableView.sectionFooterHeight = 0;
}

#pragma mark - Actions

- (void)onCancel {
  [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)onSaveBtn {
  BOOL isImported = [[self.model valueForKey:@"isImported"] boolValue];
  
  BOOL isMaskedSig = [self.sigField.text isEqualToString:@"********"];
  BOOL isMaskedOffset = [self.offsetField.text isEqualToString:@"****"];
  BOOL isMaskedHex = [self.rvaHexField.text isEqualToString:@"********"];

  [self.model setValue:self.noteField.text forKey:@"note"];

  if ([self.model isKindOfClass:NSClassFromString(@"VMPointerChain")]) {
    VMPointerChain *chain = (VMPointerChain *)self.model;
    
    chain.lockValue = self.valueField.text;
    
    NSInteger segIdx = self.modeSegment.selectedSegmentIndex;
    if (segIdx == 0) {
      chain.uiMode = VMPointerUIModeInput;
      chain.type = @"card";
    } else if (segIdx == 1) {
      chain.uiMode = VMPointerUIModeSlider;
      chain.type = @"slider";
    } else {
      chain.uiMode = VMPointerUIModeSwitch;
      chain.type = @"switch";
    }
    
    static const VMDataType typeMap[] = {
      VMDataTypeInt8, VMDataTypeInt16, VMDataTypeInt32, VMDataTypeInt64,
      VMDataTypeFloat, VMDataTypeDouble
    };
    NSInteger typeIdx = self.typeSegment.selectedSegmentIndex;
    chain.lockType = (typeIdx >= 0 && typeIdx < 6) ? typeMap[typeIdx] : VMDataTypeInt32;
    if (chain.uiMode == VMPointerUIModeSlider) {
      chain.uiMin = [self.minField.text floatValue];
      chain.uiMax = [self.maxField.text floatValue];
    } else if (chain.uiMode == VMPointerUIModeSwitch) {
      
      chain.switchOnValue = self.switchOnField.text ?: @"1";
      chain.switchOffValue = self.switchOffField.text ?: @"0";
      chain.resultTitle = self.resultTitleField.text ?: @"";
    }
    
    if (!isImported) {
      chain.author = self.authorField.text;
      if (chain.isSignatureMode) {
        if (!isMaskedSig) chain.signature = self.sigField.text;
        if (!isMaskedOffset) {
          unsigned long long offVal = 0;
          NSScanner *scanner = [NSScanner scannerWithString:self.offsetField.text];
          if ([self.offsetField.text hasPrefix:@"0x"] || [self.offsetField.text hasPrefix:@"0X"]) scanner.scanLocation = 2;
          [scanner scanHexLongLong:&offVal];
          chain.offsets = @[ @(offVal) ];
        }
      }
    }
  } else if ([self.model isKindOfClass:NSClassFromString(@"VMRVAPatch")]) {
    VMRVAPatch *patch = (VMRVAPatch *)self.model;
    
    if (!isImported) {
      if (!isMaskedHex) patch.patchHex = self.rvaHexField.text;
      
      BOOL isMaskedOrigHex = [self.rvaOrigHexField.text isEqualToString:@"********"];
      if (!isMaskedOrigHex) patch.originalHex = self.rvaOrigHexField.text;
      patch.author = self.authorField.text;
    }
  } else if ([self.model isKindOfClass:NSClassFromString(@"VMSignatureModel")]) {
    VMSignatureModel *sig = (VMSignatureModel *)self.model;
    
    static const VMDataType sigTypeMap[] = {
      VMDataTypeInt8, VMDataTypeInt16, VMDataTypeInt32, VMDataTypeInt64,
      VMDataTypeFloat, VMDataTypeDouble
    };
    NSInteger typeIdx = self.typeSegment.selectedSegmentIndex;
    sig.lockType = (typeIdx >= 0 && typeIdx < 6) ? sigTypeMap[typeIdx] : VMDataTypeInt32;
    
    if (!isImported) {
      if (!isMaskedSig) sig.signature = self.sigField.text;
      sig.author = self.authorField.text;
      if (!isMaskedOffset) {
        unsigned int offVal = 0;
        NSScanner *scanner = [NSScanner scannerWithString:self.offsetField.text];
        if ([self.offsetField.text hasPrefix:@"0x"] || [self.offsetField.text hasPrefix:@"0X"]) scanner.scanLocation = 2;
        [scanner scanHexInt:&offVal];
        sig.offset = offVal;
      }
    }
  } else if ([self.model isKindOfClass:NSClassFromString(@"VMScriptModel")]) {
    VMScriptModel *script = (VMScriptModel *)self.model;
    
    if (!isImported) {
      script.author = self.authorField.text;
    }
  }

  if (self.onSaveGeneral) {
    self.onSaveGeneral(self.model);
  }
  [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - TableView DataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
  return 1;
}

- (NSInteger)tableView:(UITableView *)tableView
    numberOfRowsInSection:(NSInteger)section {
  if ([self.model isKindOfClass:NSClassFromString(@"VMPointerChain")]) {
    VMPointerChain *chain = (VMPointerChain *)self.model;
    BOOL imported = [[self.model valueForKey:@"isImported"] boolValue];
    
    int rows = imported ? 5 : 7;
    if (chain.isSignatureMode)
      rows += 1; 
    else
      rows += 1; 
    if (chain.uiMode == VMPointerUIModeSlider)
      rows += 2; 
    else if (chain.uiMode == VMPointerUIModeSwitch)
      rows += 3; 
    return rows;
  } else if ([self.model isKindOfClass:NSClassFromString(@"VMRVAPatch")]) {
    BOOL imported = [[self.model valueForKey:@"isImported"] boolValue];
    
    return imported ? 4 : 6;
  } else if ([self.model
                 isKindOfClass:NSClassFromString(@"VMSignatureModel")]) {
    BOOL imported = [[self.model valueForKey:@"isImported"] boolValue];
    
    return imported ? 4 : 6;
  } else if ([self.model isKindOfClass:NSClassFromString(@"VMScriptModel")]) {
    BOOL imported = [[self.model valueForKey:@"isImported"] boolValue];
    
    return imported ? 2 : 4;
  }
  return 0;
}

- (NSString *)tableView:(UITableView *)tableView
    titleForHeaderInSection:(NSInteger)section {
  return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
  UITableViewCell *cell =
      [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
                             reuseIdentifier:nil];
  cell.selectionStyle = UITableViewCellSelectionStyleNone;
  cell.textLabel.font = [UIFont systemFontOfSize:14];
  cell.detailTextLabel.font = [UIFont systemFontOfSize:13];
  cell.detailTextLabel.textColor = [UIColor systemGrayColor];

  id m = self.model;
  BOOL isImported = [[m valueForKey:@"isImported"] boolValue];

  NSInteger row = indexPath.row;

  if ([m isKindOfClass:NSClassFromString(@"VMPointerChain")]) {
    VMPointerChain *chain = (VMPointerChain *)m;
    NSInteger currentRow = 0;

    if (currentRow++ == row) {
      cell.textLabel.text = TR(@"Lab_Note_Colon");
      if (!self.noteField) {
        self.noteField =
            [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 200, 44)];
        self.noteField.text = chain.note;
        self.noteField.textAlignment = NSTextAlignmentRight;
        self.noteField.placeholder = TR(@"Placeholder_Note");
        self.noteField.font = [UIFont systemFontOfSize:14];
      }
      cell.accessoryView = self.noteField;
      return cell;
    }

    if (currentRow++ == row) {
      cell.textLabel.text = TR(@"Value_Type");
      if (!self.typeSegment) {
        self.typeSegment = [[UISegmentedControl alloc] initWithItems:@[
          TR(@"Type_I8"), TR(@"Type_I16"), TR(@"Type_I32"), TR(@"Type_I64"),
          TR(@"Type_F32"), TR(@"Type_F64")
        ]];
        
        int idx = 2; 
        switch ((VMDataType)chain.lockType) {
          case VMDataTypeInt8: case VMDataTypeUInt8: idx = 0; break;
          case VMDataTypeInt16: case VMDataTypeUInt16: idx = 1; break;
          case VMDataTypeInt32: case VMDataTypeUInt32: idx = 2; break;
          case VMDataTypeInt64: case VMDataTypeUInt64: idx = 3; break;
          case VMDataTypeFloat: idx = 4; break;
          case VMDataTypeDouble: idx = 5; break;
          default: idx = 2; break;
        }
        self.typeSegment.selectedSegmentIndex = idx;
      }
      cell.accessoryView = self.typeSegment;
      return cell;
    }

    {
      if (chain.isSignatureMode) {
        if (currentRow++ == row) {
          cell.textLabel.text = TR(@"Sig_Label_Sig");
          if (!self.sigField) {
            self.sigField =
                [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 200, 44)];
            
            self.sigField.text = chain.signature;
            self.sigField.textAlignment = NSTextAlignmentRight;
            self.sigField.font = [UIFont fontWithName:@"Menlo" size:12];
            if (isImported) {
              self.sigField.enabled = NO;
              self.sigField.textColor = [UIColor systemGrayColor];
            }
          }
          cell.accessoryView = self.sigField;
          return cell;
        }
        if (currentRow++ == row) {
          cell.textLabel.text = TR(@"Sig_Label_Offset");
          if (!self.offsetField) {
            self.offsetField =
                [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 150, 44)];
            long long off = (chain.offsets.count > 0)
                                ? [chain.offsets[0] longLongValue]
                                : 0;
            self.offsetField.text =
                [NSString stringWithFormat:@"0x%llX", off];
            self.offsetField.textAlignment = NSTextAlignmentRight;
            if (isImported) {
              self.offsetField.enabled = NO;
              self.offsetField.textColor = [UIColor systemGrayColor];
            }
          }
          cell.accessoryView = self.offsetField;
          return cell;
        }
      } else {
        if (currentRow++ == row) {
          cell.textLabel.text = TR(@"Ptr_Label_Chain");
          cell.detailTextLabel.text =
              [chain displayString];
          cell.detailTextLabel.font = [UIFont fontWithName:@"Menlo" size:11];
          cell.detailTextLabel.numberOfLines = 2;
          cell.selectionStyle = UITableViewCellSelectionStyleDefault;
          return cell;
        }
      }
    }

    if (currentRow++ == row) {
      cell.textLabel.text = TR(@"Lock_Label_Value");
      if (!self.valueField) {
        self.valueField =
            [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 150, 44)];
        self.valueField.text = chain.lockValue;
        self.valueField.textAlignment = NSTextAlignmentRight;
        self.valueField.placeholder = TR(@"Placeholder_LockValue");
        self.valueField.keyboardType = UIKeyboardTypeDecimalPad;
      }
      cell.accessoryView = self.valueField;
      return cell;
    }

    if (currentRow++ == row) {
      cell.textLabel.text = TR(@"Display_Mode");
      if (!self.modeSegment) {
        self.modeSegment = [[UISegmentedControl alloc] initWithItems:@[
          TR(@"Mode_Switch_Card"), TR(@"Mode_Switch_Slider"), TR(@"Mode_Switch_Toggle")
        ]];
        NSInteger segIdx = 0;
        if (chain.uiMode == VMPointerUIModeSlider) segIdx = 1;
        else if (chain.uiMode == VMPointerUIModeSwitch) segIdx = 2;
        self.modeSegment.selectedSegmentIndex = segIdx;
        [self.modeSegment addTarget:self
                             action:@selector(onModeChange:)
                   forControlEvents:UIControlEventValueChanged];
      }
      cell.accessoryView = self.modeSegment;
      return cell;
    }

    if (chain.uiMode == VMPointerUIModeSlider) {
      if (currentRow++ == row) {
        cell.textLabel.text = TR(@"Slider_Min");
        if (!self.minField) {
          self.minField =
              [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 100, 44)];
          self.minField.text = [NSString stringWithFormat:@"%.0f", chain.uiMin];
          self.minField.textAlignment = NSTextAlignmentRight;
          self.minField.keyboardType = UIKeyboardTypeDecimalPad;
        }
        cell.accessoryView = self.minField;
        return cell;
      }
      if (currentRow++ == row) {
        cell.textLabel.text = TR(@"Slider_Max");
        if (!self.maxField) {
          self.maxField =
              [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 100, 44)];
          self.maxField.text = [NSString stringWithFormat:@"%.0f", chain.uiMax];
          self.maxField.textAlignment = NSTextAlignmentRight;
          self.maxField.keyboardType = UIKeyboardTypeDecimalPad;
        }
        cell.accessoryView = self.maxField;
        return cell;
      }
    }
    
    if (chain.uiMode == VMPointerUIModeSwitch) {
      if (currentRow++ == row) {
        cell.textLabel.text = @"ON 值";
        cell.textLabel.textColor = [UIColor systemGreenColor];
        if (!self.switchOnField) {
          self.switchOnField =
              [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 150, 44)];
          self.switchOnField.text = chain.switchOnValue ?: @"1";
          self.switchOnField.textAlignment = NSTextAlignmentRight;
          self.switchOnField.placeholder = @"1";
          self.switchOnField.keyboardType = UIKeyboardTypeDecimalPad;
        }
        cell.accessoryView = self.switchOnField;
        return cell;
      }
      if (currentRow++ == row) {
        cell.textLabel.text = @"OFF 值";
        cell.textLabel.textColor = [UIColor systemRedColor];
        if (!self.switchOffField) {
          self.switchOffField =
              [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 150, 44)];
          self.switchOffField.text = chain.switchOffValue ?: @"0";
          self.switchOffField.textAlignment = NSTextAlignmentRight;
          self.switchOffField.placeholder = @"0";
          self.switchOffField.keyboardType = UIKeyboardTypeDecimalPad;
        }
        cell.accessoryView = self.switchOffField;
        return cell;
      }
      if (currentRow++ == row) {
        cell.textLabel.text = TR(@"Item_Title");
        if (!self.resultTitleField) {
          self.resultTitleField =
              [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 200, 44)];
          self.resultTitleField.text = chain.resultTitle ?: @"";
          self.resultTitleField.textAlignment = NSTextAlignmentRight;
          self.resultTitleField.placeholder = TR(@"Item_Title_Placeholder");
          self.resultTitleField.font = [UIFont systemFontOfSize:14];
        }
        cell.accessoryView = self.resultTitleField;
        return cell;
      }
    }

    if (!isImported) {
      if (currentRow++ == row) {
        cell.textLabel.text = TR(@"Lab_Auth_Colon");
        if (!self.authorField) {
          self.authorField =
              [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 200, 44)];
          self.authorField.text = chain.author;
          self.authorField.textAlignment = NSTextAlignmentRight;
          self.authorField.placeholder = TR(@"Placeholder_Author");
          self.authorField.font = [UIFont systemFontOfSize:14];
        }
        cell.accessoryView = self.authorField;
        return cell;
      }
    }
  } else if ([m isKindOfClass:NSClassFromString(@"VMRVAPatch")]) {
    
    VMRVAPatch *p = (VMRVAPatch *)m;
    NSInteger currentRow = 0;

    if (currentRow++ == row) {
      cell.textLabel.text = TR(@"Lab_Note_Colon");
      if (!self.noteField) {
        self.noteField =
            [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 200, 44)];
        self.noteField.text = p.note;
        self.noteField.textAlignment = NSTextAlignmentRight;
        self.noteField.placeholder = TR(@"Placeholder_Note");
        self.noteField.font = [UIFont systemFontOfSize:14];
      }
      cell.accessoryView = self.noteField;
      return cell;
    }

    if (currentRow++ == row) {
      cell.textLabel.text = TR(@"RVA_Label_Loc");
      cell.detailTextLabel.text =
          [p displayString];
      cell.detailTextLabel.font = [UIFont fontWithName:@"Menlo" size:11];
          cell.selectionStyle = UITableViewCellSelectionStyleDefault;
      return cell;
    }

    if (currentRow++ == row) {
      cell.textLabel.text = @"ON:";
      cell.textLabel.textColor = [UIColor systemGreenColor];
      if (!self.rvaHexField) {
        self.rvaHexField =
            [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 200, 44)];
        self.rvaHexField.text = p.patchHex;
        self.rvaHexField.textAlignment = NSTextAlignmentRight;
        self.rvaHexField.font = [UIFont fontWithName:@"Menlo" size:12];
        if (isImported) {
          self.rvaHexField.enabled = NO;
          self.rvaHexField.textColor = [UIColor systemGrayColor];
        }
      }
      cell.accessoryView = self.rvaHexField;
      return cell;
    }

    if (currentRow++ == row) {
      cell.textLabel.text = @"OFF:";
      cell.textLabel.textColor = [UIColor systemRedColor];
      if (!self.rvaOrigHexField) {
        self.rvaOrigHexField =
            [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 200, 44)];
        self.rvaOrigHexField.text = p.originalHex;
        self.rvaOrigHexField.textAlignment = NSTextAlignmentRight;
        self.rvaOrigHexField.font = [UIFont fontWithName:@"Menlo" size:12];
        if (isImported) {
          self.rvaOrigHexField.enabled = NO;
          self.rvaOrigHexField.textColor = [UIColor systemGrayColor];
        }
      }
      cell.accessoryView = self.rvaOrigHexField;
      return cell;
    }

    if (!isImported) {
      if (currentRow++ == row) {
        cell.textLabel.text = TR(@"Lab_Auth_Colon");
        if (!self.authorField) {
          self.authorField =
              [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 200, 44)];
          self.authorField.text = p.author;
          self.authorField.textAlignment = NSTextAlignmentRight;
          self.authorField.placeholder = TR(@"Placeholder_Author");
          self.authorField.font = [UIFont systemFontOfSize:14];
        }
        cell.accessoryView = self.authorField;
        return cell;
      }
    }
  } else if ([m isKindOfClass:NSClassFromString(@"VMSignatureModel")]) {
    
    VMSignatureModel *sig = (VMSignatureModel *)m;
    NSInteger currentRow = 0;

    if (currentRow++ == row) {
      cell.textLabel.text = TR(@"Lab_Note_Colon");
      if (!self.noteField) {
        self.noteField =
            [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 200, 44)];
        self.noteField.text = sig.note;
        self.noteField.textAlignment = NSTextAlignmentRight;
        self.noteField.placeholder = TR(@"Placeholder_Note");
        self.noteField.font = [UIFont systemFontOfSize:14];
      }
      cell.accessoryView = self.noteField;
      return cell;
    }

    if (currentRow++ == row) {
      cell.textLabel.text = TR(@"Value_Type");
      if (!self.typeSegment) {
        
        self.typeSegment = [[UISegmentedControl alloc] initWithItems:@[
          TR(@"Type_I8"), TR(@"Type_I16"), TR(@"Type_I32"), TR(@"Type_I64"),
          TR(@"Type_F32"), TR(@"Type_F64")
        ]];
        
        int idx = 2; 
        switch ((VMDataType)sig.lockType) {
          case VMDataTypeInt8: case VMDataTypeUInt8: idx = 0; break;
          case VMDataTypeInt16: case VMDataTypeUInt16: idx = 1; break;
          case VMDataTypeInt32: case VMDataTypeUInt32: idx = 2; break;
          case VMDataTypeInt64: case VMDataTypeUInt64: idx = 3; break;
          case VMDataTypeFloat: idx = 4; break;
          case VMDataTypeDouble: idx = 5; break;
          default: idx = 2; break;
        }
        self.typeSegment.selectedSegmentIndex = idx;
      }
      cell.accessoryView = self.typeSegment;
      return cell;
    }

    if (currentRow++ == row) {
      cell.textLabel.text = TR(@"Sig_Label_Sig");
      if (!self.sigField) {
        self.sigField =
            [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 200, 44)];
        self.sigField.text = sig.signature;
        self.sigField.textAlignment = NSTextAlignmentRight;
        self.sigField.font = [UIFont fontWithName:@"Menlo" size:12];
        if (isImported) {
          self.sigField.enabled = NO;
          self.sigField.textColor = [UIColor systemGrayColor];
        }
      }
      cell.accessoryView = self.sigField;
      return cell;
    }

    if (currentRow++ == row) {
      cell.textLabel.text = TR(@"Sig_Label_Offset");
      if (!self.offsetField) {
        self.offsetField =
            [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 150, 44)];
        self.offsetField.text =
            [NSString stringWithFormat:@"0x%X", sig.offset];
        self.offsetField.textAlignment = NSTextAlignmentRight;
        self.offsetField.font = [UIFont fontWithName:@"Menlo" size:12];
        if (isImported) {
          self.offsetField.enabled = NO;
          self.offsetField.textColor = [UIColor systemGrayColor];
        }
      }
      cell.accessoryView = self.offsetField;
      return cell;
    }

    if (!isImported) {
      if (currentRow++ == row) {
        cell.textLabel.text = TR(@"Lab_Auth_Colon");
        if (!self.authorField) {
          self.authorField =
              [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 200, 44)];
          self.authorField.text = sig.author;
          self.authorField.textAlignment = NSTextAlignmentRight;
          self.authorField.placeholder = TR(@"Placeholder_Author");
          self.authorField.font = [UIFont systemFontOfSize:14];
        }
        cell.accessoryView = self.authorField;
        return cell;
      }
    }
  } else if ([m isKindOfClass:NSClassFromString(@"VMScriptModel")]) {
    
    VMScriptModel *script = (VMScriptModel *)m;
    NSInteger currentRow = 0;

    if (currentRow++ == row) {
      cell.textLabel.text = TR(@"Lab_Note_Colon");
      if (!self.noteField) {
        self.noteField =
            [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 200, 44)];
        self.noteField.text = script.note;
        self.noteField.textAlignment = NSTextAlignmentRight;
        self.noteField.placeholder = TR(@"Placeholder_Note");
        self.noteField.font = [UIFont systemFontOfSize:14];
      }
      cell.accessoryView = self.noteField;
      return cell;
    }

    if (currentRow++ == row) {
      cell.textLabel.text = TR(@"Lab_BundleId");
      cell.detailTextLabel.text = script.bundleID ?: @"-";
      cell.detailTextLabel.font = [UIFont fontWithName:@"Menlo" size:11];
      return cell;
    }

    if (!isImported) {
      if (currentRow++ == row) {
        cell.textLabel.text = TR(@"Lab_Auth_Colon");
        if (!self.authorField) {
          self.authorField =
              [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 200, 44)];
          self.authorField.text = script.author;
          self.authorField.textAlignment = NSTextAlignmentRight;
          self.authorField.placeholder = TR(@"Placeholder_Author");
          self.authorField.font = [UIFont systemFontOfSize:14];
        }
        cell.accessoryView = self.authorField;
        return cell;
      }
    }
  }

  return cell;
}

- (void)tableView:(UITableView *)tableView
    didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
  [tableView deselectRowAtIndexPath:indexPath animated:YES];

  UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
  UIView *acc = cell.accessoryView;
  if ([acc isKindOfClass:[UITextField class]]) {
    UITextField *tf = (UITextField *)acc;
    if (tf.enabled) {
      [tf becomeFirstResponder];
    } else {
      [self showToast:TR(@"Edit_ReadOnly_Hint")];
    }
    return;
  }

  id m = self.model;
  NSString *textToCopy = nil;

  if ([m isKindOfClass:NSClassFromString(@"VMPointerChain")]) {
    VMPointerChain *chain = (VMPointerChain *)m;
    if ([cell.textLabel.text containsString:TR(@"Ptr_Label_Chain")]) {
      textToCopy = [chain displayString];
    }
  } else if ([m isKindOfClass:NSClassFromString(@"VMRVAPatch")]) {
    VMRVAPatch *p = (VMRVAPatch *)m;
    if (indexPath.row == 3) {
      textToCopy = [p displayString];
    }
  } else if ([m isKindOfClass:NSClassFromString(@"VMSignatureModel")]) {
    VMSignatureModel *sig = (VMSignatureModel *)m;
    if (indexPath.row == 4) {
      textToCopy = [NSString stringWithFormat:@"0x%X", sig.offset];
    }
  } else if ([m isKindOfClass:NSClassFromString(@"VMScriptModel")]) {
    if (indexPath.row == 3) {
      VMScriptModel *s = (VMScriptModel *)m;
      
      VMScriptViewController *svc = [[VMScriptViewController alloc] init];
      svc.scriptModel = s;
      [self.navigationController pushViewController:svc animated:YES];
    }
  }

  if (textToCopy) {
    [[UIPasteboard generalPasteboard] setString:textToCopy];
    [self showToast:TR(@"Msg_Copied")];
    UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc]
        initWithStyle:UIImpactFeedbackStyleLight];
    [gen impactOccurred];
  }
}

- (void)showToast:(NSString *)msg {
  
  UILabel *label = [[UILabel alloc] init];
  label.text = msg;
  label.font = [UIFont systemFontOfSize:13];
  label.textColor = [UIColor whiteColor];
  label.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.7];
  label.textAlignment = NSTextAlignmentCenter;
  label.layer.cornerRadius = 15;
  label.clipsToBounds = YES;

  CGSize size = [msg sizeWithAttributes:@{NSFontAttributeName : label.font}];
  label.frame = CGRectMake(0, 0, size.width + 30, 30);
  label.center = CGPointMake(self.view.bounds.size.width / 2,
                             self.view.bounds.size.height - 100);
  [self.view addSubview:label];

  [UIView animateWithDuration:0.3
      delay:1.5
      options:0
      animations:^{
        label.alpha = 0;
      }
      completion:^(BOOL finished) {
        [label removeFromSuperview];
      }];
}

- (void)onModeChange:(UISegmentedControl *)sender {
  if ([self.model isKindOfClass:NSClassFromString(@"VMPointerChain")]) {
    VMPointerChain *chain = (VMPointerChain *)self.model;
    NSInteger segIdx = sender.selectedSegmentIndex;
    if (segIdx == 0) {
      chain.uiMode = VMPointerUIModeInput;
    } else if (segIdx == 1) {
      chain.uiMode = VMPointerUIModeSlider;
    } else {
      chain.uiMode = VMPointerUIModeSwitch;
    }
    
    [self.tableView reloadData];
  }
}

@end
