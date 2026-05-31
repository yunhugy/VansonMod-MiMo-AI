#import "../pointer/VMPointerSessionListViewController.h"
#import "../../utils/helpers/VMShareHelper.h"
#import "../../utils/helpers/VMUIHelper.h"
#import "../pointer/VMPointerVerifierViewController.h"
#import "include/VMLocalization.h"
#import "include/VMPointerManager.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#define TR(key) ([[VMLocalization shared] localizedString:key])
@interface VMPointerSessionListViewController () <
    UITableViewDelegate, UITableViewDataSource, UIDocumentPickerDelegate>
@property(nonatomic, strong) UITableView *tableView;
@property(nonatomic, strong) NSMutableArray<NSString *> *sessionFiles;
@property(nonatomic, assign) BOOL isGlobalSelectAll;
@end
@implementation VMPointerSessionListViewController
- (void)viewDidLoad {
  [super viewDidLoad];
  self.folderList = [NSMutableArray array];
  self.sessionFiles = [NSMutableArray array];
  if (self.bundleID && self.bundleID.length > 0) {
    self.isFolderMode = NO;
    NSString *displayName = self.bundleID ?: TR(@"App_Unknown");
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    id proxy = [NSClassFromString(@"LSApplicationProxy")
        performSelector:NSSelectorFromString(@"applicationProxyForIdentifier:")
             withObject:self.bundleID];
    if (proxy) {
      NSString *name =
          [proxy performSelector:NSSelectorFromString(@"localizedName")];
      if (name && name.length > 0)
        displayName = name;
    }
#pragma clang diagnostic pop
    self.title = [NSString
        stringWithFormat:@"%@ - %@", displayName, TR(@"Ptr_List_Title")];
  } else {
    self.isFolderMode = YES;
    self.title = TR(@"Ptr_Sessions_Header");
  }
  self.navigationItem.leftBarButtonItem = nil;
  self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
  self.tableView =
      [[UITableView alloc] initWithFrame:self.view.bounds
                                   style:UITableViewStyleInsetGrouped];
  self.tableView.delegate = self;
  self.tableView.dataSource = self;
  self.tableView.allowsMultipleSelectionDuringEditing = YES;
  self.tableView.autoresizingMask =
      UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  [self.view addSubview:self.tableView];
  [VMUIHelper addFixedFooterTo:self forTableView:self.tableView];
  UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc]
      initWithTarget:self
              action:@selector(handleLongPress:)];
  [self.tableView addGestureRecognizer:lp];
  [self updateNavBarButtons];
  [self loadData];
}

#pragma mark - Navigation & Batch Mode
- (void)updateNavBarButtons {
  if (self.tableView.isEditing) {
    UIBarButtonItem *selAllBtn =
        [[UIBarButtonItem alloc] initWithTitle:TR(@"Batch_Sel_All")
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(batchSelectAll)];
    self.navigationItem.leftBarButtonItem = selAllBtn;
    UIBarButtonItem *cancelBtn =
        [[UIBarButtonItem alloc] initWithTitle:TR(@"Btn_Cancel")
                                         style:UIBarButtonItemStyleDone
                                        target:self
                                        action:@selector(exitBatchMode)];
    self.navigationItem.rightBarButtonItem = cancelBtn;
    UIButton *delBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [delBtn setTitle:TR(@"Act_Delete") forState:UIControlStateNormal];
    [delBtn setTitleColor:[UIColor systemRedColor]
                 forState:UIControlStateNormal];
    [delBtn setImage:[UIImage systemImageNamed:@"trash.fill"]
            forState:UIControlStateNormal];
    delBtn.tintColor = [UIColor systemRedColor];
    delBtn.titleLabel.font = [UIFont systemFontOfSize:15
                                               weight:UIFontWeightBold];
    [delBtn addTarget:self
                  action:@selector(performBatchDelete)
        forControlEvents:UIControlEventTouchUpInside];
    self.navigationItem.titleView = delBtn;
  } else {
    self.navigationItem.leftBarButtonItem = nil;
    self.navigationItem.titleView = nil;
    UIBarButtonItem *importBtn = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"square.and.arrow.down"]
                style:UIBarButtonItemStylePlain
               target:self
               action:@selector(importSession)];
    self.navigationItem.rightBarButtonItems = @[ importBtn ];
  }
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture {
  if (gesture.state == UIGestureRecognizerStateBegan) {
    if (!self.tableView.isEditing) {
      [self enterBatchMode];
      CGPoint p = [gesture locationInView:self.tableView];
      NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:p];
      if (indexPath) {
        [self.tableView selectRowAtIndexPath:indexPath
                                    animated:YES
                              scrollPosition:UITableViewScrollPositionNone];
      }
    }
  }
}

- (void)enterBatchMode {
  self.isGlobalSelectAll = NO;
  [self.tableView setEditing:YES animated:YES];
  [self updateNavBarButtons];
}

- (void)exitBatchMode {
  self.isGlobalSelectAll = NO;
  [self.tableView setEditing:NO animated:YES];
  [self updateNavBarButtons];
}

#pragma mark - Data Loading
- (void)loadData {
  if (self.isFolderMode) {
    [self loadFolders];
  } else {
    [self loadFilesForBundleID:self.bundleID];
  }
}

- (void)loadFolders {
  NSString *root = [VMPointerManager shared].verifierFolder;
  NSArray *contents =
      [[NSFileManager defaultManager] contentsOfDirectoryAtPath:root error:nil];
  [self.folderList removeAllObjects];
  for (NSString *name in contents) {
    if ([name hasPrefix:@"."])
      continue;
    NSString *fullPath = [root stringByAppendingPathComponent:name];
    BOOL isDir = NO;
    [[NSFileManager defaultManager] fileExistsAtPath:fullPath
                                         isDirectory:&isDir];
    if (isDir) {
      [self.folderList addObject:name];
    }
  }
  [self.folderList
      sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
  [self.tableView reloadData];
}

- (void)loadFilesForBundleID:(NSString *)bid {
  [self loadSessions];
}

- (void)loadSessions {
  [self.sessionFiles removeAllObjects];
  if (!self.bundleID || self.bundleID.length == 0) {
    [self.tableView reloadData];
    return;
  }
  NSString *pointerDir = [[VMPointerManager shared].verifierFolder
      stringByAppendingPathComponent:self.bundleID];
  NSFileManager *fm = [NSFileManager defaultManager];
  if (![fm fileExistsAtPath:pointerDir]) {
    [fm createDirectoryAtPath:pointerDir
        withIntermediateDirectories:YES
                         attributes:nil
                              error:nil];
  }
  NSArray *files = [fm contentsOfDirectoryAtPath:pointerDir error:nil];
  NSMutableArray *filteredFiles = [NSMutableArray array];
  for (NSString *file in files) {
    if ([file hasSuffix:@".vmvapt"]) {
      [filteredFiles addObject:file];
    }
  }
  NSArray *sorted = [filteredFiles
      sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        NSDictionary *attrA = [fm
            attributesOfItemAtPath:[pointerDir stringByAppendingPathComponent:a]
                             error:nil];
        NSDictionary *attrB = [fm
            attributesOfItemAtPath:[pointerDir stringByAppendingPathComponent:b]
                             error:nil];
        return [attrB.fileModificationDate compare:attrA.fileModificationDate];
      }];
  self.sessionFiles = [sorted mutableCopy];
  [self.tableView reloadData];
}

- (void)importSession {
  NSArray *types = @[
    [UTType typeWithFilenameExtension:@"vmvapt"] ?: UTTypeData,
    UTTypeData 
  ];
  UIDocumentPickerViewController *picker =
      [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types
                                                                  asCopy:YES];
  picker.delegate = self;
  picker.allowsMultipleSelection = NO;
  [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller
    didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
  if (urls.count == 0)
    return;
  NSURL *url = urls.firstObject;
  BOOL accessing = [url startAccessingSecurityScopedResource];
  if (!self.bundleID || self.bundleID.length == 0) {
    [self showToast:TR(@"Err_Not_Connected_Msg")];
    if (accessing)
      [url stopAccessingSecurityScopedResource];
    return;
  }
  NSString *pointerDir = [VMPointerManager shared].verifierFolder;
  NSString *appDir = [pointerDir stringByAppendingPathComponent:self.bundleID];
  NSFileManager *fm = [NSFileManager defaultManager];
  if (![fm fileExistsAtPath:appDir]) {
    [fm createDirectoryAtPath:appDir
        withIntermediateDirectories:YES
                         attributes:nil
                              error:nil];
  }
  NSString *fileName = url.lastPathComponent;
  NSString *destPath = [appDir stringByAppendingPathComponent:fileName];
  if ([fm fileExistsAtPath:destPath]) {
    NSString *nameNoExt = [fileName stringByDeletingPathExtension];
    NSString *ext = [fileName pathExtension];
    NSString *uuid = [[NSUUID UUID] UUIDString];
    NSString *newObjName =
        [NSString stringWithFormat:@"%@_%@.%@", nameNoExt,
                                   [uuid substringToIndex:4], ext];
    destPath = [appDir stringByAppendingPathComponent:newObjName];
  }
  NSError *err;
  if ([fm copyItemAtPath:url.path toPath:destPath error:&err]) {
    [self loadSessions];
    [self showToast:TR(@"Ptr_Import_Success")];
  } else {
    [self showToast:[NSString stringWithFormat:TR(@"Err_Import_Failed"),
                                               err.localizedDescription]];
  }
  if (accessing)
    [url stopAccessingSecurityScopedResource];
}

#pragma mark - TableView
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
  return 1;
}

- (void)batchSelectAll {
  self.isGlobalSelectAll = !self.isGlobalSelectAll;
  NSInteger section = 0;
  NSInteger count = [self.tableView numberOfRowsInSection:section];
  for (int i = 0; i < count; i++) {
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:i inSection:section];
    if (self.isGlobalSelectAll) {
      [self.tableView selectRowAtIndexPath:indexPath
                                  animated:NO
                            scrollPosition:UITableViewScrollPositionNone];
    } else {
      [self.tableView deselectRowAtIndexPath:indexPath animated:NO];
    }
  }
  self.navigationItem.leftBarButtonItem.title =
      self.isGlobalSelectAll ? TR(@"Btn_Deselect_All") : TR(@"Batch_Sel_All");
}

- (void)performBatchDelete {
  NSArray *selectedPaths = [self.tableView indexPathsForSelectedRows];
  if (!selectedPaths || selectedPaths.count == 0) {
    [self showToast:TR(@"Msg_No_Sel")];
    return;
  }
  NSString *confirmMsg = [NSString
      stringWithFormat:@"%@ %@", TR(@"Act_Delete"),
                       [NSString stringWithFormat:TR(@"Ptr_Delete_Confirm_Fmt"),
                                                  (unsigned long)
                                                      selectedPaths.count]];
  UIAlertController *alert =
      [UIAlertController alertControllerWithTitle:TR(@"Alert_Warn")
                                          message:confirmMsg
                                   preferredStyle:UIAlertControllerStyleAlert];
  [alert addAction:[UIAlertAction actionWithTitle:TR(@"Btn_Cancel")
                                            style:UIAlertActionStyleCancel
                                          handler:nil]];
  [alert
      addAction:
          [UIAlertAction
              actionWithTitle:TR(@"Act_Delete")
                        style:UIAlertActionStyleDestructive
                      handler:^(UIAlertAction *_Nonnull action) {
                        NSArray *sortedPaths = [selectedPaths
                            sortedArrayUsingComparator:^NSComparisonResult(
                                NSIndexPath *obj1, NSIndexPath *obj2) {
                              return [obj2 compare:obj1];
                            }];
                        NSFileManager *fm = [NSFileManager defaultManager];
                        if (self.isFolderMode) {
                          NSString *root =
                              [VMPointerManager shared].verifierFolder;
                          for (NSIndexPath *ip in sortedPaths) {
                            if (ip.row < self.folderList.count) {
                              NSString *name = self.folderList[ip.row];
                              NSString *path =
                                  [root stringByAppendingPathComponent:name];
                              [fm removeItemAtPath:path error:nil];
                              [self.folderList removeObjectAtIndex:ip.row];
                            }
                          }
                        } else {
                          NSString *pointerDir =
                              [[VMPointerManager shared].verifierFolder
                                  stringByAppendingPathComponent:self.bundleID];
                          for (NSIndexPath *ip in sortedPaths) {
                            if (ip.row < self.sessionFiles.count) {
                              NSString *fileName = self.sessionFiles[ip.row];
                              NSString *path = [pointerDir
                                  stringByAppendingPathComponent:fileName];
                              [fm removeItemAtPath:path error:nil];
                              [self.sessionFiles removeObjectAtIndex:ip.row];
                            }
                          }
                          [self exitBatchMode];
                          [self checkAndCleanupCurrentFolder];
                          [self.tableView reloadData];
                        }
                        [self showToast:TR(@"Batch_Del_Success")];
                      }]];
  [self presentViewController:alert animated:YES completion:nil];
}

- (NSInteger)tableView:(UITableView *)tableView
    numberOfRowsInSection:(NSInteger)section {
  if (self.isFolderMode)
    return self.folderList.count;
  return self.sessionFiles.count;
}

- (NSString *)tableView:(UITableView *)tableView
    titleForHeaderInSection:(NSInteger)section {
  if (self.isFolderMode)
    return TR(@"Ptr_Sessions_Header");
  return nil;
}

- (NSString *)tableView:(UITableView *)tableView
    titleForFooterInSection:(NSInteger)section {
  if (self.isFolderMode) {
    if (self.folderList.count == 0) {
      return TR(@"Ptr_Sessions_Empty");
    }
  } else {
    if (self.sessionFiles.count == 0) {
      return TR(@"Ptr_Sessions_Empty");
    }
  }
  return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
  if (self.isFolderMode) {
    static NSString *cid = @"folder";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cid];
    if (!cell) {
      cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
                                    reuseIdentifier:cid];
      cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    NSString *bundleID = self.folderList[indexPath.row];
    cell.textLabel.text = bundleID;
    cell.imageView.image = [UIImage systemImageNamed:@"folder.fill"];
    return cell;
  } else {
    static NSString *cid = @"sessionCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cid];
    if (!cell) {
      cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                    reuseIdentifier:cid];
      cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    NSString *fileName = self.sessionFiles[indexPath.row];

    NSString *idxStr =
        [NSString stringWithFormat:@"[%ld] ", (long)(indexPath.row + 1)];
    cell.textLabel.text = [NSString stringWithFormat:@"%@%@", idxStr, fileName];
    cell.textLabel.font = [UIFont systemFontOfSize:15];
    NSString *fullPath = [[[VMPointerManager shared].verifierFolder
        stringByAppendingPathComponent:self.bundleID]
        stringByAppendingPathComponent:fileName];
    NSDictionary *attrs =
        [[NSFileManager defaultManager] attributesOfItemAtPath:fullPath
                                                         error:nil];
    NSDate *modDate = attrs.fileModificationDate;
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    cell.detailTextLabel.text = [fmt stringFromDate:modDate];
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    return cell;
  }
}

- (void)tableView:(UITableView *)tableView
    didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
  if (tableView.isEditing) {
    return;
  }
  [tableView deselectRowAtIndexPath:indexPath animated:YES];
  if (self.isFolderMode) {
    NSString *selectedBid = self.folderList[indexPath.row];
    VMPointerSessionListViewController *nextVC =
        [[VMPointerSessionListViewController alloc] init];
    nextVC.bundleID = selectedBid;
    [self.navigationController pushViewController:nextVC animated:YES];
  } else {
    if (!self.bundleID || self.bundleID.length == 0)
      return;
    NSString *fileName = self.sessionFiles[indexPath.row];
    NSString *pointerDir = [[VMPointerManager shared].verifierFolder
        stringByAppendingPathComponent:self.bundleID];
    NSString *fullPath = [pointerDir stringByAppendingPathComponent:fileName];
    VMPointerVerifierViewController *vc =
        [[VMPointerVerifierViewController alloc] init];
    vc.filePath = fullPath;
    [self.navigationController pushViewController:vc animated:YES];
  }
}

- (BOOL)tableView:(UITableView *)tableView
    canEditRowAtIndexPath:(NSIndexPath *)indexPath {
  return !self.isFolderMode;
}

- (void)tableView:(UITableView *)tableView
    commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
     forRowAtIndexPath:(NSIndexPath *)indexPath {
  if (editingStyle == UITableViewCellEditingStyleDelete) {
    NSString *fileName = self.sessionFiles[indexPath.row];
    NSString *pointerDir = [[VMPointerManager shared].verifierFolder
        stringByAppendingPathComponent:self.bundleID];
    NSString *fullPath = [pointerDir stringByAppendingPathComponent:fileName];
    [[NSFileManager defaultManager] removeItemAtPath:fullPath error:nil];
    [self.sessionFiles removeObjectAtIndex:indexPath.row];
    if (self.sessionFiles.count > 0) {
      [tableView deleteRowsAtIndexPaths:@[ indexPath ]
                       withRowAnimation:UITableViewRowAnimationFade];
    } else {
      [self checkAndCleanupCurrentFolder];
    }
  }
}

#pragma mark - Helpers
- (void)checkAndCleanupCurrentFolder {
  if (!self.bundleID)
    return;
  NSString *pointerDir = [[VMPointerManager shared].verifierFolder
      stringByAppendingPathComponent:self.bundleID];
  NSFileManager *fm = [NSFileManager defaultManager];
  if (![fm fileExistsAtPath:pointerDir])
    return;
  NSArray *contents = [fm contentsOfDirectoryAtPath:pointerDir error:nil];
  NSArray *vmvaptFiles = [contents
      filteredArrayUsingPredicate:
          [NSPredicate predicateWithFormat:@"self ENDSWITH '.vmvapt'"]];
  if (vmvaptFiles.count == 0) {
    [fm removeItemAtPath:pointerDir error:nil];
    dispatch_async(dispatch_get_main_queue(), ^{
      [self.navigationController popViewControllerAnimated:YES];
    });
  }
}

- (void)showToast:(NSString *)msg {
  UIAlertController *alert =
      [UIAlertController alertControllerWithTitle:nil
                                          message:msg
                                   preferredStyle:UIAlertControllerStyleAlert];
  [self presentViewController:alert animated:YES completion:nil];
  dispatch_after(
      dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)),
      dispatch_get_main_queue(), ^{
        [alert dismissViewControllerAnimated:YES completion:nil];
      });
}

#pragma mark - Swipe Actions

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
    trailingSwipeActionsConfigurationForRowAtIndexPath:
        (NSIndexPath *)indexPath {
  
  if (self.isFolderMode) {
    return nil;
  }

  NSString *fileName = self.sessionFiles[indexPath.row];

  UIContextualAction *del = [UIContextualAction
      contextualActionWithStyle:UIContextualActionStyleDestructive
                          title:TR(@"Act_Delete")
                        handler:^(UIContextualAction *action,
                                  UIView *sourceView,
                                  void (^completionHandler)(BOOL)) {
                          NSString *pointerDir =
                              [[VMPointerManager shared].verifierFolder
                                  stringByAppendingPathComponent:self.bundleID];
                          NSString *fullPath = [pointerDir
                              stringByAppendingPathComponent:fileName];
                          [[NSFileManager defaultManager]
                              removeItemAtPath:fullPath
                                         error:nil];
                          [self.sessionFiles removeObjectAtIndex:indexPath.row];
                          if (self.sessionFiles.count > 0) {
                            [tableView deleteRowsAtIndexPaths:@[ indexPath ]
                                             withRowAnimation:
                                                 UITableViewRowAnimationFade];
                          } else {
                            [self checkAndCleanupCurrentFolder];
                          }
                          completionHandler(YES);
                        }];
  del.title = TR(@"Act_Delete");

  UIContextualAction *share = [UIContextualAction
      contextualActionWithStyle:UIContextualActionStyleNormal
                          title:TR(@"Act_Export")
                        handler:^(UIContextualAction *action,
                                  UIView *sourceView,
                                  void (^completionHandler)(BOOL)) {
                          NSString *pointerDir =
                              [[VMPointerManager shared].verifierFolder
                                  stringByAppendingPathComponent:self.bundleID];
                          NSString *fullPath = [pointerDir
                              stringByAppendingPathComponent:fileName];
                          NSURL *url = [NSURL fileURLWithPath:fullPath];
                          CGRect rectInTableView =
                              [tableView rectForRowAtIndexPath:indexPath];
                          CGRect rectInView =
                              [tableView convertRect:rectInTableView
                                              toView:self.view];
                          [VMShareHelper shareContent:url
                                   fromViewController:self
                                           sourceView:self.view
                                           sourceRect:rectInView];
                          completionHandler(YES);
                        }];
  share.backgroundColor = [UIColor systemBlueColor];
  share.title = TR(@"Act_Export");

  UIContextualAction *rename = [UIContextualAction
      contextualActionWithStyle:UIContextualActionStyleNormal
                          title:TR(@"Common_Rename")
                        handler:^(UIContextualAction *action,
                                  UIView *sourceView,
                                  void (^completionHandler)(BOOL)) {
                          [self showRenameAlertForFile:fileName
                                           atIndexPath:indexPath];
                          completionHandler(YES);
                        }];
  rename.backgroundColor = [UIColor systemOrangeColor];
  rename.title = TR(@"Common_Rename");

  return [UISwipeActionsConfiguration
      configurationWithActions:@[ del, rename, share ]];
}

#pragma mark - Rename Logic

- (void)showRenameAlertForFile:(NSString *)fileName
                   atIndexPath:(NSIndexPath *)indexPath {
  NSString *nameNoExt = [fileName stringByDeletingPathExtension];
  NSString *ext = [fileName pathExtension];

  UIAlertController *alert =
      [UIAlertController alertControllerWithTitle:TR(@"Common_Rename")
                                          message:nil
                                   preferredStyle:UIAlertControllerStyleAlert];

  [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
    tf.text = nameNoExt;
    tf.placeholder = TR(@"Placeholder_New_Name");
    tf.clearButtonMode = UITextFieldViewModeWhileEditing;
  }];

  [alert addAction:[UIAlertAction actionWithTitle:TR(@"Btn_Cancel")
                                            style:UIAlertActionStyleCancel
                                          handler:nil]];

  [alert addAction:[UIAlertAction
                       actionWithTitle:TR(@"Btn_Confirm")
                                 style:UIAlertActionStyleDefault
                               handler:^(UIAlertAction *action) {
                                 NSString *newName =
                                     alert.textFields.firstObject.text;

                                 if (newName.length > 0 &&
                                     ![newName isEqualToString:nameNoExt]) {
                                   [self performRenameFile:fileName
                                                   newName:newName
                                                 extension:ext
                                               atIndexPath:indexPath];
                                 }
                               }]];

  [self presentViewController:alert animated:YES completion:nil];
}

- (void)performRenameFile:(NSString *)oldFileName
                  newName:(NSString *)newName
                extension:(NSString *)ext
              atIndexPath:(NSIndexPath *)indexPath {
  NSString *pointerDir = [[VMPointerManager shared].verifierFolder
      stringByAppendingPathComponent:self.bundleID];

  NSString *oldPath = [pointerDir stringByAppendingPathComponent:oldFileName];
  NSString *newFileName = [NSString stringWithFormat:@"%@.%@", newName, ext];
  NSString *newPath = [pointerDir stringByAppendingPathComponent:newFileName];

  NSFileManager *fm = [NSFileManager defaultManager];

  if (![fm fileExistsAtPath:oldPath]) {
    [self showToast:TR(@"Err_File_Read")];
    return;
  }

  if ([fm fileExistsAtPath:newPath]) {
    [self showToast:TR(@"Err_File_Exists")];
    return;
  }

  NSError *error;
  if ([fm moveItemAtPath:oldPath toPath:newPath error:&error]) {
    
    self.sessionFiles[indexPath.row] = newFileName;

    [self.tableView reloadRowsAtIndexPaths:@[ indexPath ]
                          withRowAnimation:UITableViewRowAnimationAutomatic];

    [self showToast:TR(@"Msg_Saved")];
  } else {
    [self showToast:[NSString stringWithFormat:@"Error: %@",
                                               error.localizedDescription]];
  }
}

@end
