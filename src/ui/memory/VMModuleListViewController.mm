#import "../memory/VMModuleListViewController.h"
#import "include/VMLocalization.h"
#import "../../utils/helpers/VMUIHelper.h"
#define TR(key) ([[VMLocalization shared] localizedString:key])
@interface VMModuleListViewController () <UITableViewDelegate, UITableViewDataSource, UISearchBarDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) NSArray<VMModuleInfo *> *allModules;
@property (nonatomic, strong) NSArray<VMModuleInfo *> *displayedModules;
@end
@implementation VMModuleListViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = TR(@"Patch_Select_Msg"); 
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    
    [self setupUI];
    [self loadData];
}

- (void)setupUI {
    self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 50)];
    self.searchBar.placeholder = TR(@"Patch_Search_Placeholder");
    self.searchBar.delegate = self;
    self.searchBar.searchBarStyle = UISearchBarStyleMinimal;

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.tableHeaderView = self.searchBar;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    [self.view addSubview:self.tableView];

    [VMUIHelper addFixedFooterTo:self forTableView:self.tableView];
}

- (void)loadData {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        self.allModules = [[VMMemoryEngine shared] loadRemoteModules];

        self.allModules = [self.allModules sortedArrayUsingComparator:^NSComparisonResult(VMModuleInfo *obj1, VMModuleInfo *obj2) {
            return [@(obj2.size) compare:@(obj1.size)];
        }];

        self.displayedModules = self.allModules;

        dispatch_async(dispatch_get_main_queue(), ^{
            [self.tableView reloadData];
        });
    });
}

#pragma mark - Search Logic
- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    if (searchText.length == 0) {
        self.displayedModules = self.allModules;
    } else {
        NSPredicate *pred = [NSPredicate predicateWithFormat:@"name CONTAINS[c] %@", searchText];
        self.displayedModules = [self.allModules filteredArrayUsingPredicate:pred];
    }
    [self.tableView reloadData];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
}

#pragma mark - TableView Delegate
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2; 
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 1;
    return self.displayedModules.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return nil;
    return [NSString stringWithFormat:TR(@"Mod_List_Title"), (unsigned long)self.displayedModules.count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cid = @"modCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cid];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cid];
    }
    
    if (indexPath.section == 0) {
        cell.textLabel.text = @"Auto Search";
        cell.textLabel.textColor = [UIColor systemBlueColor];
        cell.textLabel.font = [UIFont boldSystemFontOfSize:16];
        cell.detailTextLabel.text = TR(@"Mod_Search_All_Regions");
        cell.imageView.image = [UIImage systemImageNamed:@"square.stack.3d.up"];
    } else {
        VMModuleInfo *info = self.displayedModules[indexPath.row];
        cell.textLabel.text = info.name;
        cell.textLabel.textColor = [UIColor labelColor];
        cell.textLabel.font = [UIFont systemFontOfSize:16];
        
        cell.detailTextLabel.text = [NSString stringWithFormat:@"0x%llX (Size: %@)", info.loadAddress, [NSByteCountFormatter stringFromByteCount:info.size countStyle:NSByteCountFormatterCountStyleMemory]];
        cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
        
        if (info.loadAddress == [VMMemoryEngine shared].mainModuleAddress) {
            cell.imageView.image = [UIImage systemImageNamed:@"star.circle.fill"];
            cell.imageView.tintColor = [UIColor systemOrangeColor];
        } else {
            cell.imageView.image = [UIImage systemImageNamed:@"cube.box"];
            cell.imageView.tintColor = [UIColor systemGrayColor];
        }
    }
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    VMModuleInfo *selected = nil;
    if (indexPath.section == 1) {
        selected = self.displayedModules[indexPath.row];
    }
    
    if (self.selectionHandler) {
        self.selectionHandler(selected);
    }
    
    [self.navigationController popViewControllerAnimated:YES];
}

@end
