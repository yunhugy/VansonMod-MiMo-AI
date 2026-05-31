#import "VMScriptViewController.h"
#import "../../utils/helpers/VMUIHelper.h"
#import "../../utils/managers/VMScriptManager.h"
#import "../../utils/managers/VMAIManager.h"
#import "VMScriptToolsViewController.h"
#import "include/VMDataSession.h"
#import "include/VMLocalization.h"
#import "include/VMMemoryEngine.h"
#import "include/VMPointerManager.h" // 用于获取路径工具
#import <objc/runtime.h>

#define TR(key) ([[VMLocalization shared] localizedString:key])

@class VMAIChatPanel;

@interface VMScriptViewController () <UITextViewDelegate>

@property(nonatomic, strong) UIView *headerView;
@property(nonatomic, strong) UILabel *infoLabel;
@property(nonatomic, strong) UITextView *editorView;
@property(nonatomic, strong) UITextView *consoleView;
@property(nonatomic, strong) UIScrollView *shortcutBar; 
@property(nonatomic, strong) UIStackView *shortcutStack;
@property(nonatomic, strong) UIView *bottomBar;
@property(nonatomic, strong) UIButton *btnRun;

@property(nonatomic, strong) UIButton *btnSave;
@end

@implementation VMScriptViewController

- (void)viewDidLoad {
  [super viewDidLoad];
  self.view.backgroundColor =
      [UIColor systemGroupedBackgroundColor]; 
  [self setupUI]; 

  [self setupNavigationTitle];

  self.navigationItem.rightBarButtonItem = nil;

  self.editorView.text = self.scriptModel.scriptContent;

  if (self.scriptModel.isImported) {
    self.editorView.editable = NO;
    self.editorView.textColor = [UIColor systemGrayColor];
    [self.btnSave setTitle:TR(@"Script_Btn_ReadOnly")
                  forState:UIControlStateNormal];
    self.btnSave.enabled = NO;
    self.btnSave.backgroundColor = [UIColor systemGrayColor];
    self.title = [NSString
        stringWithFormat:@"%@ %@", self.title, TR(@"Script_Title_ReadOnly")];
  }

  [self updateHeaderInfo];

  UITapGestureRecognizer *tap =
      [[UITapGestureRecognizer alloc] initWithTarget:self.view
                                              action:@selector(endEditing:)];
  [self.view addGestureRecognizer:tap];

  [[NSNotificationCenter defaultCenter]
      addObserver:self
         selector:@selector(keyboardWillShow:)
             name:UIKeyboardWillShowNotification
           object:nil];
  [[NSNotificationCenter defaultCenter]
      addObserver:self
         selector:@selector(keyboardWillHide:)
             name:UIKeyboardWillHideNotification
           object:nil];
}

- (void)updateHeaderInfo {
  self.infoLabel.text = [NSString
      stringWithFormat:@"%@ %@ | %@", TR(@"Script_Info_Author"),
                       self.scriptModel.author, self.scriptModel.desc ?: @""];
}

- (void)editNoteAction {
  if (self.scriptModel.isImported) {
    [self showToast:TR(@"Status_ReadOnly")];
    return;
  }

  UIAlertController *alert =
      [UIAlertController alertControllerWithTitle:TR(@"Title_Edit_Script_Info")
                                          message:nil
                                   preferredStyle:UIAlertControllerStyleAlert];

  [alert
      addTextFieldWithConfigurationHandler:^(UITextField *_Nonnull textField) {
        textField.text = self.scriptModel.note;
        textField.placeholder = TR(@"Script_Name_Placeholder");
      }];

  [alert
      addTextFieldWithConfigurationHandler:^(UITextField *_Nonnull textField) {
        textField.text = self.scriptModel.desc;
        textField.placeholder = TR(@"Script_Desc_Placeholder");
      }];

  [alert addAction:[UIAlertAction actionWithTitle:TR(@"Btn_Cancel")
                                            style:UIAlertActionStyleCancel
                                          handler:nil]];
  [alert
      addAction:[UIAlertAction
                    actionWithTitle:TR(@"Btn_Confirm")
                              style:UIAlertActionStyleDefault
                            handler:^(UIAlertAction *_Nonnull action) {
                              NSString *newNote = alert.textFields[0].text;
                              NSString *newDesc = alert.textFields[1].text;

                              if (newNote && newNote.length > 0) {
                                self.scriptModel.note = newNote;
                                [self updateNavigationTitle:newNote];
                              }

                              if (newDesc) { 
                                self.scriptModel.desc =
                                    (newDesc.length > 0)
                                        ? newDesc
                                        : TR(@"Script_Default_Desc");
                              }

                              [self updateHeaderInfo];

                              if ([self saveScriptModelToDisk]) {
                                
                              }
                            }]];

  [self presentViewController:alert animated:YES completion:nil];
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)undoEditor {
  if ([self.editorView.undoManager canUndo]) {
    [self.editorView.undoManager undo];
  }
}

- (void)clearEditor {
  if (self.scriptModel.isImported)
    return; 

  UIAlertController *alert =
      [UIAlertController alertControllerWithTitle:nil
                                          message:TR(@"Script_Clear_Confirm")
                                   preferredStyle:UIAlertControllerStyleAlert];

  [alert addAction:[UIAlertAction actionWithTitle:TR(@"Btn_Cancel")
                                            style:UIAlertActionStyleCancel
                                          handler:nil]];

  [alert addAction:[UIAlertAction actionWithTitle:TR(@"Btn_Confirm")
                                            style:UIAlertActionStyleDestructive
                                          handler:^(UIAlertAction *action) {
                                            self.editorView.text = @"";
                                          }]];

  [self presentViewController:alert animated:YES completion:nil];
}

- (void)setupUI {
  UILayoutGuide *g = self.view.safeAreaLayoutGuide;

  self.headerView = [[UIView alloc] init];
  self.headerView.translatesAutoresizingMaskIntoConstraints = NO;
  [self.view addSubview:self.headerView];

  self.infoLabel = [[UILabel alloc] init];
  self.infoLabel.font = [UIFont systemFontOfSize:12];
  self.infoLabel.textColor = [UIColor secondaryLabelColor];
  self.infoLabel.text = [NSString
      stringWithFormat:@"%@ %@ | %@ %@", TR(@"Script_Info_Author"),
                       self.scriptModel.author, TR(@"Script_Info_Bundle"),
                       self.scriptModel.bundleID];
  self.infoLabel.translatesAutoresizingMaskIntoConstraints = NO;
  [self.headerView addSubview:self.infoLabel];

  UIButton *btnUndo = [UIButton buttonWithType:UIButtonTypeSystem];
  [btnUndo setImage:[UIImage systemImageNamed:@"arrow.uturn.backward"]
           forState:UIControlStateNormal];
  [btnUndo setTintColor:[UIColor labelColor]];
  [btnUndo addTarget:self
                action:@selector(undoEditor)
      forControlEvents:UIControlEventTouchUpInside];
  btnUndo.translatesAutoresizingMaskIntoConstraints = NO;
  [self.headerView addSubview:btnUndo];

  UIButton *btnClear = [UIButton buttonWithType:UIButtonTypeSystem];
  [btnClear setImage:[UIImage systemImageNamed:@"trash"]
            forState:UIControlStateNormal];
  [btnClear setTintColor:[UIColor systemRedColor]];
  [btnClear addTarget:self
                action:@selector(clearEditor)
      forControlEvents:UIControlEventTouchUpInside];
  btnClear.translatesAutoresizingMaskIntoConstraints = NO;
  [self.headerView addSubview:btnClear];

  self.editorView = [[UITextView alloc] init];
  self.editorView.backgroundColor =
      [UIColor secondarySystemGroupedBackgroundColor];
  self.editorView.font = [UIFont fontWithName:@"Menlo" size:12];
  self.editorView.layer.cornerRadius = 8;
  self.editorView.translatesAutoresizingMaskIntoConstraints = NO;
  self.editorView.autocapitalizationType = UITextAutocapitalizationTypeNone;
  self.editorView.autocorrectionType = UITextAutocorrectionTypeNo;
  self.editorView.delegate = self;
  [self.view addSubview:self.editorView];

  UIStackView *toolStack = [[UIStackView alloc] init];
  toolStack.axis = UILayoutConstraintAxisHorizontal;
  toolStack.distribution = UIStackViewDistributionFillEqually;
  toolStack.spacing = 15;
  toolStack.translatesAutoresizingMaskIntoConstraints = NO;
  [self.view addSubview:toolStack];

  UIButton *btnShort = [UIButton buttonWithType:UIButtonTypeSystem];
  [btnShort setTitle:TR(@"Script_Btn_Shortcut") forState:UIControlStateNormal];
  [btnShort setBackgroundColor:[UIColor tertiarySystemGroupedBackgroundColor]];
  btnShort.layer.cornerRadius = 8;
  [btnShort addTarget:self
                action:@selector(onShortcutAction)
      forControlEvents:UIControlEventTouchUpInside];

  UIButton *btnEx = [UIButton buttonWithType:UIButtonTypeSystem];
  [btnEx setTitle:TR(@"Script_Btn_Template") forState:UIControlStateNormal];
  [btnEx setBackgroundColor:[UIColor tertiarySystemGroupedBackgroundColor]];
  btnEx.layer.cornerRadius = 8;
  [btnEx addTarget:self
                action:@selector(onExampleAction)
      forControlEvents:UIControlEventTouchUpInside];

  self.btnRun = [UIButton buttonWithType:UIButtonTypeSystem];
  [self.btnRun setTitle:TR(@"Script_Btn_Run") forState:UIControlStateNormal];
  [self.btnRun setTitleColor:[UIColor systemBlueColor]
                    forState:UIControlStateNormal];
  [self.btnRun
      setBackgroundColor:[UIColor tertiarySystemGroupedBackgroundColor]];
  self.btnRun.layer.cornerRadius = 8;
  [self.btnRun addTarget:self
                  action:@selector(runScript)
        forControlEvents:UIControlEventTouchUpInside];

  self.btnSave = [UIButton buttonWithType:UIButtonTypeSystem];
  [self.btnSave setTitle:TR(@"Script_Btn_Save") forState:UIControlStateNormal];
  [self.btnSave setTitleColor:[UIColor systemGreenColor]
                     forState:UIControlStateNormal];
  [self.btnSave
      setBackgroundColor:[UIColor tertiarySystemGroupedBackgroundColor]];
  self.btnSave.layer.cornerRadius = 8;
  [self.btnSave addTarget:self
                   action:@selector(saveScript)
         forControlEvents:UIControlEventTouchUpInside];

  UIButton *btnAI = [UIButton buttonWithType:UIButtonTypeSystem];
  [btnAI setTitle:@"✨AI" forState:UIControlStateNormal];
  [btnAI setTitleColor:[UIColor systemPurpleColor]
              forState:UIControlStateNormal];
  [btnAI setBackgroundColor:[UIColor tertiarySystemGroupedBackgroundColor]];
  btnAI.layer.cornerRadius = 8;
  [btnAI addTarget:self
             action:@selector(onAIAction)
   forControlEvents:UIControlEventTouchUpInside];

  [toolStack addArrangedSubview:btnShort];
  [toolStack addArrangedSubview:btnEx];
  [toolStack addArrangedSubview:btnAI];
  [toolStack addArrangedSubview:self.btnRun];
  [toolStack addArrangedSubview:self.btnSave];

  self.consoleView = [[UITextView alloc] init];
  self.consoleView.backgroundColor = [UIColor colorWithWhite:0.1 alpha:1.0];
  self.consoleView.textColor = [UIColor systemGreenColor];
  self.consoleView.font = [UIFont fontWithName:@"Menlo" size:11];
  self.consoleView.editable = NO;
  self.consoleView.layer.cornerRadius = 8;
  self.consoleView.translatesAutoresizingMaskIntoConstraints = NO;
  self.consoleView.text =
      [NSString stringWithFormat:@"> %@", TR(@"Script_Console_Ready")];
  [self.view addSubview:self.consoleView];

  [NSLayoutConstraint activateConstraints:@[
    
    [self.headerView.topAnchor constraintEqualToAnchor:g.topAnchor constant:12],
    [self.headerView.leadingAnchor constraintEqualToAnchor:g.leadingAnchor
                                                  constant:12],
    [self.headerView.trailingAnchor constraintEqualToAnchor:g.trailingAnchor
                                                   constant:-12],
    [self.headerView.heightAnchor constraintEqualToConstant:30],

    [self.infoLabel.centerYAnchor
        constraintEqualToAnchor:self.headerView.centerYAnchor],
    [self.infoLabel.leadingAnchor
        constraintEqualToAnchor:self.headerView.leadingAnchor],
    
    [self.infoLabel.trailingAnchor
        constraintLessThanOrEqualToAnchor:btnUndo.leadingAnchor
                                 constant:-10],

    [btnClear.centerYAnchor
        constraintEqualToAnchor:self.headerView.centerYAnchor],
    [btnClear.trailingAnchor
        constraintEqualToAnchor:self.headerView.trailingAnchor],
    [btnClear.widthAnchor constraintEqualToConstant:30],
    [btnClear.heightAnchor constraintEqualToConstant:30],

    [btnUndo.centerYAnchor
        constraintEqualToAnchor:self.headerView.centerYAnchor],
    [btnUndo.trailingAnchor constraintEqualToAnchor:btnClear.leadingAnchor
                                           constant:-8],
    [btnUndo.widthAnchor constraintEqualToConstant:30],
    [btnUndo.heightAnchor constraintEqualToConstant:30],

    [self.editorView.topAnchor
        constraintEqualToAnchor:self.headerView.bottomAnchor
                       constant:4],
    [self.editorView.leadingAnchor constraintEqualToAnchor:g.leadingAnchor
                                                  constant:12],
    [self.editorView.trailingAnchor constraintEqualToAnchor:g.trailingAnchor
                                                   constant:-12],
    [self.editorView.heightAnchor constraintEqualToAnchor:g.heightAnchor
                                               multiplier:0.45],

    [toolStack.topAnchor constraintEqualToAnchor:self.editorView.bottomAnchor
                                        constant:8],
    [toolStack.leadingAnchor constraintEqualToAnchor:g.leadingAnchor
                                            constant:12],
    [toolStack.trailingAnchor constraintEqualToAnchor:g.trailingAnchor
                                             constant:-12],
    [toolStack.heightAnchor constraintEqualToConstant:40],

    [self.consoleView.topAnchor constraintEqualToAnchor:toolStack.bottomAnchor
                                               constant:8],
    [self.consoleView.leadingAnchor constraintEqualToAnchor:g.leadingAnchor
                                                   constant:12],
    [self.consoleView.trailingAnchor constraintEqualToAnchor:g.trailingAnchor
                                                    constant:-12],
    [self.consoleView.bottomAnchor constraintEqualToAnchor:g.bottomAnchor
                                                  constant:-12],
  ]];
}

- (void)onShortcutAction {
  VMScriptShortcutViewController *vc =
      [[VMScriptShortcutViewController alloc] init];
  vc.didSelectShortcut = ^(NSString *_Nonnull code) {
    if (code.length > 0) {
      [self smartInsertCode:code];
    }
  };

  UINavigationController *nav =
      [[UINavigationController alloc] initWithRootViewController:vc];

  if (@available(iOS 15.0, *)) {
    if (nav.sheetPresentationController) {
      nav.sheetPresentationController.detents = @[
        [UISheetPresentationControllerDetent mediumDetent],
        [UISheetPresentationControllerDetent largeDetent]
      ];
      nav.sheetPresentationController.prefersGrabberVisible = YES;
    }
  }

  [self presentViewController:nav animated:YES completion:nil];
}

- (void)onExampleAction {
  VMScriptExampleViewController *vc =
      [[VMScriptExampleViewController alloc] init];
  vc.didSelectShortcut = ^(NSString *_Nonnull code) {
    if (code.length > 0) {
      [self smartInsertCode:code];
    }
  };
  UINavigationController *nav =
      [[UINavigationController alloc] initWithRootViewController:vc];

  if (@available(iOS 15.0, *)) {
    if (nav.sheetPresentationController) {
      nav.sheetPresentationController.detents = @[
        [UISheetPresentationControllerDetent mediumDetent],
        [UISheetPresentationControllerDetent largeDetent]
      ];
      nav.sheetPresentationController.prefersGrabberVisible = YES;
    }
  }

  [self presentViewController:nav animated:YES completion:nil];
}

- (void)runScript {
  [self.view endEditing:YES];
  NSString *code = self.editorView.text;

  if (code.length == 0)
    return;

  self.btnRun.enabled = NO;
  self.btnRun.alpha = 0.5;
  self.consoleView.text =
      [NSString stringWithFormat:@"> %@\n", TR(@"Script_Console_Running")];

  [[VMScriptManager shared] runScript:code
                           completion:^(NSString *log) {
                             self.consoleView.text = log;
                             self.btnRun.enabled = YES;
                             self.btnRun.alpha = 1.0;

                             if (log.length > 0) {
                               NSRange range = NSMakeRange(log.length - 1, 1);
                               [self.consoleView scrollRangeToVisible:range];
                             }
                           }];
}

- (void)saveScript {
  
  if (self.scriptModel.isImported) return;

  self.scriptModel.scriptContent = self.editorView.text;

  if ([self saveScriptModelToDisk]) {
    [self showToast:TR(@"Msg_Save_Success")];
  }
}

- (BOOL)saveScriptModelToDisk {
  NSString *doc = [NSSearchPathForDirectoriesInDomains(
      NSDocumentDirectory, NSUserDomainMask, YES) firstObject];

  NSString *bid = self.scriptModel.bundleID;
  if (!bid || bid.length == 0) {
    bid = [[VMMemoryEngine shared] currentBundleID] ?: TR(@"App_Unknown");
    self.scriptModel.bundleID = bid;
  }

  NSString *dir = [[doc stringByAppendingPathComponent:@"VansonMod/Script"]
      stringByAppendingPathComponent:bid];

  if (![[NSFileManager defaultManager] fileExistsAtPath:dir]) {
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
  }

  NSString *path =
      [dir stringByAppendingPathComponent:self.scriptModel.fileName];

  VMDataSession *s = [VMDataSession sessionWithData:@[ self.scriptModel ]
                                           bundleID:bid
                                           dataType:@"script"];

  return [[s toJSONData] writeToFile:path atomically:YES];
}

- (void)setupNavigationTitle {
  UIView *titleView = [[UIView alloc] init];

  UILabel *lbl = [[UILabel alloc] init];
  lbl.text = self.scriptModel.note ?: TR(@"Script_Title_Default");
  lbl.font = [UIFont boldSystemFontOfSize:17];
  lbl.textColor = [UIColor labelColor];
  lbl.translatesAutoresizingMaskIntoConstraints = NO;
  [titleView addSubview:lbl];
  objc_setAssociatedObject(self, "navTitleLabel", lbl,
                           OBJC_ASSOCIATION_RETAIN_NONATOMIC);

  UIImageView *icon = nil;
  if (!self.scriptModel.isImported) {
    icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"pencil"]];
    icon.tintColor = [UIColor systemBlueColor];
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    [titleView addSubview:icon];
  }

  if (icon) {
    [NSLayoutConstraint activateConstraints:@[
      [lbl.topAnchor constraintEqualToAnchor:titleView.topAnchor],
      [lbl.bottomAnchor constraintEqualToAnchor:titleView.bottomAnchor],
      [lbl.leadingAnchor constraintEqualToAnchor:titleView.leadingAnchor],
      [lbl.heightAnchor constraintEqualToConstant:44],
      [icon.leadingAnchor constraintEqualToAnchor:lbl.trailingAnchor constant:6],
      [icon.centerYAnchor constraintEqualToAnchor:lbl.centerYAnchor],
      [icon.trailingAnchor constraintEqualToAnchor:titleView.trailingAnchor],
      [icon.widthAnchor constraintEqualToConstant:16],
      [icon.heightAnchor constraintEqualToConstant:16]
    ]];
  } else {
    [NSLayoutConstraint activateConstraints:@[
      [lbl.topAnchor constraintEqualToAnchor:titleView.topAnchor],
      [lbl.bottomAnchor constraintEqualToAnchor:titleView.bottomAnchor],
      [lbl.leadingAnchor constraintEqualToAnchor:titleView.leadingAnchor],
      [lbl.trailingAnchor constraintEqualToAnchor:titleView.trailingAnchor],
      [lbl.heightAnchor constraintEqualToConstant:44]
    ]];
  }

  if (!self.scriptModel.isImported) {
    UITapGestureRecognizer *tap =
        [[UITapGestureRecognizer alloc] initWithTarget:self
                                                action:@selector(editNoteAction)];
    [titleView addGestureRecognizer:tap];
  }

  self.navigationItem.titleView = titleView;
}

- (void)updateNavigationTitle:(NSString *)title {
  UILabel *lbl = objc_getAssociatedObject(self, "navTitleLabel");
  if (lbl) {
    lbl.text = title;
    
    [self.navigationItem.titleView sizeToFit];
  }
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

#pragma mark - Keyboard

- (void)keyboardWillShow:(NSNotification *)notification {
  NSDictionary *info = [notification userInfo];
  CGRect keyboardFrame = [info[UIKeyboardFrameEndUserInfoKey] CGRectValue];
  CGFloat duration = [info[UIKeyboardAnimationDurationUserInfoKey] doubleValue];

  [UIView animateWithDuration:duration
                   animations:^{
                     self.bottomBar.transform =
                         CGAffineTransformMakeTranslation(
                             0, -keyboardFrame.size.height);
                   }];
}

- (void)keyboardWillHide:(NSNotification *)notification {
  NSDictionary *info = [notification userInfo];
  CGFloat duration = [info[UIKeyboardAnimationDurationUserInfoKey] doubleValue];

  [UIView animateWithDuration:duration
                   animations:^{
                     self.bottomBar.transform = CGAffineTransformIdentity;
                   }];
}

- (void)smartInsertCode:(NSString *)code {
  NSString *text = self.editorView.text ?: @"";
  NSRange selectedRange = self.editorView.selectedRange;
  NSUInteger cursorPos = selectedRange.location;
  
  NSMutableString *insertText = [NSMutableString string];
  
  BOOL needPrefixNewline = NO;
  if (cursorPos > 0 && cursorPos <= text.length) {
    unichar prevChar = [text characterAtIndex:cursorPos - 1];
    
    needPrefixNewline = (prevChar != '\n');
  }
  
  BOOL needSuffixNewline = NO;
  if (cursorPos < text.length) {
    unichar nextChar = [text characterAtIndex:cursorPos];
    
    needSuffixNewline = (nextChar != '\n');
  } else {
    
    needSuffixNewline = YES;
  }
  
  if (needPrefixNewline) {
    [insertText appendString:@"\n"];
  }
  [insertText appendString:code];
  if (needSuffixNewline) {
    [insertText appendString:@"\n"];
  }
  
  [self.editorView insertText:insertText];
}

#pragma mark - AI Actions

- (void)onAIAction {
    VMAIManager *ai = [VMAIManager shared];
    if (![ai isConfigured]) {
        [self showToast:@"AI not configured. Go to Settings → AI"];
        return;
    }

    NSString *selected = @"";
    NSRange selRange = self.editorView.selectedRange;
    if (selRange.length > 0) {
        selected = [self.editorView.text substringWithRange:selRange];
    }
    BOOL hasSelection = selected.length > 0;

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"✨ AI Assistant"
                         message:nil
                  preferredStyle:UIAlertControllerStyleActionSheet];

    if (hasSelection) {
        [alert addAction:[UIAlertAction actionWithTitle:@"Explain Code"
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *a) {
            [self aiExplain:selected];
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Fix / Improve"
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *a) {
            [self aiFix:selected];
        }]];
    }

    [alert addAction:[UIAlertAction actionWithTitle:@"Chat with AI"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *a) {
        [self showAIChatPanel];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Generate Script"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *a) {
        [self aiGenerateScript];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];

    if (alert.popoverPresentationController) {
        alert.popoverPresentationController.sourceView = self.view;
        alert.popoverPresentationController.sourceRect =
            CGRectMake(self.view.bounds.size.width / 2,
                       self.view.bounds.size.height - 100, 1, 1);
    }
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)aiExplain:(NSString *)code {
    NSString *prompt = [NSString stringWithFormat:
        @"Explain what this VansonMod script does:\n%@", code];
    [self showAIChatWithInitialPrompt:prompt];
}

- (void)aiFix:(NSString *)code {
    NSString *prompt = [NSString stringWithFormat:
        @"Fix and improve this VansonMod script. Return ONLY the fixed code, no explanation:\n%@",
        code];
    [self showAIChatWithInitialPrompt:prompt];
}

- (void)aiGenerateScript {
    NSString *prompt = @"Write a VansonMod JavaScript script. Available APIs: "
        @"vm.search(val, type, start, end), vm.refine(val, type, mode), "
        @"vm.getResults(count, skip), vm.getValue(addr, type), "
        @"vm.setValue(addr, val, type), vm.editAll(val, type, filter), "
        @"vm.log(msg), vm.ai.chat(prompt). ";
    [self showAIChatWithInitialPrompt:prompt];
}

- (void)showAIChatWithInitialPrompt:(NSString *)prompt {
    VMAIChatPanel *panel = [[VMAIChatPanel alloc] initWithPrompt:prompt];
    panel.didInsertCode = ^(NSString *code) {
        if (code.length > 0) {
            [self smartInsertCode:code];
        }
    };
    UINavigationController *nav =
        [[UINavigationController alloc] initWithRootViewController:panel];
    if (@available(iOS 15.0, *)) {
        if (nav.sheetPresentationController) {
            nav.sheetPresentationController.detents = @[
                [UISheetPresentationControllerDetent mediumDetent],
                [UISheetPresentationControllerDetent largeDetent]
            ];
            nav.sheetPresentationController.prefersGrabberVisible = YES;
        }
    }
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)showAIChatPanel {
    [self showAIChatWithInitialPrompt:nil];
}

@end

#pragma mark - VMAIChatPanel

@interface VMAIChatPanel : UIViewController <UITextFieldDelegate>
@property (nonatomic, copy) NSString *initialPrompt;
@property (nonatomic, copy) void (^didInsertCode)(NSString *code);
@end

@implementation VMAIChatPanel {
    UITextView *_chatView;
    UITextField *_inputField;
    UIButton *_sendBtn;
    UIBarButtonItem *_insertBtn;
    NSMutableString *_lastResponse;
    BOOL _isStreaming;
}

- (instancetype)initWithPrompt:(NSString *)prompt {
    if (self = [super init]) {
        _initialPrompt = [prompt copy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"✨ AI Chat";
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                     target:self
                                                     action:@selector(dismiss)];

    _insertBtn = [[UIBarButtonItem alloc] initWithTitle:@"Insert"
                                                  style:UIBarButtonItemStyleDone
                                                 target:self
                                                 action:@selector(insertCode)];
    self.navigationItem.rightBarButtonItem = _insertBtn;
    _insertBtn.enabled = NO;

    // Chat history view
    _chatView = [[UITextView alloc] init];
    _chatView.editable = NO;
    _chatView.font = [UIFont systemFontOfSize:15];
    _chatView.backgroundColor = [UIColor secondarySystemBackgroundColor];
    _chatView.layer.cornerRadius = 12;
    _chatView.translatesAutoresizingMaskIntoConstraints = NO;
    _chatView.textContainerInset = UIEdgeInsetsMake(12, 12, 12, 12);
    [self.view addSubview:_chatView];

    // Input bar
    UIView *inputBar = [[UIView alloc] init];
    inputBar.backgroundColor = [UIColor tertiarySystemBackgroundColor];
    inputBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:inputBar];

    _inputField = [[UITextField alloc] init];
    _inputField.placeholder = @"Ask AI anything...";
    _inputField.borderStyle = UITextBorderStyleRoundedRect;
    _inputField.returnKeyType = UIReturnKeySend;
    _inputField.delegate = self;
    _inputField.translatesAutoresizingMaskIntoConstraints = NO;
    [inputBar addSubview:_inputField];

    _sendBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [_sendBtn setTitle:@"Send" forState:UIControlStateNormal];
    [_sendBtn setTitleColor:[UIColor systemBlueColor] forState:UIControlStateNormal];
    [_sendBtn addTarget:self action:@selector(sendMessage) forControlEvents:UIControlEventTouchUpInside];
    _sendBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [inputBar addSubview:_sendBtn];

    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [_chatView.topAnchor constraintEqualToAnchor:g.topAnchor constant:8],
        [_chatView.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:12],
        [_chatView.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-12],
        [_chatView.bottomAnchor constraintEqualToAnchor:inputBar.topAnchor constant:-8],

        [inputBar.leadingAnchor constraintEqualToAnchor:g.leadingAnchor],
        [inputBar.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],
        [inputBar.bottomAnchor constraintEqualToAnchor:g.bottomAnchor],
        [inputBar.heightAnchor constraintEqualToConstant:50],

        [_inputField.leadingAnchor constraintEqualToAnchor:inputBar.leadingAnchor constant:12],
        [_inputField.centerYAnchor constraintEqualToAnchor:inputBar.centerYAnchor],
        [_inputField.trailingAnchor constraintEqualToAnchor:_sendBtn.leadingAnchor constant:-8],

        [_sendBtn.trailingAnchor constraintEqualToAnchor:inputBar.trailingAnchor constant:-12],
        [_sendBtn.centerYAnchor constraintEqualToAnchor:inputBar.centerYAnchor],
        [_sendBtn.widthAnchor constraintEqualToConstant:50],
    ]];

    if (_initialPrompt.length > 0) {
        _inputField.text = _initialPrompt;
        [self sendMessage];
    }
}

- (void)dismiss {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)insertCode {
    if (_lastResponse.length > 0 && self.didInsertCode) {
        // Extract code blocks from response
        NSString *code = [self extractCodeFromMarkdown:_lastResponse];
        self.didInsertCode(code.length > 0 ? code : _lastResponse);
    }
    [self dismiss];
}

- (NSString *)extractCodeFromMarkdown:(NSString *)text {
    // Extract content between ``` markers
    NSRange start = [text rangeOfString:@"```"];
    if (start.location == NSNotFound) return text;
    NSRange end = [text rangeOfString:@"```"
                              options:0
                                range:NSMakeRange(start.location + 3,
                                                  text.length - start.location - 3)];
    if (end.location == NSNotFound) return text;

    NSUInteger codeStart = start.location + 3;
    // Skip language identifier on first line
    NSRange firstLine = [text rangeOfString:@"\n"
                                    options:0
                                      range:NSMakeRange(codeStart, end.location - codeStart)];
    if (firstLine.location != NSNotFound) {
        codeStart = firstLine.location + 1;
    }
    return [text substringWithRange:NSMakeRange(codeStart, end.location - codeStart)];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [self sendMessage];
    return YES;
}

- (void)sendMessage {
    NSString *msg = _inputField.text;
    if (msg.length == 0 || _isStreaming) return;

    _isStreaming = YES;
    _sendBtn.enabled = NO;
    _lastResponse = [NSMutableString string];

    // Append user message
    NSMutableAttributedString *attr =
        [[NSMutableAttributedString alloc] initWithAttributedString:_chatView.attributedText];
    if (attr.length > 0) {
        [attr appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n\n"]];
    }
    [attr appendAttributedString:[[NSAttributedString alloc]
        initWithString:[NSString stringWithFormat:@"👤 %@\n\n", msg]
            attributes:@{NSFontAttributeName: [UIFont boldSystemFontOfSize:15]}]];
    [attr appendAttributedString:[[NSAttributedString alloc]
        initWithString:@"🤖 "
            attributes:@{NSFontAttributeName: [UIFont boldSystemFontOfSize:15]}]];
    _chatView.attributedText = attr;
    _inputField.text = @"";

    [[VMAIManager shared] chatStream:msg
                          completion:^(NSString *chunk, NSString *fullText, NSError *error) {
        if (error) {
            self->_isStreaming = NO;
            self->_sendBtn.enabled = YES;
            NSMutableAttributedString *a =
                [[NSMutableAttributedString alloc] initWithAttributedString:self->_chatView.attributedText];
            [a appendAttributedString:[[NSAttributedString alloc]
                initWithString:[NSString stringWithFormat:@"\n[Error] %@",
                                  error.localizedDescription]
                    attributes:@{NSForegroundColorAttributeName: [UIColor systemRedColor]}]];
            self->_chatView.attributedText = a;
            return;
        }
        if (fullText) {
            [self->_lastResponse setString:fullText];
            // Rebuild full display
            NSMutableAttributedString *display =
                [[NSMutableAttributedString alloc] init];
            // Find the last user message position in the text
            NSString *existing = self->_chatView.attributedText.string;
            NSRange botRange = [existing rangeOfString:@"🤖 "
                                               options:NSBackwardsSearch];
            if (botRange.location != NSNotFound) {
                NSString *prefix = [existing substringToIndex:
                    botRange.location + botRange.length];
                [display appendAttributedString:[[NSAttributedString alloc]
                    initWithString:prefix
                        attributes:@{NSFontAttributeName: [UIFont boldSystemFontOfSize:15]}]];
            }
            [display appendAttributedString:[[NSAttributedString alloc]
                initWithString:fullText
                    attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:15]}]];
            self->_chatView.attributedText = display;

            // Scroll to bottom
            if (display.length > 0) {
                [self->_chatView scrollRangeToVisible:NSMakeRange(display.length - 1, 1)];
            }

            self->_insertBtn.enabled = YES;
        }
        if (chunk == nil && error == nil) {
            // Stream complete
            self->_isStreaming = NO;
            self->_sendBtn.enabled = YES;
            NSMutableAttributedString *a =
                [[NSMutableAttributedString alloc] initWithAttributedString:self->_chatView.attributedText];
            [a appendAttributedString:[[NSAttributedString alloc]
                initWithString:@"\n\n"]];
            self->_chatView.attributedText = a;
        }
    }];
}

@end
