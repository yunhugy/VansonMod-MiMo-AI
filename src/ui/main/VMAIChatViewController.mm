#import <UIKit/UIKit.h>
#import "../../utils/managers/VMAIManager.h"
#import "../../utils/managers/VMScriptManager.h"
#import "include/VMMemoryEngine.h"
#import "include/VMPointerManager.h"
#import <objc/runtime.h>

@interface VMAIChatViewController : UIViewController <UITextFieldDelegate>
@end

@implementation VMAIChatViewController {
  UITextView *_chatView;
  UITextField *_inputField;
  UIButton *_sendButton;
  UIView *_inputBar;
  NSLayoutConstraint *_barBottomConstraint;
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

  // Clear chat button
  self.navigationItem.rightBarButtonItem =
      [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemTrash
                                                    target:self
                                                    action:@selector(clearChat)];

  _chatView = [[UITextView alloc] initWithFrame:CGRectZero];
  _chatView.translatesAutoresizingMaskIntoConstraints = NO;
  _chatView.editable = NO;
  _chatView.font = [UIFont systemFontOfSize:15];
  _chatView.layer.cornerRadius = 12;
  _chatView.backgroundColor = [UIColor secondarySystemBackgroundColor];
  _chatView.text = @"MiMo AI 已就绪\n";
  [self.view addSubview:_chatView];

  _inputBar = [[UIView alloc] initWithFrame:CGRectZero];
  _inputBar.translatesAutoresizingMaskIntoConstraints = NO;
  _inputBar.backgroundColor = [UIColor tertiarySystemBackgroundColor];
  [self.view addSubview:_inputBar];

  _inputField = [[UITextField alloc] initWithFrame:CGRectZero];
  _inputField.translatesAutoresizingMaskIntoConstraints = NO;
  _inputField.placeholder = @"输入消息...";
  _inputField.borderStyle = UITextBorderStyleRoundedRect;
  _inputField.returnKeyType = UIReturnKeySend;
  _inputField.delegate = self;
  [_inputBar addSubview:_inputField];

  _sendButton = [UIButton buttonWithType:UIButtonTypeSystem];
  _sendButton.translatesAutoresizingMaskIntoConstraints = NO;
  [_sendButton setTitle:@"Send" forState:UIControlStateNormal];
  [_sendButton addTarget:self action:@selector(sendMessage) forControlEvents:UIControlEventTouchUpInside];
  [_inputBar addSubview:_sendButton];

  UILayoutGuide *g = self.view.safeAreaLayoutGuide;

  // Bar bottom constraint - will animate with keyboard
  _barBottomConstraint = [_inputBar.bottomAnchor constraintEqualToAnchor:g.bottomAnchor constant:0];

  [NSLayoutConstraint activateConstraints:@[
    [_chatView.topAnchor constraintEqualToAnchor:g.topAnchor constant:12],
    [_chatView.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:12],
    [_chatView.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-12],
    [_chatView.bottomAnchor constraintEqualToAnchor:_inputBar.topAnchor constant:-8],

    [_inputBar.leadingAnchor constraintEqualToAnchor:g.leadingAnchor],
    [_inputBar.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],
    _barBottomConstraint,
    [_inputBar.heightAnchor constraintEqualToConstant:50],

    [_inputField.leadingAnchor constraintEqualToAnchor:_inputBar.leadingAnchor constant:12],
    [_inputField.centerYAnchor constraintEqualToAnchor:_inputBar.centerYAnchor],
    [_inputField.trailingAnchor constraintEqualToAnchor:_sendButton.leadingAnchor constant:-8],

    [_sendButton.trailingAnchor constraintEqualToAnchor:_inputBar.trailingAnchor constant:-12],
    [_sendButton.centerYAnchor constraintEqualToAnchor:_inputBar.centerYAnchor],
    [_sendButton.widthAnchor constraintEqualToConstant:60],
  ]];

  // Keyboard notifications
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(keyboardWillShow:)
                                               name:UIKeyboardWillShowNotification
                                             object:nil];
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(keyboardWillHide:)
                                               name:UIKeyboardWillHideNotification
                                             object:nil];
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)keyboardWillShow:(NSNotification *)notif {
  NSDictionary *info = notif.userInfo;
  CGRect frame = [info[UIKeyboardFrameEndUserInfoKey] CGRectValue];
  NSTimeInterval duration = [info[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
  UIViewAnimationCurve curve = [info[UIKeyboardAnimationCurveUserInfoKey] integerValue];

  // Convert keyboard frame to view coordinates
  CGRect kbFrame = [self.view convertRect:frame fromView:nil];
  CGFloat overlap = self.view.bounds.size.height - kbFrame.origin.y;

  _barBottomConstraint.constant = -overlap;

  [UIView animateWithDuration:duration delay:0 options:(curve << 16) animations:^{
    [self.view layoutIfNeeded];
  } completion:nil];
}

- (void)keyboardWillHide:(NSNotification *)notif {
  NSDictionary *info = notif.userInfo;
  NSTimeInterval duration = [info[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
  UIViewAnimationCurve curve = [info[UIKeyboardAnimationCurveUserInfoKey] integerValue];

  _barBottomConstraint.constant = 0;

  [UIView animateWithDuration:duration delay:0 options:(curve << 16) animations:^{
    [self.view layoutIfNeeded];
  } completion:nil];
}

- (void)closeSelf {
  [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)clearChat {
  _messages = [NSMutableArray array];
  _chatView.text = @"MiMo AI 已就绪\n";
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

#pragma mark - Process Context

- (NSString *)currentProcessContext {
  VMMemoryEngine *eng = [VMMemoryEngine shared];
  NSMutableString *ctx = [NSMutableString string];

  NSString *procName = eng.currentProcessName;
  pid_t pid = eng.targetPid;
  NSUInteger resultCount = eng.resultCount;

  if (procName.length > 0 && pid > 0) {
    [ctx appendString:@"## 当前已连接的进程\n"];
    [ctx appendFormat:@"- 进程名: %@\n", procName];
    [ctx appendFormat:@"- PID: %d\n", pid];
  } else {
    [ctx appendString:@"## 当前状态: 未连接进程\n"];
  }

  if (resultCount > 0) {
    [ctx appendString:@"\n## 当前搜索结果\n"];
    [ctx appendFormat:@"- 结果数量: %lu\n", (unsigned long)resultCount];
  } else {
    [ctx appendString:@"\n## 搜索结果: 无\n"];
  }

  return ctx;
}

#pragma mark - System Prompt

- (NSString *)systemPrompt {
  NSString *processCtx = [self currentProcessContext];

  return [NSString stringWithFormat:
    @"你是 VansonMod 内置的 AI 助手，运行在用户的 iOS 设备上。"
    @"VansonMod 是一款基于 TrollStore 的 iOS 内存编辑与逆向调试工具。\n\n"
    @"## 当前运行时上下文\n"
    @"%@\n\n"
    @"## 核心功能\n"
    @"- 内存搜索：精确/模糊/分组/范围/附近/签名搜索\n"
    @"- 内存编辑：批量修改值、Hex编辑\n"
    @"- 指针分析：自动指针链搜索、验证、锁定\n"
    @"- RVA补丁：模块偏移补丁\n"
    @"- 脚本系统：内置JavaScript运行时\n\n"
    @"## JS 脚本 API\n"
    @"```javascript\n"
    @"vm.search(val, type, start, end)  // type: I32/I64/F32/F64/U8/U16/U32/U64\n"
    @"vm.refine(val, type, mode)  // mode: eq/gt/lt/chg\n"
    @"vm.searchFuzzy(type)\n"
    @"vm.searchGroup(val, type, start, end)\n"
    @"vm.searchBetween(min, max, type)\n"
    @"vm.nearby(val, type, range)\n"
    @"vm.searchSign(signature, start, end)\n"
    @"vm.getResults(count, skip)  // 获取搜索结果数组\n"
    @"vm.getResultsCount()\n"
    @"vm.getValue(addr, type)  // 读取地址的值\n"
    @"vm.setValue(addr, val, type)  // 写入值\n"
    @"vm.editAll(val, type, filter)  // 批量修改\n"
    @"vm.lock(val, type, index)  // 锁定值\n"
    @"vm.unlock(index) / vm.unlockAll()\n"
    @"vm.clear()  // 清除结果\n"
    @"vm.log(msg) / vm.toast(msg) / vm.sleep(sec)\n"
    @"vm.resolvePointer(module, baseOffset, offsets, type)\n"
    @"vm.patchRVA(module, offset, patchHex)\n"
    @"```\n\n"
    @"## 你的职责\n"
    @"1. 你已经知道当前连接的进程和搜索结果（见上方上下文），直接基于这些信息回答\n"
    @"2. 当用户想修改某个值（金币/血量/攻击力），直接给出搜索策略和完整可运行的JS脚本\n"
    @"3. 如果已有搜索结果，帮用户分析哪个地址最可能是目标，给出缩小范围的建议\n"
    @"4. 用中文回答，代码可直接复制到VansonMod脚本编辑器运行\n"
    @"5. 如果用户没连进程，提醒他先在VansonMod里选择目标进程并连接",
    processCtx];
}

- (void)sendMessage {
  NSString *msg = _inputField.text ?: @"";
  if (msg.length == 0) return;

  [_messages addObject:@{@"role": @"user", @"content": msg}];
  [self appendLine:[NSString stringWithFormat:@"\n你：%@", msg]];
  _inputField.text = @"";
  _sendButton.enabled = NO;

  VMAIManager *ai = [VMAIManager shared];
  if (![ai isConfigured]) {
    [self appendLine:@"AI：API Key 未配置，请先在设置里填写"];
    _sendButton.enabled = YES;
    return;
  }

  [self appendLine:@"AI：思考中..."];

  // Build full messages with system prompt + history
  NSMutableArray *fullMsgs = [NSMutableArray array];
  [fullMsgs addObject:@{@"role": @"system", @"content": [self systemPrompt]}];
  [fullMsgs addObjectsFromArray:_messages];

  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    NSString *reply = [ai chatSync:msg system:[self systemPrompt]];
    dispatch_async(dispatch_get_main_queue(), ^{
      NSString *t = self->_chatView.text ?: @"";
      NSRange r = [t rangeOfString:@"AI：思考中..." options:NSBackwardsSearch];
      if (r.location != NSNotFound) {
        self->_chatView.text = [t stringByReplacingCharactersInRange:r
 withString:[NSString stringWithFormat:@"AI：\n%@", reply ?: @""]];
      } else {
        [self appendLine:[NSString stringWithFormat:@"AI：\n%@", reply ?: @""]];
      }
      [self->_messages addObject:@{@"role": @"assistant", @"content": reply ?: @""}];
      self->_sendButton.enabled = YES;
    });
  });
}

@end
