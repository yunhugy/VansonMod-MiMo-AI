#import "VMProcessAuditViewController.h"
#import "include/VMMemoryEngine.h"
#import "include/VMLocalization.h"
#import "../../utils/helpers/VMUIHelper.h"
#include "../../core/AuditCore.hpp"
#include <mach/mach.h>
#include <sys/sysctl.h>
extern "C" int proc_pidpath(int pid, void *buffer, uint32_t buffersize);

#define TR(key) ([[VMLocalization shared] localizedString:key])

@interface VMAuditDiffItem : NSObject
@property (nonatomic, copy) NSString *moduleName;
@property (nonatomic, assign) uint64_t offset;
@property (nonatomic, assign) uint64_t runtimeAddress;
@property (nonatomic, copy) NSString *originalHex;
@property (nonatomic, copy) NSString *currentHex;
@property (nonatomic, strong) NSData *originalBytes;
@end
@implementation VMAuditDiffItem
@end

@interface VMProcessAuditViewController () <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSMutableArray<VMAuditDiffItem *> *diffItems;
@property (nonatomic, assign) BOOL isMonitoring; 
@property (nonatomic, assign) BOOL hasScanned;
@property (nonatomic, assign) pid_t targetPid;
@property (nonatomic, assign) mach_port_t targetTask;
@property (nonatomic, strong) NSTimer *pollTimer;
@end

static const NSInteger kSectionInfo = 0;
static const NSInteger kSectionDiffs = 1;
static const NSInteger kSectionExport = 2;
static const NSInteger kSectionCount = 3;

@implementation VMProcessAuditViewController

- (UIColor *)auditCardBackgroundColor {
    return [UIColor secondarySystemGroupedBackgroundColor];
}

- (UIColor *)auditSecondaryTextColor {
    return [UIColor secondaryLabelColor];
}

- (UIColor *)auditPrimaryActionColor {
    return [UIColor systemBlueColor];
}

- (UIColor *)auditSecondaryActionColor {
    return [UIColor systemOrangeColor];
}

- (UIColor *)auditStatusIdleBackgroundColor {
    return [UIColor tertiarySystemFillColor];
}

- (UIColor *)auditStatusIdleTextColor {
    return [UIColor secondaryLabelColor];
}

- (void)dealloc {
    [self stopPolling];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = TR(@"Audit_Title");
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];

    self.diffItems = [NSMutableArray array];
    self.isMonitoring = NO;
    self.hasScanned = NO;

    [self setupNavBar];
    [self setupTableView];
    [self resolveTarget];
}

- (void)setupNavBar {
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"info.circle"]
                style:UIBarButtonItemStylePlain
               target:self
               action:@selector(onShowInfo)];
}

- (void)setupTableView {
    CGRect tableFrame = self.view.bounds;
    self.tableView = [[UITableView alloc] initWithFrame:tableFrame
                                                  style:UITableViewStyleGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.autoresizingMask =
        UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.view addSubview:self.tableView];
    [VMUIHelper addFixedFooterTo:self forTableView:self.tableView];
}

#pragma mark - Target Resolution

- (void)onShowInfo {
    NSString *msg = [NSString stringWithFormat:@"%@\n\n%@",
        TR(@"Audit_Info_Static"), TR(@"Audit_Info_Dynamic")];
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:TR(@"Audit_Title")
                         message:msg
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:TR(@"Btn_OK")
        style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)resolveTarget {
    if (!self.bundleID) return;

    pid_t foundPid = 0;
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0};
    size_t size = 0;
    if (sysctl(mib, 4, NULL, &size, NULL, 0) != 0) return;

    struct kinfo_proc *procs = (struct kinfo_proc *)malloc(size);
    if (!procs) return;
    if (sysctl(mib, 4, procs, &size, NULL, 0) != 0) { free(procs); return; }

    int count = (int)(size / sizeof(struct kinfo_proc));
    for (int i = 0; i < count; i++) {
        pid_t pid = procs[i].kp_proc.p_pid;
        if (pid <= 0) continue;

        char pathBuf[4096] = {0};
        proc_pidpath(pid, pathBuf, sizeof(pathBuf));
        NSString *fullPath = [NSString stringWithUTF8String:pathBuf];
        if (![fullPath containsString:@".app"]) continue;

        NSString *appDir = [fullPath stringByDeletingLastPathComponent];
        while (![appDir.pathExtension isEqualToString:@"app"] &&
               ![appDir isEqualToString:@"/"]) {
            appDir = [appDir stringByDeletingLastPathComponent];
        }
        NSString *plistPath = [appDir stringByAppendingPathComponent:@"Info.plist"];
        NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:plistPath];
        if (info && [info[@"CFBundleIdentifier"] caseInsensitiveCompare:self.bundleID] == NSOrderedSame) {
            foundPid = pid;
            break;
        }
    }
    free(procs);

    if (foundPid > 0) {
        self.targetPid = foundPid;
        mach_port_t task = MACH_PORT_NULL;
        if (task_for_pid(mach_task_self(), foundPid, &task) == KERN_SUCCESS) {
            self.targetTask = task;
        }
    }
}

#pragma mark - Static Detection

- (void)onStaticDetect {
    if (self.targetTask == MACH_PORT_NULL) {
        [self resolveTarget];
        if (self.targetTask == MACH_PORT_NULL) {
            [self showToast:TR(@"Audit_No_Process")];
            return;
        }
    }

    UIAlertController *loading = [UIAlertController
        alertControllerWithTitle:nil
                         message:[NSString stringWithFormat:@"%@...",
                                  TR(@"Audit_Scanning")]
                  preferredStyle:UIAlertControllerStyleAlert];
    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc]
        initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [spinner startAnimating];
    [loading.view addSubview:spinner];
    [NSLayoutConstraint activateConstraints:@[
        [spinner.centerYAnchor constraintEqualToAnchor:loading.view.centerYAnchor],
        [spinner.trailingAnchor constraintEqualToAnchor:loading.view.trailingAnchor constant:-20]
    ]];
    [self presentViewController:loading animated:YES completion:nil];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        auto &audit = VMCore::AuditCore::getInstance();
        mach_port_t task = self.targetTask;

        auto modules = audit.classifyModules(task);

        NSMutableArray *diffs = [NSMutableArray array];
        for (auto &m : modules) {
            if (m.isSystem || m.isEncrypted) continue;

            auto diffEntries = audit.diffTextSegmentWithDisk(task, m);
            for (auto &d : diffEntries) {
                VMAuditDiffItem *item = [[VMAuditDiffItem alloc] init];
                item.moduleName = [NSString stringWithUTF8String:d.moduleName.c_str()];
                item.offset = d.offset;
                item.runtimeAddress = d.runtimeAddress;
                item.originalHex = [self hexFromBytes:d.originalBytes];
                item.currentHex = [self hexFromBytes:d.currentBytes];
                item.originalBytes = [NSData dataWithBytes:d.originalBytes.data()
                                                    length:d.originalBytes.size()];
                [diffs addObject:item];
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            self.diffItems = diffs;
            self.hasScanned = YES;
            [self.tableView reloadData];
            [loading dismissViewControllerAnimated:YES completion:^{
                if (diffs.count > 0) {
                    [self showToast:[NSString stringWithFormat:@"%@ %lu %@",
                        TR(@"Audit_Scan_Done"), (unsigned long)diffs.count, TR(@"Audit_TextDiff")]];
                } else {
                    [self showToast:TR(@"Audit_No_Diff")];
                }
            }];
        });
    });
}

#pragma mark - Dynamic Detection

- (void)onDynamicDetect {
    if (self.isMonitoring) {
        
        [self performDynamicComparison];
        return;
    }

    if (self.targetTask == MACH_PORT_NULL) {
        [self resolveTarget];
    }

    if (self.targetTask == MACH_PORT_NULL) {
        
        [self startPollingForProcess];
        return;
    }

    [self startDynamicMonitoring];
}

- (void)startPollingForProcess {
    self.isMonitoring = YES;
    [self updateDynamicButtonTitle];

    self.pollTimer = [NSTimer scheduledTimerWithTimeInterval:0.5
                                                      target:self
                                                    selector:@selector(pollForProcess)
                                                    userInfo:nil
                                                     repeats:YES];
}

- (void)pollForProcess {
    if (!self.bundleID) return;

    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0};
    size_t size = 0;
    if (sysctl(mib, 4, NULL, &size, NULL, 0) != 0) return;

    struct kinfo_proc *procs = (struct kinfo_proc *)malloc(size);
    if (!procs) return;
    if (sysctl(mib, 4, procs, &size, NULL, 0) != 0) { free(procs); return; }

    pid_t foundPid = 0;
    int count = (int)(size / sizeof(struct kinfo_proc));
    for (int i = 0; i < count; i++) {
        pid_t pid = procs[i].kp_proc.p_pid;
        if (pid <= 0) continue;

        char pathBuf[4096] = {0};
        proc_pidpath(pid, pathBuf, sizeof(pathBuf));
        NSString *fullPath = [NSString stringWithUTF8String:pathBuf];
        if (![fullPath containsString:@".app"]) continue;

        NSString *appDir = [fullPath stringByDeletingLastPathComponent];
        while (![appDir.pathExtension isEqualToString:@"app"] &&
               ![appDir isEqualToString:@"/"]) {
            appDir = [appDir stringByDeletingLastPathComponent];
        }
        NSString *plistPath = [appDir stringByAppendingPathComponent:@"Info.plist"];
        NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:plistPath];
        if (info && [info[@"CFBundleIdentifier"] caseInsensitiveCompare:self.bundleID] == NSOrderedSame) {
            foundPid = pid;
            break;
        }
    }
    free(procs);

    if (foundPid > 0) {
        [self stopPolling];
        self.targetPid = foundPid;
        mach_port_t task = MACH_PORT_NULL;
        if (task_for_pid(mach_task_self(), foundPid, &task) == KERN_SUCCESS) {
            self.targetTask = task;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                           (int64_t)(0.3 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                [self startDynamicMonitoring];
            });
        }
    }
}

- (void)stopPolling {
    if (self.pollTimer) {
        [self.pollTimer invalidate];
        self.pollTimer = nil;
    }
}

- (void)startDynamicMonitoring {
    auto &audit = VMCore::AuditCore::getInstance();
    auto modules = audit.classifyModules(self.targetTask);
    bool ok = audit.takeTextSnapshot(self.targetTask, modules);

    if (!ok) {
        [self showToast:TR(@"Audit_Snapshot_Fail")];
        self.isMonitoring = NO;
        [self updateDynamicButtonTitle];
        return;
    }

    self.isMonitoring = YES;
    [self updateDynamicButtonTitle];
    [self showToast:TR(@"Audit_Monitoring")];
}

- (void)performDynamicComparison {
    if (self.targetTask == MACH_PORT_NULL) {
        [self resolveTarget];
        if (self.targetTask == MACH_PORT_NULL) {
            [self showToast:TR(@"Audit_No_Process")];
            return;
        }
    }

    auto &audit = VMCore::AuditCore::getInstance();
    if (!audit.hasSnapshot()) {
        [self showToast:TR(@"Audit_No_Snapshot")];
        return;
    }

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        auto diffEntries = audit.diffTextSegmentWithSnapshot(self.targetTask);

        NSMutableArray *diffs = [NSMutableArray array];
        for (auto &d : diffEntries) {
            VMAuditDiffItem *item = [[VMAuditDiffItem alloc] init];
            item.moduleName = [NSString stringWithUTF8String:d.moduleName.c_str()];
            item.offset = d.offset;
            item.runtimeAddress = d.runtimeAddress;
            item.originalHex = [self hexFromBytes:d.originalBytes];
            item.currentHex = [self hexFromBytes:d.currentBytes];
            item.originalBytes = [NSData dataWithBytes:d.originalBytes.data()
                                                length:d.originalBytes.size()];
            [diffs addObject:item];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            self.diffItems = diffs;
            self.hasScanned = YES;
            self.isMonitoring = NO;
            VMCore::AuditCore::getInstance().clearSnapshot();
            [self updateDynamicButtonTitle];
            [self.tableView reloadData];

            if (diffs.count > 0) {
                [self showToast:[NSString stringWithFormat:@"%@ %lu %@",
                    TR(@"Audit_Scan_Done"), (unsigned long)diffs.count, TR(@"Audit_TextDiff")]];
            } else {
                [self showToast:TR(@"Audit_No_Diff")];
            }
        });
    });
}

- (void)updateDynamicButtonTitle {
    NSIndexSet *sections = [NSIndexSet indexSetWithIndex:kSectionInfo];
    [self.tableView reloadSections:sections withRowAnimation:UITableViewRowAnimationNone];
}

#pragma mark - TableView DataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return kSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case kSectionInfo: return 1;
        case kSectionDiffs: return self.diffItems.count;
        case kSectionExport: return self.diffItems.count > 0 ? 1 : 0;
        default: return 0;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case kSectionDiffs:
            return self.diffItems.count > 0
                ? [NSString stringWithFormat:@"%@ (%lu)", TR(@"Audit_TextDiff"),
                   (unsigned long)self.diffItems.count]
                : nil;
        default: return nil;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {

    if (indexPath.section == kSectionInfo) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"infoCell"];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                          reuseIdentifier:@"infoCell"];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            cell.backgroundColor = [UIColor clearColor];

            UIView *cardView = [[UIView alloc] init];
            cardView.tag = 1000;
            cardView.layer.cornerRadius = 14;
            cardView.backgroundColor = [self auditCardBackgroundColor];
            [cell.contentView addSubview:cardView];

            UILabel *titleLabel = [[UILabel alloc] init];
            titleLabel.tag = 1003;
            titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
            titleLabel.textColor = [UIColor labelColor];
            [cardView addSubview:titleLabel];

            UILabel *bundleLabel = [[UILabel alloc] init];
            bundleLabel.tag = 1004;
            bundleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
            bundleLabel.textColor = [self auditSecondaryTextColor];
            [cardView addSubview:bundleLabel];

            UILabel *statusLabel = [[UILabel alloc] init];
            statusLabel.tag = 1005;
            statusLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
            statusLabel.textAlignment = NSTextAlignmentCenter;
            statusLabel.layer.cornerRadius = 8;
            statusLabel.layer.masksToBounds = YES;
            [cardView addSubview:statusLabel];

            UIButton *staticBtn = [UIButton buttonWithType:UIButtonTypeSystem];
            staticBtn.tag = 1001;
            staticBtn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
            staticBtn.layer.cornerRadius = 10;
            staticBtn.layer.borderWidth = 0;
            [staticBtn addTarget:self action:@selector(onStaticDetect) forControlEvents:UIControlEventTouchUpInside];
            [cardView addSubview:staticBtn];

            UIButton *dynamicBtn = [UIButton buttonWithType:UIButtonTypeSystem];
            dynamicBtn.tag = 1002;
            dynamicBtn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
            dynamicBtn.layer.cornerRadius = 10;
            dynamicBtn.layer.borderWidth = 0;
            [dynamicBtn addTarget:self action:@selector(onDynamicDetect) forControlEvents:UIControlEventTouchUpInside];
            [cardView addSubview:dynamicBtn];
        }

        NSString *status = self.targetTask != MACH_PORT_NULL
            ? [NSString stringWithFormat:@"PID: %d", self.targetPid]
            : TR(@"Audit_Not_Running");

        UIView *cardView = [cell.contentView viewWithTag:1000];
        UILabel *titleLabel = [cardView viewWithTag:1003];
        UILabel *bundleLabel = [cardView viewWithTag:1004];
        UILabel *statusLabel = [cardView viewWithTag:1005];
        UIButton *staticBtn = [cardView viewWithTag:1001];
        UIButton *dynamicBtn = [cardView viewWithTag:1002];

        cardView.backgroundColor = [self auditCardBackgroundColor];
        titleLabel.text = self.appName ?: TR(@"App_Unknown");
        bundleLabel.text = self.bundleID ?: @"";
        statusLabel.text = status;

        UIColor *primaryActionColor = [self auditPrimaryActionColor];
        staticBtn.backgroundColor = [primaryActionColor colorWithAlphaComponent:0.12];
        [staticBtn setTitleColor:primaryActionColor forState:UIControlStateNormal];

        UIColor *secondaryActionColor = [self auditSecondaryActionColor];
        dynamicBtn.backgroundColor = [secondaryActionColor colorWithAlphaComponent:0.12];
        [dynamicBtn setTitleColor:secondaryActionColor forState:UIControlStateNormal];

        BOOL isRunning = (self.targetTask != MACH_PORT_NULL);
        statusLabel.backgroundColor = isRunning
            ? [[UIColor systemGreenColor] colorWithAlphaComponent:0.14]
            : [self auditStatusIdleBackgroundColor];
        statusLabel.textColor = isRunning
            ? [UIColor systemGreenColor]
            : [self auditStatusIdleTextColor];

        CGFloat contentW = tableView.bounds.size.width - 32;
        cardView.frame = CGRectMake(16, 8, contentW, 120);
        titleLabel.frame = CGRectMake(14, 12, contentW - 28, 22);
        bundleLabel.frame = CGRectMake(14, 38, contentW - 140, 18);
        statusLabel.frame = CGRectMake(contentW - 104, 34, 90, 24);
        CGFloat buttonW = floor((contentW - 12) / 2.0);
        staticBtn.frame = CGRectMake(14, 72, buttonW - 8, 34);
        dynamicBtn.frame = CGRectMake(CGRectGetMaxX(staticBtn.frame) + 12, 66, buttonW, 36);
        dynamicBtn.frame = CGRectMake(CGRectGetMaxX(staticBtn.frame) + 12, 72, buttonW - 8, 34);
        [staticBtn setTitle:TR(@"Audit_Static") forState:UIControlStateNormal];
        [dynamicBtn setTitle:(self.isMonitoring ? TR(@"Audit_Dynamic_Scan") : TR(@"Audit_Dynamic"))
                    forState:UIControlStateNormal];
        return cell;
    }

    if (indexPath.section == kSectionDiffs) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"diffCell"];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                          reuseIdentifier:@"diffCell"];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
        VMAuditDiffItem *item = self.diffItems[indexPath.row];
        cell.textLabel.text = [NSString stringWithFormat:@"%@ +0x%llX",
                               item.moduleName, item.offset];
        cell.textLabel.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightRegular];

        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@: %@\n%@: %@",
            TR(@"Audit_Original"), item.originalHex,
            TR(@"Audit_Current"), item.currentHex];
        cell.detailTextLabel.numberOfLines = 2;
        cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
        cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
        return cell;
    }

    if (indexPath.section == kSectionExport) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"exportCell"];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                          reuseIdentifier:@"exportCell"];
            cell.textLabel.textAlignment = NSTextAlignmentCenter;
            cell.textLabel.textColor = [UIColor systemBlueColor];
        }
        cell.textLabel.text = TR(@"Audit_Export");
        return cell;
    }

    return [[UITableViewCell alloc] init];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == kSectionInfo) {
        return 136;
    }
    if (indexPath.section == kSectionDiffs) {
        return 74;
    }
    return 44;
}

#pragma mark - TableView Delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == kSectionDiffs) {
        [self showDiffActionSheet:self.diffItems[indexPath.row]];
    } else if (indexPath.section == kSectionExport) {
        [self exportReport];
    }
}

#pragma mark - Diff Actions

- (void)showDiffActionSheet:(VMAuditDiffItem *)item {
    UIAlertController *sheet = [UIAlertController
        alertControllerWithTitle:[NSString stringWithFormat:@"%@ +0x%llX",
                                  item.moduleName, item.offset]
                         message:nil
                  preferredStyle:UIAlertControllerStyleActionSheet];

    [sheet addAction:[UIAlertAction actionWithTitle:TR(@"Btn_Restore")
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            [self restoreDiffItem:item];
        }]];

    [sheet addAction:[UIAlertAction actionWithTitle:TR(@"Btn_Copy")
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            NSString *info = [NSString stringWithFormat:
                @"%@ +0x%llX\n%@: %@\n%@: %@",
                item.moduleName, item.offset,
                TR(@"Audit_Original"), item.originalHex,
                TR(@"Audit_Current"), item.currentHex];
            [UIPasteboard generalPasteboard].string = info;
            [self showToast:TR(@"Btn_Copy")];
        }]];

    [sheet addAction:[UIAlertAction actionWithTitle:TR(@"Btn_Cancel")
        style:UIAlertActionStyleCancel handler:nil]];

    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        sheet.popoverPresentationController.sourceView = self.tableView;
        sheet.popoverPresentationController.sourceRect =
            CGRectMake(self.tableView.center.x, self.tableView.center.y, 1, 1);
    }

    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)restoreDiffItem:(VMAuditDiffItem *)item {
    if (self.targetTask == MACH_PORT_NULL) {
        [self showToast:TR(@"Audit_No_Process")];
        return;
    }

    std::vector<uint8_t> original((uint8_t *)item.originalBytes.bytes,
        (uint8_t *)item.originalBytes.bytes + item.originalBytes.length);

    bool ok = VMCore::AuditCore::getInstance().restoreBytes(
        self.targetTask, item.runtimeAddress, original);

    [self showToast:ok ? TR(@"Audit_Restored") : TR(@"Audit_Restore_Fail")];
}

#pragma mark - Export

- (void)exportReport {
    NSString *version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"";
    NSMutableString *report = [NSMutableString string];
    [report appendFormat:@"=== %@ ===\n", TR(@"Audit_Title")];
    [report appendFormat:@"VansonMod v%@\n", version];
    [report appendFormat:@"%@: %@\n", TR(@"Audit_Target"), self.appName];
    [report appendFormat:@"Bundle ID: %@\n", self.bundleID];
    [report appendFormat:@"PID: %d\n\n", self.targetPid];

    [report appendFormat:@"--- %@ (%lu) ---\n", TR(@"Audit_TextDiff"),
     (unsigned long)self.diffItems.count];
    for (VMAuditDiffItem *d in self.diffItems) {
        [report appendFormat:@"  %@ +0x%llX\n  %@: %@\n  %@: %@\n",
         d.moduleName, d.offset,
         TR(@"Audit_Original"), d.originalHex,
         TR(@"Audit_Current"), d.currentHex];
    }

    NSString *fileName = [NSString stringWithFormat:@"%@.txt", self.bundleID ?: @"report"];
    NSString *filePath = [NSTemporaryDirectory() stringByAppendingPathComponent:fileName];
    [report writeToFile:filePath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSURL *fileURL = [NSURL fileURLWithPath:filePath];

    UIActivityViewController *share = [[UIActivityViewController alloc]
        initWithActivityItems:@[fileURL] applicationActivities:nil];
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        share.popoverPresentationController.sourceView = self.view;
        share.popoverPresentationController.sourceRect =
            CGRectMake(self.view.center.x, self.view.center.y, 1, 1);
    }
    [self presentViewController:share animated:YES completion:nil];
}

#pragma mark - Helpers

- (NSString *)hexFromBytes:(const std::vector<uint8_t> &)bytes {
    NSMutableString *hex = [NSMutableString string];
    for (size_t i = 0; i < bytes.size(); i++) {
        if (i > 0) [hex appendString:@" "];
        [hex appendFormat:@"%02X", bytes[i]];
    }
    return hex;
}

- (void)showToast:(NSString *)msg {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:nil message:msg
                  preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:alert animated:YES completion:nil];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [alert dismissViewControllerAnimated:YES completion:nil];
    });
}

@end
