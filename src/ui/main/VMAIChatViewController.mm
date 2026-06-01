#import <UIKit/UIKit.h>
#import "VMAIManager.h"

@interface VMAIChatViewController : UIViewController <UITextFieldDelegate>
@end

@implementation VMAIChatViewController {
  UITextView *_chatView;
  UITextField *_inputField;
  UIButton *_sendButton;
  NSMutableArray<NSDictionary *> *_messages;
}

- (void)viewDidLoad {
  [super viewDidLoad];
  self.title = @"MiMo AI Chat";
  self.view.backgroundColor = [UIColor systemBackgroundColor];
  _messages = [NSMutableArray array];

  self.navigationItem.leftBarButtonItem =
      [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose
                                                    target:self
                                                    action:@selector(closeSelf)];

  _chatView = [[UITextView alloc] initWithFrame:CGRectZero];
  _chatView.translatesAutoresizingMaskIntoConstraints = NO;
  _chatView.editable = NO;
  _chatView.font = [UIFont systemFontOfSize:15];
  _chatView.layer.cornerRadius = 12;
  _chatView.backgroundColor = [UIColor secondarySystemBackgroundColor];
  _chatView.text = @"MiMo AI 已就绪\n";
  [self.view addSubview:_chatView];

  UIView *bar = [[UIView alloc] initWithFrame:CGRectZero];
  bar.translatesAutoresizingMaskIntoConstraints = NO;
  [self.view addSubview:bar];

  _inputField = [[UITextField alloc] initWithFrame:CGRectZero];
  _inputField.translatesAutoresizingMaskIntoConstraints = NO;
  _inputField.placeholder = @"输入消息...";
  _inputField.borderStyle = UITextBorderStyleRoundedRect;
  _inputField.returnKeyType = UIReturnKeySend;
  _inputField.delegate = self;
  [bar addSubview:_inputField];

  _sendButton = [UIButton buttonWithType:UIButtonTypeSystem];
  _sendButton.translatesAutoresizingMaskIntoConstraints = NO;
  [_sendButton setTitle:@"Send" forState:UIControlStateNormal];
  [_sendButton addTarget:self action:@selector(sendMessage) forControlEvents:UIControlEventTouchUpInside];
  [bar addSubview:_sendButton];

  UILayoutGuide *g = self.view.safeAreaLayoutGuide;
  [NSLayoutConstraint activateConstraints:@[
    [_chatView.topAnchor constraintEqualToAnchor:g.topAnchor constant:12],
    [_chatView.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:12],
    [_chatView.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-12],
    [_chatView.bottomAnchor constraintEqualToAnchor:bar.topAnchor constant:-10],

    [bar.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:12],
    [bar.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-12],
    [bar.bottomAnchor constraintEqualToAnchor:g.bottomAnchor constant:-12],
    [bar.heightAnchor constraintEqualToConstant:44],

    [_inputField.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor],
    [_inputField.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],
    [_inputField.trailingAnchor constraintEqualToAnchor:_sendButton.leadingAnchor constant:-8],

    [_sendButton.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor],
    [_sendButton.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],
    [_sendButton.widthAnchor constraintEqualToConstant:60],
  ]];
}

- (void)closeSelf {
  [self dismissViewControllerAnimated:YES completion:nil];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
  [self sendMessage];
  return YES;
}

- (void)appendLine:(NSString *)line {
  NSString *old = _chatView.text ?: @"";
  _chatView.text = [old stringByAppendingFormat:@"\n%@", line ?: @""];
  if (_chatView.text.length > 0) {
    [_chatView scrollRangeToVisible:NSMakeRange(_chatView.text.length - 1, 1)];
  }
}

- (void)sendMessage {
  NSString *msg = _inputField.text ?: @"";
  if (msg.length == 0) return;

  [_messages addObject:@{@"role": @"user", @"content": msg}];
  [self appendLine:[NSString stringWithFormat:@"你：%@", msg]];
  _inputField.text = @"";
  _sendButton.enabled = NO;

  VMAIManager *ai = [VMAIManager shared];
  if (![ai isConfigured]) {
    [self appendLine:@"AI：API Key 未配置"];
    _sendButton.enabled = YES;
    return;
  }

  [self appendLine:@"AI：思考中..."];
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    NSString *reply = [ai chatSync:msg];
    dispatch_async(dispatch_get_main_queue(), ^{
      NSString *t = self->_chatView.text ?: @"";
      NSRange r = [t rangeOfString:@"AI：思考中..." options:NSBackwardsSearch];
      if (r.location != NSNotFound) {
        self->_chatView.text = [t stringByReplacingCharactersInRange:r withString:[NSString stringWithFormat:@"AI：%@", reply ?: @""]];
      } else {
        [self appendLine:[NSString stringWithFormat:@"AI：%@", reply ?: @""]];
      }
      [self->_messages addObject:@{@"role": @"assistant", @"content": reply ?: @""}];
      self->_sendButton.enabled = YES;
    });
  });
}

@end
