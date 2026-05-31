#import "./VMGlobalBackupViewController.h"
#import "../patch/VMBackupListViewController.h"
#import "../../utils/managers/VMBackupManager.h"
#import "include/VMLocalization.h"
#import "../../utils/helpers/VMUIHelper.h"
#define TR(key) ([[VMLocalization shared] localizedString:key])
@interface VMGlobalBackupViewController ()
@property (nonatomic, strong) NSMutableArray<NSString *> *backupFolders;
@end
@implementation VMGlobalBackupViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = TR(@"Backups_Global_Title");

    self.navigationItem.rightBarButtonItem = nil;

    [VMUIHelper addFixedFooterTo:self forTableView:self.tableView];

    [self loadBackupFolders];
}

- (void)loadBackupFolders {
    NSString *rootPath = [[VMBackupManager shared] myBackupFolder];
    NSFileManager *fm = [NSFileManager defaultManager];
    
    NSError *err;
    NSArray *contents = [fm contentsOfDirectoryAtPath:rootPath error:&err];
    if (!contents) {
        self.backupFolders = [NSMutableArray array];
        return;
    }
    
    NSMutableArray *dirs = [NSMutableArray array];
    for (NSString *name in contents) {
        if ([name hasPrefix:@"."]) continue; 
        
        NSString *fullPath = [rootPath stringByAppendingPathComponent:name];
        BOOL isDir = NO;
        if ([fm fileExistsAtPath:fullPath isDirectory:&isDir] && isDir) {
            [dirs addObject:name];
        }
    }
    
    [dirs sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    self.backupFolders = dirs;
    [self.tableView reloadData];
    
    if (self.backupFolders.count == 0) {
        UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(0,0,self.view.bounds.size.width, 50)];
        lbl.text = TR(@"Backups_Empty");
        lbl.textAlignment = NSTextAlignmentCenter;
        lbl.textColor = [UIColor systemGrayColor];
        self.tableView.tableFooterView = lbl;
    } else {
        self.tableView.tableFooterView = nil;
    }
}

- (NSString *)formatAppInfoForFolder:(NSString *)folderName {
    NSString *bid = folderName;
    
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    id proxy = [NSClassFromString(@"LSApplicationProxy") performSelector:NSSelectorFromString(@"applicationProxyForIdentifier:") withObject:bid];
    
    if (proxy) {
        NSString *name = [proxy performSelector:NSSelectorFromString(@"localizedName")];
        NSString *ver = [proxy performSelector:NSSelectorFromString(@"shortVersionString")];
        if (!name) name = bid;
        if (!ver) ver = @"?";
        
        return [NSString stringWithFormat:@"%@ - v%@\n%@", name, ver, bid];
    }
    #pragma clang diagnostic pop
    
    return bid;
}

#pragma mark - TableView
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.backupFolders.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cid = @"backFolder";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cid];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:cid];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    
    NSString *folderName = self.backupFolders[indexPath.row];
    cell.textLabel.numberOfLines = 2;
    cell.textLabel.text = [self formatAppInfoForFolder:folderName];
    cell.textLabel.font = [UIFont systemFontOfSize:14];
    cell.imageView.image = [UIImage systemImageNamed:@"folder"];
    cell.imageView.tintColor = [UIColor systemGrayColor];
    
    NSString *path = [[[VMBackupManager shared] myBackupFolder] stringByAppendingPathComponent:folderName];
    NSArray *subs = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:path error:nil];
    NSPredicate *pred = [NSPredicate predicateWithFormat:@"NOT (self BEGINSWITH '.')"];
    subs = [subs filteredArrayUsingPredicate:pred];
    
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)subs.count];
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    NSString *folderName = self.backupFolders[indexPath.row];
    
    NSString *installedPath = [[VMBackupManager shared] getDataPathForBundleID:folderName];
    if (!installedPath) {
    }
    
    VMBackupListViewController *vc = [[VMBackupListViewController alloc] init];
    vc.appName = folderName; 
    vc.bid = folderName;     
    
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        NSString *appName = self.backupFolders[indexPath.row];
        NSString *path = [[[VMBackupManager shared] myBackupFolder] stringByAppendingPathComponent:appName];
        
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
        [self.backupFolders removeObjectAtIndex:indexPath.row];
        [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
    }
}

@end
