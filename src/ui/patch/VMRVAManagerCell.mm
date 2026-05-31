#import "../patch/VMRVAManagerCell.h"
#import "include/VMLocalization.h"
#import "include/VMRVAPatch.h"
#define kCardCornerRadius 16.0
#define kButtonHeight 34.0
#define TR(key) ([[VMLocalization shared] localizedString:key])
@interface VMRVAManagerCell ()
@property(nonatomic, strong) UIView *cardContainer;
@property(nonatomic, strong) UIView *statusIndicator;
@property(nonatomic, strong) UILabel *titleLabel;
@property(nonatomic, strong) UILabel *authorLabel;
@property(nonatomic, strong) UILabel *appInfoLabel;
@property(nonatomic, strong) UILabel *metaLabel;
@property(nonatomic, strong) UILabel *hexDisplayLabel;
@property(nonatomic, strong) UILabel *origHexLabel;
@property(nonatomic, strong) UIButton *btnEdit;
@property(nonatomic, strong) UIButton *btnToggle;
@property(nonatomic, assign) BOOL isActive;
@end
@implementation VMRVAManagerCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(NSString *)reuseIdentifier {
  if (self = [super initWithStyle:style reuseIdentifier:reuseIdentifier]) {
    self.backgroundColor = [UIColor clearColor];
    self.selectionStyle = UITableViewCellSelectionStyleDefault;

    UIView *cv = [UIView new];
    cv.backgroundColor = [UIColor clearColor];
    self.selectedBackgroundView = cv;

    [self setupUI];
  }
  return self;
}

- (void)setEditing:(BOOL)editing animated:(BOOL)animated {
  [super setEditing:editing animated:animated];
  self.selectionStyle = editing ? UITableViewCellSelectionStyleDefault
                                : UITableViewCellSelectionStyleNone;
}

- (void)setupUI {
  _cardContainer = [[UIView alloc] init];
  _cardContainer.backgroundColor =
      [UIColor secondarySystemGroupedBackgroundColor];
  _cardContainer.layer.cornerRadius = kCardCornerRadius;
  _cardContainer.layer.borderWidth = 1.0;
  _cardContainer.layer.borderColor = [UIColor clearColor].CGColor;
  _cardContainer.translatesAutoresizingMaskIntoConstraints = NO;
  [self.contentView addSubview:_cardContainer];

  _titleLabel = [[UILabel alloc] init];
  _titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightBold];
  _titleLabel.textColor = [UIColor labelColor];
  _titleLabel.numberOfLines = 0;
  _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
  [_cardContainer addSubview:_titleLabel];

  _authorLabel = [[UILabel alloc] init];
  _authorLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
  _authorLabel.textColor = [UIColor secondaryLabelColor];
  _authorLabel.textAlignment = NSTextAlignmentRight;
  _authorLabel.translatesAutoresizingMaskIntoConstraints = NO;
  [_authorLabel
      setContentCompressionResistancePriority:UILayoutPriorityRequired
                                      forAxis:UILayoutConstraintAxisHorizontal];
  [_cardContainer addSubview:_authorLabel];

  _statusIndicator = [[UIView alloc] init];
  _statusIndicator.backgroundColor = [UIColor systemGray4Color];
  _statusIndicator.layer.cornerRadius = 4;
  _statusIndicator.translatesAutoresizingMaskIntoConstraints = NO;
  [_cardContainer addSubview:_statusIndicator];

  _metaLabel = [[UILabel alloc] init];
  _metaLabel.font = [UIFont fontWithName:@"Menlo" size:11];
  _metaLabel.textColor = [UIColor secondaryLabelColor];
  _metaLabel.numberOfLines = 0;
  _metaLabel.lineBreakMode = NSLineBreakByCharWrapping;
  _metaLabel.translatesAutoresizingMaskIntoConstraints = NO;
  [_cardContainer addSubview:_metaLabel];

  _appInfoLabel = [[UILabel alloc] init];
  _appInfoLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
  _appInfoLabel.textColor = [UIColor tertiaryLabelColor];
  _appInfoLabel.numberOfLines = 0;
  _appInfoLabel.translatesAutoresizingMaskIntoConstraints = NO;
  [_cardContainer addSubview:_appInfoLabel];

  UIView *line = [[UIView alloc] init];
  line.backgroundColor = [UIColor separatorColor];
  line.alpha = 0.5;
  line.translatesAutoresizingMaskIntoConstraints = NO;
  [_cardContainer addSubview:line];

  UILabel *hexTitle = [self createTagLabel:@"ON:"
                                     color:[UIColor systemGreenColor]];
  [_cardContainer addSubview:hexTitle];

  _hexDisplayLabel = [self createHexLabel];
  [_hexDisplayLabel
      setContentCompressionResistancePriority:UILayoutPriorityDefaultHigh
                                      forAxis:UILayoutConstraintAxisHorizontal];
  [_cardContainer addSubview:_hexDisplayLabel];

  UILabel *origTitle = [self createTagLabel:@"OFF:"
                                      color:[UIColor systemRedColor]];
  [_cardContainer addSubview:origTitle];

  _origHexLabel = [self createHexLabel];
  [_origHexLabel
      setContentCompressionResistancePriority:UILayoutPriorityDefaultHigh
                                      forAxis:UILayoutConstraintAxisHorizontal];
  [_cardContainer addSubview:_origHexLabel];

  UIStackView *btnStack = [[UIStackView alloc] init];
  btnStack.axis = UILayoutConstraintAxisHorizontal;
  btnStack.spacing = 10;
  btnStack.distribution = UIStackViewDistributionFillEqually;
  btnStack.translatesAutoresizingMaskIntoConstraints = NO;
  [_cardContainer addSubview:btnStack];

  _btnEdit = [self createButton:TR(@"Common_Edit")
                          color:[UIColor systemGrayColor]
                         filled:NO];
  [_btnEdit addTarget:self
                action:@selector(onEditTap)
      forControlEvents:UIControlEventTouchUpInside];

  _btnToggle = [self createButton:TR(@"Btn_Inject")
                            color:[UIColor systemBlueColor]
                           filled:YES];
  [_btnToggle addTarget:self
                 action:@selector(onToggleTap)
       forControlEvents:UIControlEventTouchUpInside];

  [btnStack addArrangedSubview:_btnEdit];
  [btnStack addArrangedSubview:_btnToggle];

  CGFloat p = 14.0;

  [NSLayoutConstraint activateConstraints:@[
    [_cardContainer.topAnchor constraintEqualToAnchor:self.contentView.topAnchor
                                             constant:6],
    [_cardContainer.bottomAnchor
        constraintEqualToAnchor:self.contentView.bottomAnchor
                       constant:-6],
    [_cardContainer.leadingAnchor
        constraintEqualToAnchor:self.contentView.leadingAnchor
                       constant:12],
    [_cardContainer.trailingAnchor
        constraintEqualToAnchor:self.contentView.trailingAnchor
                       constant:-12],

    [_titleLabel.topAnchor constraintEqualToAnchor:_cardContainer.topAnchor
                                          constant:p],
    [_titleLabel.leadingAnchor
        constraintEqualToAnchor:_cardContainer.leadingAnchor
                       constant:p],
    [_titleLabel.trailingAnchor
        constraintLessThanOrEqualToAnchor:_authorLabel.leadingAnchor
                                 constant:-8],

    [_authorLabel.centerYAnchor
        constraintEqualToAnchor:_titleLabel.firstBaselineAnchor],
    [_authorLabel.trailingAnchor
        constraintEqualToAnchor:_statusIndicator.leadingAnchor
                       constant:-8],

    [_statusIndicator.centerYAnchor
        constraintEqualToAnchor:_authorLabel.centerYAnchor],
    [_statusIndicator.trailingAnchor
        constraintEqualToAnchor:_cardContainer.trailingAnchor
                       constant:-p],
    [_statusIndicator.widthAnchor constraintEqualToConstant:8],
    [_statusIndicator.heightAnchor constraintEqualToConstant:8],

    [_metaLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor
                                         constant:4],
    [_metaLabel.leadingAnchor
        constraintEqualToAnchor:_cardContainer.leadingAnchor
                       constant:p],
    [_metaLabel.trailingAnchor
        constraintEqualToAnchor:_cardContainer.trailingAnchor
                       constant:-p],

    [_appInfoLabel.topAnchor constraintEqualToAnchor:_metaLabel.bottomAnchor
                                            constant:2],
    [_appInfoLabel.leadingAnchor
        constraintEqualToAnchor:_cardContainer.leadingAnchor
                       constant:p],
    [_appInfoLabel.trailingAnchor
        constraintEqualToAnchor:_cardContainer.trailingAnchor
                       constant:-p],

    [line.topAnchor constraintEqualToAnchor:_appInfoLabel.bottomAnchor
                                   constant:10],
    [line.leadingAnchor constraintEqualToAnchor:_cardContainer.leadingAnchor
                                       constant:p],
    [line.trailingAnchor constraintEqualToAnchor:_cardContainer.trailingAnchor
                                        constant:-p],
    [line.heightAnchor constraintEqualToConstant:0.5],

    [hexTitle.topAnchor constraintEqualToAnchor:line.bottomAnchor constant:12],
    [hexTitle.leadingAnchor constraintEqualToAnchor:_cardContainer.leadingAnchor
                                           constant:p],
    [hexTitle.widthAnchor constraintEqualToConstant:35],

    [_hexDisplayLabel.topAnchor constraintEqualToAnchor:hexTitle.topAnchor],
    [_hexDisplayLabel.leadingAnchor
        constraintEqualToAnchor:hexTitle.trailingAnchor
                       constant:6],
    [_hexDisplayLabel.trailingAnchor
        constraintEqualToAnchor:_cardContainer.trailingAnchor
                       constant:-p],

    [origTitle.topAnchor
        constraintGreaterThanOrEqualToAnchor:_hexDisplayLabel.bottomAnchor
                                    constant:8],
    [origTitle.leadingAnchor
        constraintEqualToAnchor:_cardContainer.leadingAnchor
                       constant:p],
    [origTitle.widthAnchor constraintEqualToConstant:35],

    [_origHexLabel.topAnchor constraintEqualToAnchor:origTitle.topAnchor],
    [_origHexLabel.leadingAnchor
        constraintEqualToAnchor:origTitle.trailingAnchor
                       constant:6],
    [_origHexLabel.trailingAnchor
        constraintEqualToAnchor:_cardContainer.trailingAnchor
                       constant:-p],

    [btnStack.topAnchor
        constraintGreaterThanOrEqualToAnchor:_origHexLabel.bottomAnchor
                                    constant:16],
    [btnStack.leadingAnchor constraintEqualToAnchor:_cardContainer.leadingAnchor
                                           constant:p],
    [btnStack.trailingAnchor
        constraintEqualToAnchor:_cardContainer.trailingAnchor
                       constant:-p],
    [btnStack.heightAnchor constraintEqualToConstant:kButtonHeight],
    [btnStack.bottomAnchor constraintEqualToAnchor:_cardContainer.bottomAnchor
                                          constant:-p]
  ]];
}

- (UIButton *)createButton:(NSString *)title
                     color:(UIColor *)color
                    filled:(BOOL)filled {
  UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
  if (@available(iOS 15.0, *)) {
    UIButtonConfiguration *conf =
        filled ? [UIButtonConfiguration filledButtonConfiguration]
               : [UIButtonConfiguration grayButtonConfiguration];
    conf.baseBackgroundColor = filled ? color : [UIColor systemGray6Color];
    conf.baseForegroundColor =
        filled ? [UIColor whiteColor] : [UIColor labelColor];
    conf.cornerStyle = UIButtonConfigurationCornerStyleMedium;
    NSDictionary *attrs = @{
      NSFontAttributeName : [UIFont systemFontOfSize:13 weight:UIFontWeightBold]
    };
    conf.attributedTitle = [[NSAttributedString alloc] initWithString:title
                                                           attributes:attrs];
    btn.configuration = conf;
  } else {
    [btn setTitle:title forState:UIControlStateNormal];
    btn.backgroundColor = filled ? color : [UIColor systemGray6Color];
    btn.tintColor = filled ? [UIColor whiteColor] : [UIColor labelColor];
    btn.layer.cornerRadius = 8;
    btn.titleLabel.font = [UIFont boldSystemFontOfSize:13];
  }
  return btn;
}

- (UILabel *)createTagLabel:(NSString *)text color:(UIColor *)color {
  UILabel *l = [UILabel new];
  l.text = text;
  l.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
  l.textColor = color;
  l.translatesAutoresizingMaskIntoConstraints = NO;
  return l;
}

- (UILabel *)createHexLabel {
  UILabel *l = [UILabel new];
  l.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightBold];
  l.textColor = [UIColor labelColor];
  l.textAlignment = NSTextAlignmentLeft;
  l.numberOfLines = 0;
  l.lineBreakMode = NSLineBreakByCharWrapping;
  l.adjustsFontSizeToFitWidth = YES;
  l.minimumScaleFactor = 0.7;
  l.translatesAutoresizingMaskIntoConstraints = NO;
  return l;
}

- (void)configureWithPatch:(VMRVAPatch *)patch {
  self.titleLabel.text = (patch.note && patch.note.length > 0)
                             ? patch.note
                             : TR(@"Default_Patch_Note");
  self.authorLabel.text =
      [NSString stringWithFormat:@"@%@", patch.author ?: TR(@"Lab_Me_Default")];

  NSMutableArray *appInfoParts = [NSMutableArray array];
  if (patch.appName && patch.appName.length > 0) {
    [appInfoParts addObject:patch.appName];
  }
  if (patch.appVersion && patch.appVersion.length > 0) {
    [appInfoParts
        addObject:[NSString stringWithFormat:@"v%@", patch.appVersion]];
  }
  if (patch.createdAt > 0) {
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:patch.createdAt];
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    [fmt setDateFormat:@"yy/MM/dd"];
    [appInfoParts addObject:[fmt stringFromDate:date]];
  }

  NSString *modInfo = [NSString
      stringWithFormat:@"%@ + 0x%llX", patch.moduleName, patch.offset];

  BOOL titleContainsMod =
      [self.titleLabel.text containsString:patch.moduleName];

  if (titleContainsMod) {
    
    self.metaLabel.text = [appInfoParts componentsJoinedByString:@" • "];
    
    self.appInfoLabel.text = @"";
  } else {
    
    self.metaLabel.text = modInfo;
    
    self.appInfoLabel.text = [appInfoParts componentsJoinedByString:@" • "];
  }

  self.hexDisplayLabel.text = patch.patchHex;
  self.origHexLabel.text = patch.originalHex;

  if (patch.isImported) {
    
    _cardContainer.layer.borderWidth = 1.0;
    _cardContainer.layer.borderColor = [UIColor systemGray4Color].CGColor;
  } else {
    
    _cardContainer.layer.borderWidth = 0;
  }
  
  _btnEdit.enabled = YES;
  _btnEdit.alpha = 1.0;

  [self updateStateVisuals:patch.isOn animated:NO];
}

- (void)updateStateVisuals:(BOOL)isActive animated:(BOOL)animated {
  self.isActive = isActive;

  void (^updates)(void) = ^{
    if (isActive) {
      UIColor *activeColor = [UIColor systemRedColor];

      self.cardContainer.layer.borderColor = activeColor.CGColor;
      self.cardContainer.backgroundColor =
          [activeColor colorWithAlphaComponent:0.08];
      self.statusIndicator.backgroundColor = activeColor;

      self.hexDisplayLabel.textColor = [UIColor systemRedColor];
      self.hexDisplayLabel.font =
          [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightBold];

      self.origHexLabel.textColor = [UIColor tertiaryLabelColor];
      self.origHexLabel.font =
          [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];

      [self updateButton:_btnToggle
                   title:TR(@"Btn_Restore")
                   color:[UIColor systemGreenColor]
                  filled:YES];

    } else {
      UIColor *restoreColor = [UIColor systemGreenColor];

      self.cardContainer.layer.borderColor = restoreColor.CGColor;
      self.cardContainer.backgroundColor =
          [restoreColor colorWithAlphaComponent:0.08];
      self.statusIndicator.backgroundColor = restoreColor;

      self.hexDisplayLabel.textColor = [UIColor secondaryLabelColor];
      self.hexDisplayLabel.font =
          [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];

      self.origHexLabel.textColor = restoreColor;
      self.origHexLabel.font =
          [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightBold];

      [self updateButton:_btnToggle
                   title:TR(@"Btn_Inject")
                   color:[UIColor systemGreenColor]
                  filled:YES];
    }
  };

  if (animated) {
    [UIView animateWithDuration:0.25
                          delay:0
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:updates
                     completion:nil];
  } else {
    updates();
  }
}

- (void)updateButton:(UIButton *)btn
               title:(NSString *)title
               color:(UIColor *)color
              filled:(BOOL)filled {
  if (@available(iOS 15.0, *)) {
    UIButtonConfiguration *conf = btn.configuration;
    conf.baseBackgroundColor = filled ? color : [UIColor systemGray6Color];
    conf.baseForegroundColor =
        filled ? [UIColor whiteColor] : [UIColor labelColor];

    NSDictionary *attrs = @{
      NSFontAttributeName : [UIFont systemFontOfSize:13 weight:UIFontWeightBold]
    };
    conf.attributedTitle = [[NSAttributedString alloc] initWithString:title
                                                           attributes:attrs];
    btn.configuration = conf;
  } else {
    [btn setTitle:title forState:UIControlStateNormal];
    btn.backgroundColor = filled ? color : [UIColor systemGray6Color];
    btn.tintColor = filled ? [UIColor whiteColor] : [UIColor labelColor];
  }
}

- (void)onEditTap {
  if ([self.delegate respondsToSelector:@selector(didClickRVAEdit:)])
    [self.delegate didClickRVAEdit:self];
}
- (void)onToggleTap {
  if ([self.delegate respondsToSelector:@selector(didClickRVAToggle:)])
    [self.delegate didClickRVAToggle:self];
}
@end
