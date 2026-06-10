//
//  MPToolbarController.h
//  MacDown
//
//  Created by Niklas Berglund on 2017-02-12.
//  Copyright © 2017 Tzu-ping Chung . All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MPDocument.h"

@interface MPToolbarController : NSObject<NSToolbarDelegate>

@property (weak) IBOutlet MPDocument *document;

/**
 * Update the toolbar to reflect the editor's visibility. When the editor is
 * hidden (preview-only layout) all text-formatting items are removed, since
 * they have no effect without an editor to act on.
 */
- (void)updateForEditorVisible:(BOOL)editorVisible;

@end
