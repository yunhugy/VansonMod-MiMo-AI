#import <UIKit/UIKit.h>
#import "../../utils/managers/VMAIManager.h"

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

- (NSString *)systemPrompt {
  return @"你是 VansonMod 内置的 AI 助手，运行在用户的 iOS 设备上。"
  @"VansonMod 是一款基于 TrollStore 的 iOS 内存编辑与逆向调试工具，支持以下功能：\n\n"
  @"## 核心功能\n"
  @"- **内存搜索**：精确搜索、模糊搜索（变大/变小/改变）、分组搜索、范围搜索、附近搜索、签名搜索\n"
  @"- **内存编辑**：批量修改值、Hex编辑、内存浏览器\n"
  @"- **指针分析**：自动指针链搜索、指针验证、指针锁定\n"
  @"- **RVA补丁**：模块偏移补丁、ARM64指令预设\n"
  @"- **脚本系统**：内置JavaScript运行时，支持自动化操作\n"
  @"- **应用存档**：Documents/Library备份恢复\n"
  @"- **进程审计**：对比代码变化\n\n"
  @"## JS 脚本 API（用户在脚本编辑器里写JS调用）\n"
  @"```javascript\n"
  @"vm.search(val, type, start, end)  // 搜索内存，type: I32/I64/F32/F64/U8等\n"
  @"vm.refine(val, type, mode)  // 过滤结果，mode: eq/gt/lt/chg\n"
  @"vm.searchFuzzy(type)  // 模糊搜索（值改变了的）\n"
  @"vm.searchGroup(val, type, start, end)  // 分组搜索\n"
  @"vm.searchBetween(min, max, type)  // 范围搜索\n"
  @"vm.nearby(val, type, range)  // 附近搜索\n"
  @"vm.searchSign(signature, start, end)  // 签名搜索\n"
  @"vm.getResults(count, skip)  // 获取搜索结果\n"
  @"vm.getResultsCount()  // 结果数量\n"
  @"vm.getValue(addr, type)  // 读取地址值\n"
  @"vm.setValue(addr, val, type)  // 写入地址值\n"
  @"vm.editAll(val, type, filter)  // 批量修改所有结果\n"
  @"vm.write(val, type, index)  // 修改第N个结果\n"
  @"vm.lock(val, type, index)  // 锁定值\n"
  @"vm.unlock(index)  // 解锁\n"
  @"vm.lockAll(val, type, filter)  // 批量锁定\n"
  @"vm.unlockAll()  // 全部解锁\n"
  @"vm.clear()  // 清除搜索结果\n"
  @"vm.log(msg)  // 输出到控制台\n"
  @"vm.toast(msg)  // 弹窗提示\n"
  @"vm.sleep(seconds)  // 延时\n"
  @"vm.setBaseAddress(addr)  // 设置基址\n"
  @"vm.setFloatTolerance(tol)  // 设置浮点容差\n"
  @"// 指针操作\n"
  @"vm.resolvePointer(module, baseOffset, offsets, type)\n"
  @"vm.writePointer(module, baseOffset, offsets, val, type)\n"
  @"vm.lockPointer(module, baseOffset, offsets, val, type, note)\n"
  @"// RVA补丁\n"
  @"vm.patchRVA(module, offset, patchHex)\n"
  @"vm.restoreRVA(module, offset, originalHex)\n"
  @"vm.readRVA(module, offset, length)\n"
  @"```\n\n"
  @"## 你的职责\n"
  @"1. 当用户描述想要修改的内容（比如金币、血量、攻击力），帮他们分析应该搜索什么值、用什么类型、怎么过滤\n"
  @"2. 直接给出可以复制到VansonMod脚本编辑器里运行的JS代码\n"
  @"3. 解释VansonMod的各种功能和操作步骤\n"
  @"4. 帮用户分析搜索结果、判断哪个地址最可能是目标\n"
  @"5. 用中文回答，简洁实用，代码优先";
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

  // Build full message array with system prompt
  NSMutableArray *fullMessages = [NSMutableArray array];
  [fullMessages addObject:@{@"role": @"system", @"content": [self systemPrompt]}];
  [fullMessages addObjectsFromArray:_messages];

  [self appendLine:@"AI：思考中..."];
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    NSString *reply = [ai chatSync:msg system:[self systemPrompt]];
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
