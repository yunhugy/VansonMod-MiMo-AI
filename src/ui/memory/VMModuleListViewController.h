#import <UIKit/UIKit.h>
#import "include/VMMemoryEngine.h"

typedef void (^VMModuleSelectionHandler)(VMModuleInfo * _Nullable selectedModule);

@interface VMModuleListViewController : UIViewController

@property (nonatomic, copy, nullable) VMModuleSelectionHandler selectionHandler;

@end
