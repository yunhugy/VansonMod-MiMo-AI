#import "VMHexRowEditorViewController.h"
#import "../../utils/helpers/VMUIHelper.h"
#import "include/VMLocalization.h"
#import "include/VMMemoryEngine.h"
#define TR(key) ([[VMLocalization shared] localizedString:key])
@interface VMHexRowEditorViewController () <UITextViewDelegate>
@property(nonatomic, strong) UITextView *hexTextView;
@property(nonatomic, strong) UITextView *asciiTextView;
@property(nonatomic, strong) UILabel *addressDisplayLabel;
@property(nonatomic, strong) UILabel *hexLabel;
@property(nonatomic, strong) UILabel *asciiLabel;

@property(nonatomic, strong) UIScrollView *scrollView;
@end
@implementation VMHexRowEditorViewController
- (void)viewDidLoad {
  [super viewDidLoad];
  self.title = TR(@"Hex_Row_Editor");
  self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];

  self.navigationItem.rightBarButtonItem =
      [[UIBarButtonItem alloc] initWithTitle:TR(@"Hex_Save")
                                       style:UIBarButtonItemStyleDone
                                      target:self
                                      action:@selector(save)];

  [self setupUI];
  [self populateData];

  [VMUIHelper addFixedFooterTo:self forTableView:nil];

  UIEdgeInsets inset = self.scrollView.contentInset;
  inset.bottom += 30;
  self.scrollView.contentInset = inset;
  self.scrollView.scrollIndicatorInsets = inset;
}

- (void)setupUI {
  self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];

  self.scrollView = [[UIScrollView alloc] init];
  self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
  self.scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
  [self.view addSubview:self.scrollView];

  UIStackView *stackView = [[UIStackView alloc] init];
  stackView.axis = UILayoutConstraintAxisVertical;
  stackView.spacing = 15;
  stackView.alignment = UIStackViewAlignmentFill;
  stackView.distribution = UIStackViewDistributionFill;
  stackView.translatesAutoresizingMaskIntoConstraints = NO;
  [self.scrollView addSubview:stackView];

  UILayoutGuide *g = self.view.safeAreaLayoutGuide;

  [NSLayoutConstraint activateConstraints:@[
    [self.scrollView.topAnchor constraintEqualToAnchor:g.topAnchor],
    [self.scrollView.bottomAnchor constraintEqualToAnchor:g.bottomAnchor],
    [self.scrollView.leadingAnchor constraintEqualToAnchor:g.leadingAnchor],
    [self.scrollView.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],

    [stackView.topAnchor
        constraintEqualToAnchor:self.scrollView.contentLayoutGuide.topAnchor
                       constant:20],
    [stackView.bottomAnchor
        constraintEqualToAnchor:self.scrollView.contentLayoutGuide.bottomAnchor
                       constant:-20],
    [stackView.leadingAnchor
        constraintEqualToAnchor:self.scrollView.contentLayoutGuide.leadingAnchor
                       constant:15],
    [stackView.trailingAnchor
        constraintEqualToAnchor:self.scrollView.contentLayoutGuide.trailingAnchor
                       constant:-15],

    [stackView.widthAnchor
        constraintEqualToAnchor:self.scrollView.frameLayoutGuide.widthAnchor
                       constant:-30]
  ]];

  self.addressDisplayLabel = [[UILabel alloc] init];
  self.addressDisplayLabel.textAlignment = NSTextAlignmentCenter;
  self.addressDisplayLabel.font =
      [UIFont monospacedSystemFontOfSize:18 weight:UIFontWeightBold];
  self.addressDisplayLabel.textColor = [UIColor labelColor];
  self.addressDisplayLabel.text =
      [NSString stringWithFormat:TR(@"Status_Editing_Addr"), self.address];
  [stackView addArrangedSubview:self.addressDisplayLabel];

  self.hexLabel = [[UILabel alloc] init];
  self.hexLabel.text = TR(@"Hex_Header_Edit");
  self.hexLabel.font = [UIFont boldSystemFontOfSize:14];
  self.hexLabel.textColor = [UIColor systemGrayColor];
  [stackView addArrangedSubview:self.hexLabel];

  self.hexTextView = [[UITextView alloc] init];
  self.hexTextView.font =
      [UIFont monospacedSystemFontOfSize:18 weight:UIFontWeightRegular];
  self.hexTextView.layer.cornerRadius = 8;
  self.hexTextView.backgroundColor =
      [UIColor secondarySystemGroupedBackgroundColor];
  self.hexTextView.delegate = self;
  self.hexTextView.keyboardType = UIKeyboardTypeASCIICapable;
  self.hexTextView.autocapitalizationType =
      UITextAutocapitalizationTypeAllCharacters;
  [self.hexTextView.heightAnchor constraintEqualToConstant:100].active = YES;
  [stackView addArrangedSubview:self.hexTextView];

  self.asciiLabel = [[UILabel alloc] init];
  self.asciiLabel.text = TR(@"Hex_Header_Ascii");
  self.asciiLabel.font = [UIFont boldSystemFontOfSize:14];
  self.asciiLabel.textColor = [UIColor systemGrayColor];
  [stackView addArrangedSubview:self.asciiLabel];

  self.asciiTextView = [[UITextView alloc] init];
  self.asciiTextView.font =
      [UIFont monospacedSystemFontOfSize:18 weight:UIFontWeightRegular];
  self.asciiTextView.layer.cornerRadius = 8;
  self.asciiTextView.backgroundColor =
      [UIColor secondarySystemGroupedBackgroundColor];
  self.asciiTextView.editable = NO;
  self.asciiTextView.textColor = [UIColor systemBlueColor];
  [self.asciiTextView.heightAnchor constraintEqualToConstant:100].active = YES;
  [stackView addArrangedSubview:self.asciiTextView];

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

- (void)populateData {
  if (!self.originalData)
    return;
  NSMutableString *hexStr = [NSMutableString string];
  const uint8_t *bytes = (const uint8_t *)self.originalData.bytes;
  for (int i = 0; i < self.originalData.length; i++) {
    [hexStr appendFormat:@"%02X ", bytes[i]];
  }
  self.hexTextView.text = hexStr;
  [self updateASCII];
}

- (void)textViewDidChange:(UITextView *)textView {
  if (textView == self.hexTextView) {
    [self updateASCII];
  }
}

- (void)updateASCII {
  NSString *cleanHex = [[self.hexTextView.text
      componentsSeparatedByCharactersInSet:
          [[NSCharacterSet
              characterSetWithCharactersInString:@"0123456789ABCDEFabcdef"]
              invertedSet]] componentsJoinedByString:@""];
  NSData *data = [[VMMemoryEngine shared] dataFromHexString:cleanHex];

  NSMutableString *ascStr = [NSMutableString string];
  const uint8_t *bytes = (const uint8_t *)data.bytes;
  for (int i = 0; i < data.length; i++) {
    uint8_t b = bytes[i];
    if (b >= 0x20 && b <= 0x7E)
      [ascStr appendFormat:@"%c", b];
    else
      [ascStr appendString:@"."];
  }
  self.asciiTextView.text = ascStr;
}

- (void)save {
  NSString *cleanHex = [[self.hexTextView.text
      componentsSeparatedByCharactersInSet:
          [[NSCharacterSet
              characterSetWithCharactersInString:@"0123456789ABCDEFabcdef"]
              invertedSet]] componentsJoinedByString:@""];

  NSUInteger expectedLength = self.originalData.length * 2;
  if (cleanHex.length != expectedLength) {
    NSString *errMsg = [NSString
        stringWithFormat:TR(@"Hex_Err_Len_Msg"), (unsigned long)expectedLength,
                         (unsigned long)cleanHex.length];
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:TR(@"Hex_Err_Len_Title")
                         message:errMsg
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:TR(@"Btn_OK")
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
    return;
  }

  NSData *newData = [[VMMemoryEngine shared] dataFromHexString:cleanHex];
  if (self.delegate && [self.delegate respondsToSelector:@selector
                                      (rowEditorDidSaveData:atAddress:)]) {
    [self.delegate rowEditorDidSaveData:newData atAddress:self.address];
  }
  [self.navigationController popViewControllerAnimated:YES];
}

- (void)keyboardWillShow:(NSNotification *)notification {
  NSDictionary *info = [notification userInfo];
  CGSize kbSize =
      [[info objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue].size;

  if (self.scrollView) {
    UIEdgeInsets contentInsets = UIEdgeInsetsMake(0.0, 0.0, kbSize.height, 0.0);
    self.scrollView.contentInset = contentInsets;
    self.scrollView.scrollIndicatorInsets = contentInsets;
  }
}

- (void)keyboardWillHide:(NSNotification *)notification {
  if (self.scrollView) {
    
    UIEdgeInsets inset = UIEdgeInsetsMake(0.0, 0.0, 30.0, 0.0);
    self.scrollView.contentInset = inset;
    self.scrollView.scrollIndicatorInsets = inset;
  }
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
