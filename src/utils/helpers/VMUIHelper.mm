#import "VMUIHelper.h"
#import "include/VMIconHelper.h"
@implementation VMUIHelper
+ (UIButton *)createButtonWithTitle:(NSString *)title color:(UIColor *)color target:(id)target action:(SEL)action {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    
    [btn addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    
    if (@available(iOS 15.0, *)) {
        UIButtonConfiguration *conf = [UIButtonConfiguration filledButtonConfiguration];
        conf.baseBackgroundColor = color;
        conf.baseForegroundColor = [UIColor whiteColor];
        conf.cornerStyle = UIButtonConfigurationCornerStyleMedium;
        
        UIFont *font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
        conf.attributedTitle = [[NSAttributedString alloc] initWithString:title attributes:@{NSFontAttributeName: font}];
        
        btn.configuration = conf;
    } else {
        [btn setTitle:title forState:UIControlStateNormal];
        [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        [btn setBackgroundColor:color];
        
        btn.layer.cornerRadius = 8;
        btn.layer.masksToBounds = YES;
        btn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
        
        btn.contentEdgeInsets = UIEdgeInsetsMake(8, 12, 8, 12);
    }
    
    return btn;
}

+ (UIButton *)createIconButton:(NSString *)iconName color:(UIColor *)color target:(id)target action:(SEL)action {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    [btn addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    
    UIImage *icon = [VMIconHelper compatibleSystemImageNamed:iconName];
    
    if (@available(iOS 15.0, *)) {
        UIButtonConfiguration *conf = [UIButtonConfiguration grayButtonConfiguration];
        conf.baseForegroundColor = color;
        conf.baseBackgroundColor = [color colorWithAlphaComponent:0.1];
        conf.image = icon;
        conf.cornerStyle = UIButtonConfigurationCornerStyleMedium;
        btn.configuration = conf;
    } else {
        [btn setImage:icon forState:UIControlStateNormal];
        [btn setTintColor:color];
        [btn setBackgroundColor:[color colorWithAlphaComponent:0.1]];
        btn.layer.cornerRadius = 6;
        btn.contentEdgeInsets = UIEdgeInsetsMake(6, 8, 6, 8);
    }
    
    return btn;
}

+ (UIView *)createVansonFooterViewForWidth:(CGFloat)width {
    UIView *footer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 60)];
    UILabel *lbl = [[UILabel alloc] initWithFrame:footer.bounds];
    lbl.text = @"VansonMod";
    lbl.textAlignment = NSTextAlignmentCenter;
    lbl.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    lbl.textColor = [UIColor systemGrayColor];
    lbl.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [footer addSubview:lbl];
    return footer;
}

+ (void)addFixedFooterTo:(UIViewController *)vc forTableView:(UITableView *)tableView {
    
    for (UIView *sub in vc.view.subviews) {
        if (sub.tag == 999111) {
            [sub removeFromSuperview];
        }
    }

    UIView *footer = [[UIView alloc] init];
    footer.tag = 999111; 
    footer.backgroundColor = [UIColor clearColor];
    footer.translatesAutoresizingMaskIntoConstraints = NO;
    
    footer.userInteractionEnabled = NO;
    
    [vc.view addSubview:footer];
    
    [vc.view bringSubviewToFront:footer];
    
    UILabel *lbl = [[UILabel alloc] init];
    lbl.text = @"VansonMod";
    lbl.textAlignment = NSTextAlignmentCenter;
    
    lbl.textColor = [[UIColor systemOrangeColor] colorWithAlphaComponent:1];
    
    lbl.font = [UIFont systemFontOfSize:12 weight:UIFontWeightBold];
    lbl.translatesAutoresizingMaskIntoConstraints = NO;
    [footer addSubview:lbl];
    
    UILayoutGuide *guide = vc.view.safeAreaLayoutGuide;
    
    CGFloat height = 16.0;
    
    [NSLayoutConstraint activateConstraints:@[
        
        [footer.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor constant:-2],
        
        [footer.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
        [footer.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor],
        
        [footer.heightAnchor constraintEqualToConstant:height],
        
        [lbl.centerXAnchor constraintEqualToAnchor:footer.centerXAnchor],
        
        [lbl.centerYAnchor constraintEqualToAnchor:footer.centerYAnchor]
    ]];
    
    if (tableView) {
        UIEdgeInsets insets = tableView.contentInset;
        insets.bottom += 20; 
        tableView.contentInset = insets;
        
        UIEdgeInsets indicatorInsets = tableView.verticalScrollIndicatorInsets;
        indicatorInsets.bottom += 20;
        tableView.verticalScrollIndicatorInsets = indicatorInsets;
    }
}

@end
