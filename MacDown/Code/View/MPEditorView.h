//
//  MPEditorView.h
//  MacDown
//
//  Created by Tzu-ping Chung  on 30/8.
//  Copyright (c) 2014 Tzu-ping Chung . All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface MPEditorView : NSTextView

@property BOOL scrollsPastEnd;
// Rango del "bloque activo" de la selección conectada; se dibuja un recuadro fino
// alrededor (length 0 = sin recuadro). Lo fija MPDocument según el mapeo por bloque.
@property (nonatomic) NSRange linkedBlockRange;
- (NSRect)contentRect;

@end
