//
//  MPEditorView.m
//  MacDown
//
//  Created by Tzu-ping Chung  on 30/8.
//  Copyright (c) 2014 Tzu-ping Chung . All rights reserved.
//

#import "MPEditorView.h"


NS_INLINE BOOL MPAreRectsEqual(NSRect r1, NSRect r2)
{
    return (r1.origin.x == r2.origin.x && r1.origin.y == r2.origin.y
            && r1.size.width == r2.size.width
            && r1.size.height == r2.size.height);
}


@interface MPEditorView ()

@property NSRect contentRect;
@property CGFloat trailingHeight;

@end


@implementation MPEditorView

#pragma mark - Accessors

@synthesize contentRect = _contentRect;
@synthesize scrollsPastEnd = _scrollsPastEnd;

- (BOOL)scrollsPastEnd
{
    @synchronized(self) {
        return _scrollsPastEnd;
    }
}

- (void)awakeFromNib {
    [self registerForDraggedTypes:[NSArray arrayWithObjects: NSDragPboard, nil]];
    [super awakeFromNib];
}

- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender {
    NSPasteboard *pboard;
    NSDragOperation sourceDragMask;
    
    sourceDragMask = [sender draggingSourceOperationMask];
    pboard = [sender draggingPasteboard];
    
    if ([pboard canReadItemWithDataConformingToTypes:[NSArray arrayWithObjects:@"public.jpeg", nil]]) {
        if (sourceDragMask & NSDragOperationLink) {
            return NSDragOperationLink;
        } else if (sourceDragMask & NSDragOperationCopy) {
            return NSDragOperationCopy;
        }
    }
    
    return NSDragOperationNone;
}

- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender {
    NSPasteboard *pboard;
    NSDragOperation sourceDragMask;
    
    sourceDragMask = [sender draggingSourceOperationMask];
    pboard = [sender draggingPasteboard];
    
    if ( [[pboard types] containsObject:NSFilenamesPboardType] ) {
        NSArray *files = [pboard propertyListForType:NSFilenamesPboardType];
        
        /* Load data of file. */
        NSError *error;
        NSData *fileData = [NSData dataWithContentsOfFile: files[0]
                                                  options: NSMappedRead
                                                    error: &error];
        if (!error) {
            // convert to base64 representation
            NSString *dataString = [fileData base64Encoding];
            
            // insert into text.
            NSInteger insertionPoint = [[[self selectedRanges] objectAtIndex:0] rangeValue].location;
            [self setString:[NSString stringWithFormat:@"%@![](data:image/jpeg;base64,%@)%@", [[self string] substringToIndex:insertionPoint], dataString, [[self string] substringFromIndex:insertionPoint]]];
            [self didChangeText];
        } else {
            return NO;
        }
    }
    return YES;
}


- (void)setScrollsPastEnd:(BOOL)scrollsPastEnd
{
    @synchronized(self) {
        _scrollsPastEnd = scrollsPastEnd;
        if (scrollsPastEnd)
        {
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                [self updateContentGeometry];
            }];
        }
        else
        {
            // Clears contentRect to fallback to self.frame.
            self.contentRect = NSZeroRect;
        }
    }
}

- (NSRect)contentRect
{
    @synchronized(self) {
        if (MPAreRectsEqual(_contentRect, NSZeroRect))
            return self.frame;
        return _contentRect;
    }
}

- (void)setContentRect:(NSRect)rect
{
    @synchronized(self) {
        _contentRect = rect;
    }
}

- (void)setFrameSize:(NSSize)newSize
{
    if (self.scrollsPastEnd)
    {
        CGFloat ch = self.contentRect.size.height;
        CGFloat eh = self.enclosingScrollView.contentSize.height;
        CGFloat offset = ch < eh ? ch : eh;
        offset -= self.trailingHeight + 2 * self.textContainerInset.height;
        if (offset > 0)
            newSize.height += offset;
    }
    [super setFrameSize:newSize];
}

/** Overriden to perform extra operation on initial text setup.
 *
 * When we first launch the editor, -didChangeText will *not* be called, so we
 * override this to perform required resizing. The -updateContentRect is wrapped
 * inside an NSOperation to be invoked later since the layout manager will not
 * be invoked when the text is first set.
 *
 * @see didChangeText
 * @see updateContentRect
 */
- (void)setString:(NSString *)string
{
    [super setString:string];
    if (self.scrollsPastEnd)
    {
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            [self updateContentGeometry];
        }];
    }
}


#pragma mark - Overrides

/** Overriden to perform extra operation on text change.
 *
 * Updates content height, and invoke the resizing method to apply it.
 *
 * @see updateContentRect
 */
- (void)didChangeText
{
    [super didChangeText];
    if (self.scrollsPastEnd)
        [self updateContentGeometry];
}


#pragma mark - Private

- (void)updateContentGeometry
{
    static NSCharacterSet *visibleCharacterSet = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSCharacterSet *ws = [NSCharacterSet whitespaceAndNewlineCharacterSet];
        visibleCharacterSet = ws.invertedSet;
    });

    NSString *content = self.string;
    NSLayoutManager *manager = self.layoutManager;
    NSTextContainer *container = self.textContainer;
    NSRect r = [manager usedRectForTextContainer:container];

    NSRange lastRange = [content rangeOfCharacterFromSet:visibleCharacterSet
                                                 options:NSBackwardsSearch];
    NSRect junkRect = r;
    if (lastRange.location != NSNotFound)
    {
        NSUInteger contentLength = content.length;
        NSUInteger firstJunkLocation = lastRange.location + lastRange.length;
        NSRange junkRange = NSMakeRange(firstJunkLocation,
                                        contentLength - firstJunkLocation);
        junkRect = [manager boundingRectForGlyphRange:junkRange
                                      inTextContainer:container];
    }
    self.trailingHeight = junkRect.size.height;

    NSSize inset = self.textContainerInset;
    r.size.width += 2 * inset.width;
    r.size.height += 2 * inset.height;
    self.contentRect = r;

    [self setFrameSize:self.frame.size];    // Force size update.
}


#pragma mark - Selección conectada (recuadro del bloque activo)

@synthesize linkedBlockRange = _linkedBlockRange;

- (void)setLinkedBlockRange:(NSRange)range
{
    if (NSEqualRanges(range, _linkedBlockRange))
        return;
    _linkedBlockRange = range;
    self.needsDisplay = YES;
}

- (void)drawRect:(NSRect)dirtyRect
{
    [super drawRect:dirtyRect];
    if (_linkedBlockRange.length == 0 || _linkedBlockRange.location == NSNotFound)
        return;
    if (NSMaxRange(_linkedBlockRange) > self.string.length)
        return;

    NSLayoutManager *lm = self.layoutManager;
    NSTextContainer *tc = self.textContainer;
    NSRange glyphRange =
        [lm glyphRangeForCharacterRange:_linkedBlockRange actualCharacterRange:NULL];
    NSRect r = [lm boundingRectForGlyphRange:glyphRange inTextContainer:tc];
    NSPoint origin = self.textContainerOrigin;
    r.origin.x += origin.x;
    r.origin.y += origin.y;

    // Aire interior generoso (sacrificando margen exterior). En párrafos multilínea
    // el rect del texto llena el ancho del contenedor, así que las verticales de las
    // esquinas caerían en los márgenes; se clampa a ambos bordes del área visible
    // para que se vean siempre.
    NSRect box = NSInsetRect(r, -8.0, -5.0);
    CGFloat viewW = self.bounds.size.width;
    CGFloat minX = MAX(2.0, NSMinX(box));
    CGFloat maxX = MIN(viewW - 2.0, NSMaxX(box));
    CGFloat minY = NSMinY(box), maxY = NSMaxY(box);
    if (maxX - minX < 12.0 || maxY - minY < 8.0)
        return;

    // ¿bloque grande? cuenta líneas visuales (fragmentos) hasta el umbral.
    NSUInteger lines = 0, idx = glyphRange.location, maxIdx = NSMaxRange(glyphRange);
    NSRange lineRange;
    while (idx < maxIdx)
    {
        [lm lineFragmentRectForGlyphAtIndex:idx effectiveRange:&lineRange];
        idx = NSMaxRange(lineRange);
        if (++lines >= 10)
            break;
    }
    BOOL big = (lines >= 10);

    CGFloat corX = MIN(30.0, (maxX - minX) * 0.45);
    CGFloat corY = MIN(30.0, (maxY - minY) * 0.45);

    NSBezierPath *path = [NSBezierPath bezierPath];
    path.lineWidth = 2.0;
    path.lineCapStyle = NSLineCapStyleRound;
    // Cuatro esquinas en L.
    [path moveToPoint:NSMakePoint(minX, minY)]; [path lineToPoint:NSMakePoint(minX + corX, minY)];
    [path moveToPoint:NSMakePoint(minX, minY)]; [path lineToPoint:NSMakePoint(minX, minY + corY)];
    [path moveToPoint:NSMakePoint(maxX, minY)]; [path lineToPoint:NSMakePoint(maxX - corX, minY)];
    [path moveToPoint:NSMakePoint(maxX, minY)]; [path lineToPoint:NSMakePoint(maxX, minY + corY)];
    [path moveToPoint:NSMakePoint(minX, maxY)]; [path lineToPoint:NSMakePoint(minX + corX, maxY)];
    [path moveToPoint:NSMakePoint(minX, maxY)]; [path lineToPoint:NSMakePoint(minX, maxY - corY)];
    [path moveToPoint:NSMakePoint(maxX, maxY)]; [path lineToPoint:NSMakePoint(maxX - corX, maxY)];
    [path moveToPoint:NSMakePoint(maxX, maxY)]; [path lineToPoint:NSMakePoint(maxX, maxY - corY)];
    // Trazo central por lado solo en bloques grandes.
    if (big)
    {
        CGFloat midX = (minX + maxX) / 2, midY = (minY + maxY) / 2, dl = 34.0;
        [path moveToPoint:NSMakePoint(midX - dl/2, minY)]; [path lineToPoint:NSMakePoint(midX + dl/2, minY)];
        [path moveToPoint:NSMakePoint(midX - dl/2, maxY)]; [path lineToPoint:NSMakePoint(midX + dl/2, maxY)];
        [path moveToPoint:NSMakePoint(minX, midY - dl/2)]; [path lineToPoint:NSMakePoint(minX, midY + dl/2)];
        [path moveToPoint:NSMakePoint(maxX, midY - dl/2)]; [path lineToPoint:NSMakePoint(maxX, midY + dl/2)];
    }

    static int dbgN = 0;   // [debug temporal]
    if (dbgN < 30)
    {
        FILE *f = fopen("/tmp/macdown-draw.log", "a");
        if (f)
        {
            fprintf(f, "#%d minX=%.0f maxX=%.0f minY=%.0f maxY=%.0f corX=%.0f corY=%.0f "
                       "viewW=%.0f big=%d dirty={%.0f,%.0f,%.0f,%.0f}\n",
                    dbgN, minX, maxX, minY, maxY, corX, corY, viewW, big,
                    dirtyRect.origin.x, dirtyRect.origin.y,
                    dirtyRect.size.width, dirtyRect.size.height);
            fclose(f);
        }
        dbgN++;
    }

    NSColor *c = self.insertionPointColor
        ?: [NSColor colorWithRed:0.47 green:0.63 blue:1.0 alpha:1.0];
    [[c colorWithAlphaComponent:0.92] setStroke];
    [path stroke];
}

@end
