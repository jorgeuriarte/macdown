//
//  MPDocument.m
//  MacDown
//
//  Created by Tzu-ping Chung  on 6/06/2014.
//  Copyright (c) 2014 Tzu-ping Chung . All rights reserved.
//

#import "MPDocument.h"
#import <WebKit/WebKit.h>
#import <JJPluralForm/JJPluralForm.h>
#import "cmark_gfm_rendering.h"
#import "HGMarkdownHighlighter.h"
#import "MPUtilities.h"
#import "MPAutosaving.h"
#import "NSColor+HTML.h"
#import "NSDocumentController+Document.h"
#import "NSPasteboard+Types.h"
#import "NSString+Lookup.h"
#import "NSTextView+Autocomplete.h"
#import "DOMNode+Text.h"
#import "MPPreferences.h"
#import "MPDocumentSplitView.h"
#import "MPEditorView.h"
#import "MPRenderer.h"
#import "MPPreferencesViewController.h"
#import "MPEditorPreferencesViewController.h"
#import "MPExportPanelAccessoryViewController.h"
#import "MPMathJaxListener.h"
#import "WebView+WebViewPrivateHeaders.h"
#import "MPToolbarController.h"
#import "MPGlobals.h"
#import <JavaScriptCore/JavaScriptCore.h>

static NSString * const kMPDefaultAutosaveName = @"Untitled";

// Editor font-zoom bounds and the default size used by "Actual Size".
// kMPDefaultEditorFontPointSize mirrors the value in MPPreferences.m (not
// exported), kept in sync here intentionally.
static CGFloat const kMPEditorFontPointSizeDefault = 14.0;
static CGFloat const kMPEditorFontPointSizeMin = 6.0;
static CGFloat const kMPEditorFontPointSizeMax = 72.0;


NS_INLINE NSString *MPEditorPreferenceKeyWithValueKey(NSString *key)
{
    if (!key.length)
        return @"editor";
    NSString *first = [[key substringToIndex:1] uppercaseString];
    NSString *rest = [key substringFromIndex:1];
    return [NSString stringWithFormat:@"editor%@%@", first, rest];
}

NS_INLINE NSDictionary *MPEditorKeysToObserve()
{
    static NSDictionary *keys = nil;
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        keys = @{@"automaticDashSubstitutionEnabled": @NO,
                 @"automaticDataDetectionEnabled": @NO,
                 @"automaticQuoteSubstitutionEnabled": @NO,
                 @"automaticSpellingCorrectionEnabled": @NO,
                 @"automaticTextReplacementEnabled": @NO,
                 @"continuousSpellCheckingEnabled": @NO,
                 @"enabledTextCheckingTypes": @(NSTextCheckingAllTypes),
                 @"grammarCheckingEnabled": @NO};
    });
    return keys;
}

NS_INLINE NSSet *MPEditorPreferencesToObserve()
{
    static NSSet *keys = nil;
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        keys = [NSSet setWithObjects:
            @"editorBaseFontInfo", @"extensionFootnotes",
            @"editorHorizontalInset", @"editorVerticalInset",
            @"editorWidthLimited", @"editorMaximumWidth", @"editorLineSpacing",
            @"editorOnRight", @"editorStyleName", @"editorShowWordCount",
            @"editorScrollsPastEnd", nil
        ];
    });
    return keys;
}

NS_INLINE NSString *MPRectStringForAutosaveName(NSString *name)
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *key = [NSString stringWithFormat:@"NSWindow Frame %@", name];
    NSString *rectString = [defaults objectForKey:key];
    return rectString;
}

NS_INLINE NSColor *MPGetWebViewBackgroundColor(WebView *webview)
{
    DOMDocument *doc = webview.mainFrameDocument;
    DOMNodeList *nodes = [doc getElementsByTagName:@"body"];
    if (!nodes.length)
        return nil;

    id bodyNode = [nodes item:0];
    DOMCSSStyleDeclaration *style = [doc getComputedStyle:bodyNode
                                            pseudoElement:nil];
    return [NSColor colorWithHTMLName:[style backgroundColor]];
}


@implementation NSURL (Convert)

- (NSString *)absoluteBaseURLString
{
    // Remove fragment (#anchor) and query string.
    NSString *base = self.absoluteString;
    base = [base componentsSeparatedByString:@"?"].firstObject;
    base = [base componentsSeparatedByString:@"#"].firstObject;
    return base;
}

@end


@implementation WebView (Shortcut)

- (NSScrollView *)enclosingScrollView
{
    return self.mainFrame.frameView.documentView.enclosingScrollView;
}

@end


@implementation MPPreferences (CmarkGFM)

// Returns a bitmask used for change-detection in parseIfPreferencesChanged.
- (int)extensionFlags
{
    int flags = 0;
    if (self.extensionAutolink)       flags |= (1 << 0);
    if (self.extensionFootnotes)      flags |= (1 << 1);
    if (self.extensionStrikethough)   flags |= (1 << 2);
    if (self.extensionTables)         flags |= (1 << 3);
    if (self.htmlTaskList)            flags |= (1 << 4);
    if (self.htmlHardWrap)            flags |= (1 << 5);
    return flags;
}

- (NSArray<NSString *> *)cmarkExtensionNames
{
    NSMutableArray *names = [NSMutableArray array];
    if (self.extensionTables)
        [names addObject:@"table"];
    if (self.extensionStrikethough)
        [names addObject:@"strikethrough"];
    if (self.extensionAutolink)
        [names addObject:@"autolink"];
    if (self.htmlTaskList)
        [names addObject:@"tasklist"];
    [names addObject:@"tagfilter"];
    return names;
}

- (MPCmarkRenderFlags)cmarkRenderFlags
{
    MPCmarkRenderFlags flags = MPCmarkRenderFlagNone;
    if (self.htmlLineNumbers)
        flags |= MPCmarkRenderFlagLineNumbers;
    if (self.htmlCodeBlockAccessory == MPCodeBlockAccessoryCustom)
        flags |= MPCmarkRenderFlagBlockInformation;
    return flags;
}
@end


@interface MPDocument ()
    <NSSplitViewDelegate, NSTextViewDelegate,
#if __MAC_OS_X_VERSION_MAX_ALLOWED >= 101100
     WebEditingDelegate, WebFrameLoadDelegate, WebPolicyDelegate, WebResourceLoadDelegate,
#endif
     WKNavigationDelegate, WKScriptMessageHandler,
     MPAutosaving, MPRendererDataSource, MPRendererDelegate>

typedef NS_ENUM(NSUInteger, MPWordCountType) {
    MPWordCountTypeWord,
    MPWordCountTypeCharacter,
    MPWordCountTypeCharacterNoSpaces,
};

typedef NS_ENUM(NSInteger, MPDefaultLayout) {
    MPDefaultLayoutBoth = 0,
    MPDefaultLayoutEditorOnly = 1,
    MPDefaultLayoutPreviewOnly = 2,
};

@property (weak) IBOutlet NSToolbar *toolbar;
@property (weak) IBOutlet MPDocumentSplitView *splitView;
@property (weak) IBOutlet NSView *editorContainer;
@property (unsafe_unretained) IBOutlet MPEditorView *editor;
@property (weak) IBOutlet NSLayoutConstraint *editorPaddingBottom;
@property (weak) IBOutlet WebView *preview;
@property (weak) IBOutlet NSPopUpButton *wordCountWidget;
@property (strong) IBOutlet MPToolbarController *toolbarController;
@property (copy, nonatomic) NSString *autosaveName;
@property (strong) HGMarkdownHighlighter *highlighter;
@property (strong) MPRenderer *renderer;
@property CGFloat previousSplitRatio;
/// Aplica directamente un modo de vista (Editor&Preview / Solo Editor / Solo Vista).
- (void)applyLayoutMode:(MPDefaultLayout)mode;
@property BOOL manualRender;
@property BOOL copying;
@property BOOL printing;
@property BOOL shouldHandleBoundsChange;
/// Modo escritura (edición inline) activo. Por documento, no se persiste; arranca OFF
/// (lectura limpia). Lo conmuta el toggle de la toolbar; al cambiar se empuja al JS del
/// visor (macdownSetWritingMode) y se reaplica tras cada re-render.
@property (nonatomic) BOOL inlineWritingMode;
@property BOOL isPreviewReady;
@property (strong) NSURL *currentBaseUrl;
@property CGFloat lastPreviewScrollTop;
@property (nonatomic, readonly) BOOL needsHtml;
@property (nonatomic) NSUInteger totalWords;
@property (nonatomic) NSUInteger totalCharacters;
@property (nonatomic) NSUInteger totalCharactersNoSpaces;
@property (strong) NSMenuItem *wordsMenuItem;
@property (strong) NSMenuItem *charMenuItem;
@property (strong) NSMenuItem *charNoSpacesMenuItem;
@property (nonatomic) BOOL needsToUnregister;
@property (nonatomic) BOOL alreadyRenderingInWeb;
@property (nonatomic) BOOL renderToWebPending;
@property (strong) NSArray<NSNumber *> *webViewHeaderLocations;
@property (strong) NSArray<NSNumber *> *editorHeaderLocations;
@property (nonatomic) BOOL inLiveScroll;

// Store file content in initializer until nib is loaded.
@property (copy) NSString *loadedString;

- (void)scaleWebview;
- (void)syncScrollers;
-(void) updateHeaderLocations;

// Spike experimental: preview alternativo con WKWebView, detrás del flag
// NSUserDefaults @"experimentalWKWebView". La WebView legacy sigue intacta.
@property (strong) WKWebView *wkPreview;
@property (copy) NSURL *wkPreviewTempURL;
@property CGFloat wkPreviewContentHeight;   // alto total del contenido (px CSS)
@property CGFloat wkPreviewVisibleHeight;   // alto visible del viewport (px CSS)
@property NSTimeInterval suppressPreviewScrollUntil;  // anti-bucle editor↔preview
@property (copy) NSString *wkPreviewID;     // id único del temporal por documento

// Find bar del visor (búsqueda en el WKWebView con findString:).
@property (strong) NSView *wkFindBar;
@property (strong) NSSearchField *wkFindField;
@property (strong) NSTextField *wkFindStatus;

// Selección conectada editor↔visor (mapeo por bloque vía data-sourcepos).
@property NSTimeInterval suppressLinkedSelectionUntil;  // anti-bucle de selección
- (BOOL)usesWKWebView;
- (void)setupWKPreviewIfNeeded;
- (void)loadHTMLInWKWebView:(NSString *)html baseURL:(NSURL *)baseUrl;
- (void)updateEditorHeaderLocations;        // mitad "editor" de updateHeaderLocations
- (void)refreshWKPreviewMetricsThen:(void (^)(void))then;  // lee posiciones (async)
- (void)syncScrollersWK;
- (void)syncEditorToPreviewScrollY:(CGFloat)previewY;

@end

static void (^MPGetPreviewLoadingCompletionHandler(MPDocument *doc))()
{
    __weak MPDocument *weakObj = doc;
    return ^{
        WebView *webView = weakObj.preview;
        NSWindow *window = webView.window;
        @synchronized(window) {
            if (window.isFlushWindowDisabled)
                [window enableFlushWindow];
        }
        [weakObj scaleWebview];
        if (weakObj.preferences.editorSyncScrolling)
        {
            [weakObj updateHeaderLocations];
            [weakObj syncScrollers];
        }
        else
        {
            NSClipView *contentView = webView.enclosingScrollView.contentView;
            NSRect bounds = contentView.bounds;
            bounds.origin.y = weakObj.lastPreviewScrollTop;
            contentView.bounds = bounds;
        }
    };
}


// Devuelve `s` como literal de cadena JS (incluidas las comillas), escapando
// comillas, barras, saltos de línea, etc. Se apoya en el codificador JSON (el
// escape de cadenas JSON es válido en JS) envolviendo en un array y quitando los
// corchetes, para no depender de NSJSONWritingFragmentsAllowed.
static NSString *MPJSStringLiteral(NSString *s)
{
    if (![s isKindOfClass:[NSString class]])
        s = @"";
    NSData *d = [NSJSONSerialization dataWithJSONObject:@[s] options:0 error:NULL];
    NSString *arr = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
    if (arr.length >= 2)
        return [arr substringWithRange:NSMakeRange(1, arr.length - 2)];
    return @"\"\"";
}

// WKWebView del visor. Captura el Cmd+F (performFindPanelAction:) cuando el visor
// tiene el foco y lo reenvía al documento, que muestra el find bar propio — si no,
// WebKit/el editor se lo comen y el buscador del visor no aparece. Acepta primer
// respondedor para que el clic en el visor le dé el foco.
@interface MPWKWebView : WKWebView
@property (weak) id findActionTarget;
@end

@implementation MPWKWebView
- (BOOL)acceptsFirstResponder { return YES; }
- (void)performFindPanelAction:(id)sender
{
    if ([self.findActionTarget respondsToSelector:@selector(performFindPanelAction:)])
        [self.findActionTarget performFindPanelAction:sender];
}
@end


@implementation MPDocument

#pragma mark - Accessor

- (MPPreferences *)preferences
{
    return [MPPreferences sharedInstance];
}

- (NSString *)markdown
{
    return self.editor.string;
}

- (void)setMarkdown:(NSString *)markdown
{
    self.editor.string = markdown;
}

- (NSString *)html
{
    return self.renderer.currentHtml;
}

- (BOOL)toolbarVisible
{
    return self.windowForSheet.toolbar.visible;
}

- (BOOL)previewVisible
{
    return (self.preview.frame.size.width != 0.0);
}

- (BOOL)editorVisible
{
    return (self.editorContainer.frame.size.width != 0.0);
}

- (BOOL)needsHtml
{
    if (self.preferences.markdownManualRender)
        return NO;
    return (self.previewVisible || self.preferences.editorShowWordCount);
}

- (void)setTotalWords:(NSUInteger)value
{
    _totalWords = value;
    NSString *key = NSLocalizedString(@"WORDS_PLURAL_STRING", @"");
    NSInteger rule = kJJPluralFormRule.integerValue;
    self.wordsMenuItem.title =
        [JJPluralForm pluralStringForNumber:value withPluralForms:key
                            usingPluralRule:rule localizeNumeral:NO];
}

- (void)setTotalCharacters:(NSUInteger)value
{
    _totalCharacters = value;
    NSString *key = NSLocalizedString(@"CHARACTERS_PLURAL_STRING", @"");
    NSInteger rule = kJJPluralFormRule.integerValue;
    self.charMenuItem.title =
        [JJPluralForm pluralStringForNumber:value withPluralForms:key
                            usingPluralRule:rule localizeNumeral:NO];
}

- (void)setTotalCharactersNoSpaces:(NSUInteger)value
{
    _totalCharactersNoSpaces = value;
    NSString *key = NSLocalizedString(@"CHARACTERS_NO_SPACES_PLURAL_STRING",
                                      @"");
    NSInteger rule = kJJPluralFormRule.integerValue;
    self.charNoSpacesMenuItem.title =
        [JJPluralForm pluralStringForNumber:value withPluralForms:key
                            usingPluralRule:rule localizeNumeral:NO];
}

- (void)setAutosaveName:(NSString *)autosaveName
{
    _autosaveName = autosaveName;
    self.splitView.autosaveName = autosaveName;
}


#pragma mark - Override

- (instancetype)init
{
    self = [super init];
    if (!self)
        return nil;

    self.isPreviewReady = NO;
    self.shouldHandleBoundsChange = YES;
    self.previousSplitRatio = -1.0;
    
    return self;
}

- (NSString *)windowNibName
{
    return @"MPDocument";
}

- (void)windowControllerDidLoadNib:(NSWindowController *)controller
{
    [super windowControllerDidLoadNib:controller];

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    // All files use their absolute path to keep their window states.
    NSString *autosaveName = kMPDefaultAutosaveName;
    if (self.fileURL)
        autosaveName = self.fileURL.absoluteString;
    controller.window.frameAutosaveName = autosaveName;
    self.autosaveName = autosaveName;

    // Perform initial resizing manually because for some reason untitled
    // documents do not pick up the autosaved frame automatically in 10.10.
    NSString *rectString = MPRectStringForAutosaveName(autosaveName);
    if (!rectString)
        rectString = MPRectStringForAutosaveName(kMPDefaultAutosaveName);
    if (rectString)
        [controller.window setFrameFromString:rectString];

    self.highlighter =
        [[HGMarkdownHighlighter alloc] initWithTextView:self.editor
                                           waitInterval:0.0];
    self.renderer = [[MPRenderer alloc] init];
    self.renderer.dataSource = self;
    self.renderer.delegate = self;

    for (NSString *key in MPEditorPreferencesToObserve())
    {
        [defaults addObserver:self forKeyPath:key
                      options:NSKeyValueObservingOptionNew context:NULL];
    }
    for (NSString *key in MPEditorKeysToObserve())
    {
        [self.editor addObserver:self forKeyPath:key
                         options:NSKeyValueObservingOptionNew context:NULL];
    }

    self.editor.postsFrameChangedNotifications = YES;
    self.preview.frameLoadDelegate = self;
    self.preview.policyDelegate = self;
    self.preview.editingDelegate = self;
    self.preview.resourceLoadDelegate = self;

    // Crea la WKWebView temprano (en contexto limpio del hilo principal), no dentro
    // del callback de render, para evitar el crash de re-entrancia de WebKit al
    // arrancar el WebProcess durante el primer loadFileURL.
    [self setupWKPreviewIfNeeded];

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(editorTextDidChange:)
                   name:NSTextDidChangeNotification object:self.editor];
    [center addObserver:self selector:@selector(userDefaultsDidChange:)
                   name:NSUserDefaultsDidChangeNotification
                 object:[NSUserDefaults standardUserDefaults]];
    [center addObserver:self selector:@selector(editorBoundsDidChange:)
                   name:NSViewBoundsDidChangeNotification
                 object:self.editor.enclosingScrollView.contentView];
    [center addObserver:self selector:@selector(editorFrameDidChange:)
                   name:NSViewFrameDidChangeNotification object:self.editor];
    [center addObserver:self selector:@selector(didRequestEditorReload:)
                   name:MPDidRequestEditorSetupNotification object:nil];
    [center addObserver:self selector:@selector(didRequestPreviewReload:)
                   name:MPDidRequestPreviewRenderNotification object:nil];
    [center addObserver:self selector:@selector(willStartLiveScroll:)
                   name:NSScrollViewWillStartLiveScrollNotification
                 object:self.editor.enclosingScrollView];
    [center addObserver:self selector:@selector(didEndLiveScroll:)
                   name:NSScrollViewDidEndLiveScrollNotification
                 object:self.editor.enclosingScrollView];
    if (kCFCoreFoundationVersionNumber >= kCFCoreFoundationVersionNumber10_9)
    {
        [center addObserver:self selector:@selector(previewDidLiveScroll:)
                       name:NSScrollViewDidEndLiveScrollNotification
                     object:self.preview.enclosingScrollView];
    }

    self.needsToUnregister = YES;

    self.wordsMenuItem = [[NSMenuItem alloc] initWithTitle:@"" action:NULL
                                             keyEquivalent:@""];
    self.charMenuItem = [[NSMenuItem alloc] initWithTitle:@"" action:NULL
                                            keyEquivalent:@""];
    self.charNoSpacesMenuItem = [[NSMenuItem alloc] initWithTitle:@""
                                                           action:NULL
                                                    keyEquivalent:@""];

    NSPopUpButton *wordCountWidget = self.wordCountWidget;
    [wordCountWidget removeAllItems];
    [wordCountWidget.menu addItem:self.wordsMenuItem];
    [wordCountWidget.menu addItem:self.charMenuItem];
    [wordCountWidget.menu addItem:self.charNoSpacesMenuItem];
    [wordCountWidget selectItemAtIndex:self.preferences.editorWordCountType];
    wordCountWidget.alphaValue = 0.9;
    wordCountWidget.hidden = !self.preferences.editorShowWordCount;
    wordCountWidget.enabled = NO;

    // These needs to be queued until after the window is shown, so that editor
    // can have the correct dimention for size-limiting and stuff. See
    // https://github.com/uranusjr/macdown/issues/236
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        [self setupEditor:nil];
        [self redrawDivider];
        [self reloadFromLoadedString];
        // The editor/preview styles persist on their own; only the window
        // chrome needs reapplying to match the saved appearance mode.
        [self applyWindowAppearanceForViewMode:self.preferences.appViewMode];
    }];
}

- (void)reloadFromLoadedString
{
    if (self.loadedString && self.editor && self.renderer && self.highlighter)
    {
        self.editor.string = self.loadedString;
        self.loadedString = nil;
        [self.renderer parseAndRenderNow];
        [self.highlighter parseAndHighlightNow];
    }
}

- (void)close
{
    if (self.needsToUnregister) 
    {
        // Close can be called multiple times, but this can only be done once.
        // http://www.cocoabuilder.com/archive/cocoa/240166-nsdocument-close-method-calls-itself.html
        self.needsToUnregister = NO;

        // Need to cleanup these so that callbacks won't crash the app.
        [self.highlighter deactivate];
        self.highlighter.targetTextView = nil;
        self.highlighter = nil;
        self.renderer = nil;
        self.preview.frameLoadDelegate = nil;
        self.preview.policyDelegate = nil;

        // Spike WKWebView: limpiar el HTML temporal y soltar delegados/handlers
        // (addScriptMessageHandler: retiene self → hay que quitarlo para no fugar).
        if (self.wkPreviewTempURL)
        {
            [[NSFileManager defaultManager] removeItemAtURL:self.wkPreviewTempURL
                                                      error:NULL];
            self.wkPreviewTempURL = nil;
        }
        @try {
            [self.wkPreview.configuration.userContentController
                removeScriptMessageHandlerForName:@"macdown"];
        } @catch (__unused NSException *e) {}
        self.wkPreview.navigationDelegate = nil;

        [[NSNotificationCenter defaultCenter] removeObserver:self];

        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

        for (NSString *key in MPEditorPreferencesToObserve())
            [defaults removeObserver:self forKeyPath:key];
        for (NSString *key in MPEditorKeysToObserve())
            [self.editor removeObserver:self forKeyPath:key];
    }

    [super close];
}

+ (BOOL)autosavesInPlace
{
    return YES;
}

+ (NSArray *)writableTypes
{
    return @[@"net.daringfireball.markdown"];
}

- (BOOL)isDocumentEdited
{
    // Prevent save dialog on an unnamed, empty document. The file will still
    // show as modified (because it is), but no save dialog will be presented
    // when the user closes it.
    if (!self.presentedItemURL && !self.editor.string.length)
        return NO;
    return [super isDocumentEdited];
}

- (BOOL)writeToURL:(NSURL *)url ofType:(NSString *)typeName
             error:(NSError *__autoreleasing *)outError
{
    if (self.preferences.editorEnsuresNewlineAtEndOfFile)
    {
        NSCharacterSet *newline = [NSCharacterSet newlineCharacterSet];
        NSString *text = self.editor.string;
        NSUInteger end = text.length;
        if (end && ![newline characterIsMember:[text characterAtIndex:end - 1]])
        {
            NSRange selection = self.editor.selectedRange;
            [self.editor insertText:@"\n" replacementRange:NSMakeRange(end, 0)];
            self.editor.selectedRange = selection;
        }
    }
    return [super writeToURL:url ofType:typeName error:outError];
}

- (NSData *)dataOfType:(NSString *)typeName error:(NSError **)outError
{
    return [self.editor.string dataUsingEncoding:NSUTF8StringEncoding];
}

- (BOOL)readFromData:(NSData *)data ofType:(NSString *)typeName
               error:(NSError **)outError
{
    NSString *content = [[NSString alloc] initWithData:data
                                              encoding:NSUTF8StringEncoding];
    if (!content)
        return NO;

    self.loadedString = content;
    [self reloadFromLoadedString];
    return YES;
}

- (void)presentedItemDidChange
{
    [super presentedItemDidChange];
    dispatch_async(dispatch_get_main_queue(), ^{
        NSURL *url = self.fileURL;
        if (!url || !url.isFileURL)
            return;

        NSDate *diskDate = nil;
        NSError *attrError = nil;
        if (![url getResourceValue:&diskDate forKey:NSURLContentModificationDateKey error:&attrError])
            return;
        NSDate *knownDate = self.fileModificationDate;
        if (knownDate && diskDate && [diskDate compare:knownDate] != NSOrderedDescending)
            return;

        if (self.isDocumentEdited)
            return; // don't clobber unsaved edits

        NSError *revertError = nil;
        [self revertToContentsOfURL:url ofType:self.fileType error:&revertError];
    });
}

- (BOOL)prepareSavePanel:(NSSavePanel *)savePanel
{
    savePanel.extensionHidden = NO;
    if (self.fileURL && self.fileURL.isFileURL)
    {
        NSString *path = self.fileURL.path;

        // Use path of parent directory if this is a file. Otherwise this is it.
        BOOL isDir = NO;
        BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:path
                                                           isDirectory:&isDir];
        if (!exists || !isDir)
            path = [path stringByDeletingLastPathComponent];

        savePanel.directoryURL = [NSURL fileURLWithPath:path];
    }
    else
    {
        // Suggest a file name for new documents.
        NSString *fileName = self.presumedFileName;
        if (fileName && ![fileName hasExtension:@"md"])
        {
            fileName = [fileName stringByAppendingPathExtension:@"md"];
            savePanel.nameFieldStringValue = fileName;
        }
    }
    
    // Get supported extensions from plist
    static NSMutableArray *supportedExtensions = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        supportedExtensions = [NSMutableArray array];
        NSDictionary *infoDict = [NSBundle mainBundle].infoDictionary;
        for (NSDictionary *docType in infoDict[@"CFBundleDocumentTypes"])
        {
            NSArray *exts = docType[@"CFBundleTypeExtensions"];
            if (exts.count)
            {
                [supportedExtensions addObjectsFromArray:exts];
            }
        }
    });
    
    savePanel.allowedFileTypes = supportedExtensions;
    savePanel.allowsOtherFileTypes = YES; // Allow all extensions.
    
    return [super prepareSavePanel:savePanel];
}

- (NSPrintInfo *)printInfo
{
    NSPrintInfo *info = [super printInfo];
    if (!info)
        info = [[NSPrintInfo sharedPrintInfo] copy];
    info.horizontalPagination = NSAutoPagination;
    info.verticalPagination = NSAutoPagination;
    info.verticallyCentered = NO;
    info.topMargin = 50.0;
    info.leftMargin = 0.0;
    info.rightMargin = 0.0;
    info.bottomMargin = 50.0;
    return info;
}

- (NSPrintOperation *)printOperationWithSettings:(NSDictionary *)printSettings
                                           error:(NSError *__autoreleasing *)e
{
    NSPrintInfo *info = [self.printInfo copy];
    [info.dictionary addEntriesFromDictionary:printSettings];

    // WKWebView tiene su propia operación de impresión (macOS 11+); el preview
    // legacy está vacío en modo WK, así que imprimiría/exportaría en blanco.
    if (self.usesWKWebView)
        return [self.wkPreview printOperationWithPrintInfo:info];

    WebFrameView *view = self.preview.mainFrame.frameView;
    NSPrintOperation *op = [view printOperationWithPrintInfo:info];
    return op;
}

- (void)printDocumentWithSettings:(NSDictionary *)printSettings
                   showPrintPanel:(BOOL)showPrintPanel delegate:(id)delegate
                 didPrintSelector:(SEL)selector contextInfo:(void *)contextInfo
{
    self.printing = YES;
    NSInvocation *invocation = nil;
    if (delegate && selector)
    {
        NSMethodSignature *signature =
            [NSMethodSignature methodSignatureForSelector:selector];
        invocation = [NSInvocation invocationWithMethodSignature:signature];
        invocation.target = delegate;
        if (contextInfo)
            [invocation setArgument:&contextInfo atIndex:2];
    }
    [super printDocumentWithSettings:printSettings
                      showPrintPanel:showPrintPanel delegate:self
                    didPrintSelector:@selector(document:didPrint:context:)
                         contextInfo:(void *)invocation];
}

- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)item
{
    BOOL result = [super validateUserInterfaceItem:item];
    SEL action = item.action;
    if (action == @selector(toggleToolbar:))
    {
        NSMenuItem *it = ((NSMenuItem *)item);
        it.title = self.toolbarVisible ?
            NSLocalizedString(@"Hide Toolbar",
                              @"Toggle reveal toolbar") :
            NSLocalizedString(@"Show Toolbar",
                              @"Toggle reveal toolbar");
    }
    else if (action == @selector(togglePreviewPane:))
    {
        NSMenuItem *it = ((NSMenuItem *)item);
        it.hidden = (!self.previewVisible && self.previousSplitRatio < 0.0);
        it.title = self.previewVisible ?
            NSLocalizedString(@"Hide Preview Pane",
                              @"Toggle preview pane menu item") :
            NSLocalizedString(@"Restore Preview Pane",
                              @"Toggle preview pane menu item");

    }
    else if (action == @selector(toggleEditorPane:))
    {
        NSMenuItem *it = (NSMenuItem*)item;
        it.title = self.editorVisible ?
        NSLocalizedString(@"Hide Editor Pane",
                          @"Toggle editor pane menu item") :
        NSLocalizedString(@"Restore Editor Pane",
                          @"Toggle editor pane menu item");
    }
    else if ((action == @selector(setLightMode:)
              || action == @selector(setDarkMode:)
              || action == @selector(setSepiaMode:))
             && [(NSObject *)item isKindOfClass:[NSMenuItem class]])
    {
        NSMenuItem *it = (NSMenuItem *)item;
        MPViewMode mode = (action == @selector(setDarkMode:)) ? MPViewModeDark
                        : (action == @selector(setSepiaMode:)) ? MPViewModeSepia
                        : MPViewModeLight;
        it.state = (self.preferences.appViewMode == mode)
            ? NSControlStateValueOn : NSControlStateValueOff;
    }
    else if ((action == @selector(showEditorAndPreview:)
              || action == @selector(showEditorOnly:)
              || action == @selector(showPreviewOnly:))
             && [(NSObject *)item isKindOfClass:[NSMenuItem class]])
    {
        NSMenuItem *it = (NSMenuItem *)item;
        BOOL ed = self.editorVisible, pv = self.previewVisible;
        BOOL active;
        if (action == @selector(showEditorAndPreview:)) {
            active = (ed && pv);
            it.title = NSLocalizedString(@"Show Both Panes",
                                         @"View mode: editor and preview");
        } else if (action == @selector(showEditorOnly:)) {
            active = (ed && !pv);
            it.title = NSLocalizedString(@"Show Editor Only",
                                         @"View mode: editor only");
        } else {
            active = (!ed && pv);
            it.title = NSLocalizedString(@"Show Preview Only",
                                         @"View mode: preview only");
        }
        // Selectivo: oculta la opción del estado actual; muestra solo las
        // transiciones útiles (con su atajo ⌃⌘1/2/3 al lado).
        it.hidden = active;
        it.state = NSControlStateValueOff;
    }
    return result;
}


#pragma mark - NSSplitViewDelegate

- (void)splitViewDidResizeSubviews:(NSNotification *)notification
{
    [self redrawDivider];
    self.editor.editable = self.editorVisible;
}


#pragma mark - NSTextViewDelegate

- (BOOL)textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector
{
    if (commandSelector == @selector(insertTab:))
        return ![self textViewShouldInsertTab:textView];
    else if (commandSelector == @selector(insertBacktab:))
        return ![self textViewShouldInsertBacktab:textView];
    else if (commandSelector == @selector(insertNewline:))
        return ![self textViewShouldInsertNewline:textView];
    else if (commandSelector == @selector(deleteBackward:))
        return ![self textViewShouldDeleteBackward:textView];
    else if (commandSelector == @selector(moveToLeftEndOfLine:))
        return ![self textViewShouldMoveToLeftEndOfLine:textView];
    return NO;
}

- (BOOL)textView:(NSTextView *)textView shouldChangeTextInRange:(NSRange)range
                                              replacementString:(NSString *)str
{
    // Ignore if this originates from an IM marked text commit event.
    if (NSIntersectionRange(textView.markedRange, range).length)
        return YES;

    if (self.preferences.editorCompleteMatchingCharacters)
    {
        BOOL strikethrough = self.preferences.extensionStrikethough;
        if ([textView completeMatchingCharactersForTextInRange:range
                                                    withString:str
                                          strikethroughEnabled:strikethrough])
            return NO;
    }
    
	// For every change, set the typing attributes
	if (range.location > 0) {
		NSRange prevRange = range;
		prevRange.location -= 1;
		prevRange.length = 1;

		NSDictionary *attr = [[textView attributedString] fontAttributesInRange:prevRange];
		[textView setTypingAttributes:attr];
	}

    return YES;
}

#pragma mark - Fake NSTextViewDelegate

- (BOOL)textViewShouldInsertTab:(NSTextView *)textView
{
    if (textView.selectedRange.length != 0)
    {
        [self indent:nil];
        return NO;
    }
    else if (self.preferences.editorConvertTabs)
    {
        [textView insertSpacesForTab];
        return NO;
    }
    return YES;
}

- (BOOL)textViewShouldInsertBacktab:(NSTextView *)textView
{
    [self unindent:nil];
    return NO;
}

- (BOOL)textViewShouldInsertNewline:(NSTextView *)textView
{
    if ([textView insertMappedContent])
        return NO;

    BOOL inserts = self.preferences.editorInsertPrefixInBlock;
    if (inserts && [textView completeNextListItem:
            self.preferences.editorAutoIncrementNumberedLists])
        return NO;
    if (inserts && [textView completeNextBlockquoteLine])
        return NO;
    if ([textView completeNextIndentedLine])
        return NO;
    return YES;
}

- (BOOL)textViewShouldDeleteBackward:(NSTextView *)textView
{
    NSRange selectedRange = textView.selectedRange;
    if (self.preferences.editorCompleteMatchingCharacters)
    {
        NSUInteger location = selectedRange.location;
        if ([textView deleteMatchingCharactersAround:location])
            return NO;
    }
    if (self.preferences.editorConvertTabs && !selectedRange.length)
    {
        NSUInteger location = selectedRange.location;
        if ([textView unindentForSpacesBefore:location])
            return NO;
    }
    return YES;
}

- (BOOL)textViewShouldMoveToLeftEndOfLine:(NSTextView *)textView
{
    if (!self.preferences.editorSmartHome)
        return YES;
    NSUInteger cur = textView.selectedRange.location;
    NSUInteger location =
        [textView.string locationOfFirstNonWhitespaceCharacterInLineBefore:cur];
    if (location == cur || cur == 0)
        return YES;
    else if (cur >= textView.string.length)
        cur = textView.string.length - 1;

    // We don't want to jump rows when the line is wrapped. (#103)
    // If the line is wrapped, the target will be higher than the current glyph.
    NSLayoutManager *manager = textView.layoutManager;
    NSTextContainer *container = textView.textContainer;
    NSRect targetRect =
        [manager boundingRectForGlyphRange:NSMakeRange(location, 1)
                           inTextContainer:container];
    NSRect currentRect =
        [manager boundingRectForGlyphRange:NSMakeRange(cur, 1)
                           inTextContainer:container];
    if (targetRect.origin.y != currentRect.origin.y)
        return YES;

    textView.selectedRange = NSMakeRange(location, 0);
    return NO;
}


#pragma mark - WebResourceLoadDelegate

- (NSURLRequest *)webView:(WebView *)sender resource:(id)identifier willSendRequest:(NSURLRequest *)request redirectResponse:(NSURLResponse *)redirectResponse fromDataSource:(WebDataSource *)dataSource
{
    
    if ([[request.URL lastPathComponent] isEqualToString:@"MathJax.js"])
    {
        NSURLComponents *origComps = [NSURLComponents componentsWithURL:[request URL] resolvingAgainstBaseURL:YES];
        NSURLComponents *updatedComps = [NSURLComponents componentsWithURL:[[NSBundle mainBundle] URLForResource:@"MathJax" withExtension:@"js" subdirectory:@"MathJax"] resolvingAgainstBaseURL:NO];
        [updatedComps setQueryItems:[origComps queryItems]];
        
        request = [NSURLRequest requestWithURL:[updatedComps URL]];
    }
    
    return request;
}

#pragma mark - WebFrameLoadDelegate

- (void)webView:(WebView *)sender didCommitLoadForFrame:(WebFrame *)frame
{
    NSWindow *window = sender.window;
    @synchronized(window) {
        if (!window.isFlushWindowDisabled)
            [window disableFlushWindow];
    }

    // If MathJax is off, the on-completion callback will be invoked directly
    // when loading is done (in -webView:didFinishLoadForFrame:).
    if (self.preferences.htmlMathJax)
    {
        MPMathJaxListener *listener = [[MPMathJaxListener alloc] init];
        [listener addCallback:MPGetPreviewLoadingCompletionHandler(self)
                       forKey:@"End"];
        [sender.windowScriptObject setValue:listener forKey:@"MathJaxListener"];
    }
}

- (void)webView:(WebView *)sender didFinishLoadForFrame:(WebFrame *)frame
{
    // If MathJax is on, the on-completion callback will be invoked by the
    // JavaScript handler injected in -webView:didCommitLoadForFrame:.
    if (!self.preferences.htmlMathJax)
    {
        id callback = MPGetPreviewLoadingCompletionHandler(self);
        NSOperationQueue *queue = [NSOperationQueue mainQueue];
        [queue addOperationWithBlock:callback];
    }

    self.isPreviewReady = YES;

    // Update word count
    if (self.preferences.editorShowWordCount)
        [self updateWordCount];
    
    self.alreadyRenderingInWeb = NO;

    if (self.renderToWebPending)
        [self.renderer parseAndRenderNow];

    self.renderToWebPending = NO;
}

- (void)webView:(WebView *)sender didFailLoadWithError:(NSError *)error
       forFrame:(WebFrame *)frame
{
    [self webView:sender didFinishLoadForFrame:frame];
    
    self.alreadyRenderingInWeb = NO;

    if (self.renderToWebPending)
        [self.renderer parseAndRenderNow];

    self.renderToWebPending = NO;
}


#pragma mark - WebPolicyDelegate

- (void)webView:(WebView *)webView
                decidePolicyForNavigationAction:(NSDictionary *)information
        request:(NSURLRequest *)request frame:(WebFrame *)frame
                decisionListener:(id<WebPolicyDecisionListener>)listener
{
    switch ([information[WebActionNavigationTypeKey] integerValue])
    {
        case WebNavigationTypeLinkClicked:
            // If the target is exactly as the current one, ignore.
            if ([self.currentBaseUrl isEqual:request.URL])
            {
                [listener ignore];
                return;
            }
            // If this is a different page, intercept and handle ourselves.
            else if (![self isCurrentBaseUrl:request.URL])
            {
                [listener ignore];
                [self openOrCreateFileForUrl:request.URL];
                return;
            }
            // Otherwise this is somewhere else on the same page. Jump there.
            break;
        default:
            break;
    }
    [listener use];
}


#pragma mark - WKNavigationDelegate

// Equivalente WK del WebPolicyDelegate de arriba: sin esto, un clic en un enlace
// hace que WKWebView navegue dentro del preview y muestre el destino (p. ej. otro
// .md) como texto plano. Interceptamos los clics para abrir el documento en MacDown
// (o el enlace externo en el navegador), y dejamos pasar los saltos a anclas.
- (void)webView:(WKWebView *)webView
    decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction
                decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler
{
    NSURL *url = navigationAction.request.URL;
    if (navigationAction.navigationType == WKNavigationTypeLinkActivated && url)
    {
        // Ancla dentro de la propia página del preview (#sección): el WebView
        // carga un fichero temporal; si el destino es ese mismo fichero, es un
        // salto interno y dejamos que WK haga el scroll.
        if (self.wkPreviewTempURL && url.isFileURL &&
            [url.path isEqualToString:self.wkPreviewTempURL.path])
        {
            decisionHandler(WKNavigationActionPolicyAllow);
            return;
        }
        // Cualquier otro destino (otro .md, una imagen, una URL http…): lo
        // gestionamos nosotros en vez de dejar que WK lo abra como texto plano.
        decisionHandler(WKNavigationActionPolicyCancel);
        [self openOrCreateFileForUrl:url];
        return;
    }
    decisionHandler(WKNavigationActionPolicyAllow);
}


#pragma mark - WebEditingDelegate

- (BOOL)webView:(WebView *)webView doCommandBySelector:(SEL)selector
{
    if (selector == @selector(copy:))
    {
        NSString *html = webView.selectedDOMRange.markupString;

        // Inject the HTML content later so that it doesn't get cleared during
        // the native copy operation.
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            NSPasteboard *pb = [NSPasteboard generalPasteboard];
            if (![pb stringForType:@"public.html"])
                [pb setString:html forType:@"public.html"];
        }];
    }
    return NO;
}

#pragma mark - WebUIDelegate

- (NSUInteger)webView:(WebView *)webView
        dragDestinationActionMaskForDraggingInfo:(id<NSDraggingInfo>)info
{
    return WebDragDestinationActionNone;
}

#pragma mark - MPRendererDataSource

- (BOOL)rendererLoading {
	return self.preview.loading;
}
    
- (NSString *)rendererMarkdown:(MPRenderer *)renderer
{
    return self.editor.string;
}

- (NSString *)rendererHTMLTitle:(MPRenderer *)renderer
{
    NSString *n = self.fileURL.lastPathComponent.stringByDeletingPathExtension;
    return n ? n : @"";
}


#pragma mark - MPRendererDelegate

- (int)rendererExtensions:(MPRenderer *)renderer
{
    return self.preferences.extensionFlags;
}

- (BOOL)rendererHasSmartyPants:(MPRenderer *)renderer
{
    return self.preferences.extensionSmartyPants;
}

- (BOOL)rendererRendersTOC:(MPRenderer *)renderer
{
    return self.preferences.htmlRendersTOC;
}

- (NSString *)rendererStyleName:(MPRenderer *)renderer
{
    return self.preferences.htmlStyleName;
}

- (BOOL)rendererDetectsFrontMatter:(MPRenderer *)renderer
{
    return self.preferences.htmlDetectFrontMatter;
}

- (BOOL)rendererHasSyntaxHighlighting:(MPRenderer *)renderer
{
    return self.preferences.htmlSyntaxHighlighting;
}

- (BOOL)rendererHasMermaid:(MPRenderer *)renderer
{
    return self.preferences.htmlMermaid;
}

- (BOOL)rendererHasGraphviz:(MPRenderer *)renderer
{
    return self.preferences.htmlGraphviz;
}

- (MPCodeBlockAccessoryType)rendererCodeBlockAccesory:(MPRenderer *)renderer
{
    return self.preferences.htmlCodeBlockAccessory;
}

- (BOOL)rendererHasMathJax:(MPRenderer *)renderer
{
    return self.preferences.htmlMathJax;
}

- (NSString *)rendererHighlightingThemeName:(MPRenderer *)renderer
{
    return self.preferences.htmlHighlightingThemeName;
}

- (NSArray<NSString *> *)rendererCmarkExtensions:(MPRenderer *)renderer
{
    return self.preferences.cmarkExtensionNames;
}

- (MPCmarkRenderFlags)rendererCmarkRenderFlags:(MPRenderer *)renderer
{
    return self.preferences.cmarkRenderFlags;
}

- (BOOL)rendererHasHardWrap:(MPRenderer *)renderer
{
    return self.preferences.htmlHardWrap;
}

- (BOOL)rendererHasFootnotes:(MPRenderer *)renderer
{
    return self.preferences.extensionFootnotes;
}

- (void)renderer:(MPRenderer *)renderer didProduceHTMLOutput:(NSString *)html
{
    if (self.alreadyRenderingInWeb)
    {
        self.renderToWebPending = YES;
        return;
    }
    
    if (self.printing)
        return;
    
    self.alreadyRenderingInWeb = YES;

    // Delayed copying for -copyHtml.
    if (self.copying)
    {
        self.copying = NO;
        NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
        [pasteboard clearContents];
        [pasteboard writeObjects:@[self.renderer.currentHtml]];
    }

    NSURL *baseUrl = self.fileURL;
    if (!baseUrl)   // Unsaved doument; just use the default URL.
        baseUrl = self.preferences.htmlDefaultDirectoryUrl;

    self.manualRender = self.preferences.markdownManualRender;

#if 0
    // Unfortunately this DOM-replacing causes a lot of problems...
    // 1. MathJax needs to be triggered.
    // 2. Prism rendering is lost.
    // 3. Potentially more.
    // Essentially all JavaScript needs to be run again after we replace
    // the DOM. I have no idea how many more problems there are, so we'll have
    // to back off from the path for now... :(

    // If we're working on the same document, try not to reload.
    if (self.isPreviewReady && [self.currentBaseUrl isEqualTo:baseUrl])
    {
        // HACK: Ideally we should only inject the parts that changed, and only
        // get the parts we need. For now we only get a complete HTML codument,
        // and rely on regex to get the parts we want in the DOM.

        // Use the existing tree if available, and replace the content.
        DOMDocument *doc = self.preview.mainFrame.DOMDocument;
        DOMNodeList *htmlNodes = [doc getElementsByTagName:@"html"];
        if (htmlNodes.length >= 1)
        {
            static NSString *pattern = @"<html>(.*)</html>";
            static int opts = NSRegularExpressionDotMatchesLineSeparators;

            // Find things inside the <html> tag.
            NSRegularExpression *regex =
                [[NSRegularExpression alloc] initWithPattern:pattern
                                                     options:opts error:NULL];
            NSTextCheckingResult *result =
                [regex firstMatchInString:html options:0
                                    range:NSMakeRange(0, html.length)];
            html = [html substringWithRange:[result rangeAtIndex:1]];

            // Replace everything in the old <html> tag.
            DOMElement *htmlNode = (DOMElement *)[htmlNodes item:0];
            htmlNode.innerHTML = html;

            return;
        }
    }
#endif

    // Reload the page if there's not valid tree to work with.
    if (self.usesWKWebView)
        [self loadHTMLInWKWebView:html baseURL:baseUrl];
    else
        [self.preview.mainFrame loadHTMLString:html baseURL:baseUrl];
    self.currentBaseUrl = baseUrl;
}


#pragma mark - WKWebView (spike experimental)

- (BOOL)usesWKWebView
{
    return [[NSUserDefaults standardUserDefaults]
            boolForKey:@"experimentalWKWebView"];
}

// Crea la WKWebView como subview del preview legacy (que sigue siendo el arranged
// subview del split view → no rompe el divisor). La legacy queda detrás, vacía.
- (void)setupWKPreviewIfNeeded
{
    if (!self.usesWKWebView || self.wkPreview || !self.preview)
        return;

    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    // Permitir que el HTML local cargue recursos file:// (bundle + doc) y que
    // mermaid/MathJax hagan XHR a file://. KVC sobre prefs no documentadas:
    // aceptable en un spike; la migración real usará un WKURLSchemeHandler.
    @try {
        [config.preferences setValue:@YES forKey:@"allowFileAccessFromFileURLs"];
        [config setValue:@YES forKey:@"allowUniversalAccessFromFileURLs"];
    } @catch (__unused NSException *e) {}

    // Puente JS→ObjC genérico: un único handler "macdown" enrutado por un campo
    // "type" en el mensaje. Reemplaza al windowScriptObject legacy y sirve a
    // cualquier visualizador/plugin (scroll, mathjaxDone, …) y a la futura IA.
    WKUserContentController *ucc = [[WKUserContentController alloc] init];
    [ucc addScriptMessageHandler:self name:@"macdown"];
    NSString *scrollJS =
        @"(function(){var t=false;function send(){t=false;"
        @"if(window.webkit&&window.webkit.messageHandlers&&window.webkit.messageHandlers.macdown)"
        @"window.webkit.messageHandlers.macdown.postMessage({type:'scroll',y:window.pageYOffset});}"
        @"window.addEventListener('scroll',function(){if(!t){t=true;"
        @"requestAnimationFrame(send);}},{passive:true});})();";
    [ucc addUserScript:[[WKUserScript alloc] initWithSource:scrollJS
        injectionTime:WKUserScriptInjectionTimeAtDocumentEnd forMainFrameOnly:YES]];

    // Selección conectada editor↔visor (mapeo por bloque vía data-sourcepos):
    //  - macdownHighlightLines(start,end): resalta el bloque que cubre esas líneas.
    //  - selectionchange: al seleccionar en el visor, manda las líneas del bloque
    //    para reflejar la selección en el editor.
    NSString *linkedJS =
        @"(function(){"
        @"var pr=document.createElement('a');pr.href='#';pr.style.cssText='display:none';"
        @"document.documentElement.appendChild(pr);"
        @"var ac=getComputedStyle(pr).color;pr.remove();"
        @"if(!ac||ac==='rgba(0, 0, 0, 0)')ac=getComputedStyle(document.body||document.documentElement).color;"
        @"var G8='linear-gradient(var(--mda),var(--mda)),linear-gradient(var(--mda),var(--mda)),linear-gradient(var(--mda),var(--mda)),linear-gradient(var(--mda),var(--mda)),linear-gradient(var(--mda),var(--mda)),linear-gradient(var(--mda),var(--mda)),linear-gradient(var(--mda),var(--mda)),linear-gradient(var(--mda),var(--mda))';"
        @"var P8='left top,left top,right top,right top,left bottom,left bottom,right bottom,right bottom';"
        @"var Z8='30px 2px,2px 30px,30px 2px,2px 30px,30px 2px,2px 30px,30px 2px,2px 30px';"
        @"var G4=',linear-gradient(var(--mda),var(--mda)),linear-gradient(var(--mda),var(--mda)),linear-gradient(var(--mda),var(--mda)),linear-gradient(var(--mda),var(--mda))';"
        @"var st=document.createElement('style');"
        @"st.textContent=':root{--mda:'+ac+';}'"
        @"+'.macdown-linked{position:relative;}'"
        @"+'.macdown-linked::after{content:\"\";position:absolute;inset:-6px;pointer-events:none;border-radius:4px;background-repeat:no-repeat;background-image:'+G8+';background-position:'+P8+';background-size:'+Z8+';}'"
        @"+'.macdown-linked.big::after{background-image:'+G8+G4+';background-position:'+P8+',top center,bottom center,left center,right center;background-size:'+Z8+',34px 2px,34px 2px,2px 34px,2px 34px;}';"
        @"(document.head||document.documentElement).appendChild(st);"
        @"function clr(){var n=document.querySelectorAll('.macdown-linked');for(var i=0;i<n.length;i++){n[i].classList.remove('macdown-linked');n[i].classList.remove('big');}}"
        @"function mark(el){el.classList.add('macdown-linked');var lh=parseFloat(getComputedStyle(el).lineHeight)||20;if(Math.round(el.offsetHeight/lh)>=10)el.classList.add('big');}"
        @"function pb(t,el){var a=el.getAttribute('data-sourcepos');"
        @"var m=a&&a.match(/^(\\d+):\\d+-(\\d+):\\d+/);"
        @"if(m&&window.webkit&&window.webkit.messageHandlers&&window.webkit.messageHandlers.macdown)"
        @"window.webkit.messageHandlers.macdown.postMessage({type:t,startLine:+m[1],endLine:+m[2]});}"
        @"window.macdownHighlightLines=function(start,end){clr();if(!start)return;"
        @"var els=document.querySelectorAll('[data-sourcepos]'),best=null,bs=1e9;"
        @"for(var i=0;i<els.length;i++){var a=els[i].getAttribute('data-sourcepos');"
        @"var m=a&&a.match(/^(\\d+):\\d+-(\\d+):\\d+/);if(!m)continue;"
        @"var s=+m[1],e=+m[2];if(s<=start&&start<=e){var sp=e-s;if(sp<bs){bs=sp;best=els[i];}}}"
        @"if(best){mark(best);pb('block',best);}"
        @"else if(window.webkit&&window.webkit.messageHandlers&&window.webkit.messageHandlers.macdown)"
        @"window.webkit.messageHandlers.macdown.postMessage({type:'block',startLine:0,endLine:0});};"
        @"document.addEventListener('selectionchange',function(){"
        @"var sel=window.getSelection();if(!sel||sel.rangeCount===0)return;"
        @"var node=sel.anchorNode;if(node&&node.nodeType===3)node=node.parentElement;"
        @"while(node&&!(node.getAttribute&&node.getAttribute('data-sourcepos')))node=node.parentElement;"
        @"if(!node)return;clr();mark(node);pb('selection',node);"
        @"});})();";

    // Edición inline (M1): el inspector del visor sustituye a la selección conectada
    // clásica (ambos definen macdownHighlightLines y postean 'block'/'selection';
    // inyectar los dos a la vez duplicaría recuadros). En esta rama va siempre activo
    // —la rama es el aislamiento del experimento—; cuando vaya hacia master se añadirá
    // una preferencia real. Si el recurso no carga, se cae al linkedJS clásico.
    NSString *inspectorJS = nil;
    NSString *p = [[NSBundle mainBundle] pathForResource:@"inline-inspector"
                                                  ofType:@"js" inDirectory:@"Extensions"];
    if (p)
        inspectorJS = [NSString stringWithContentsOfFile:p
                                                encoding:NSUTF8StringEncoding error:NULL];
    [ucc addUserScript:[[WKUserScript alloc]
        initWithSource:(inspectorJS ? inspectorJS : linkedJS)
         injectionTime:WKUserScriptInjectionTimeAtDocumentEnd forMainFrameOnly:YES]];
    config.userContentController = ucc;

    MPWKWebView *wk = [[MPWKWebView alloc] initWithFrame:self.preview.bounds
                                           configuration:config];
    wk.findActionTarget = self;
    wk.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    wk.navigationDelegate = self;
    [self.preview addSubview:wk];
    self.wkPreview = wk;
}

#pragma mark - Búsqueda en el visor (WKWebView, findString:)

// performFindPanelAction: lo maneja el editor (NSTextView) cuando tiene el foco; si el
// selector llega hasta el documento por la responder chain es porque el foco está en el
// visor, así que buscamos ahí con un find bar propio (WKWebView no trae uno).
- (void)performFindPanelAction:(id)sender
{
    if (![self usesWKWebView] || !self.wkPreview)
        return;
    switch ([sender tag])
    {
        case NSFindPanelActionShowFindPanel: [self mp_showWKFindBar];          break;
        case NSFindPanelActionNext:          [self mp_findInPreviewForward:YES]; break;
        case NSFindPanelActionPrevious:      [self mp_findInPreviewForward:NO];  break;
        default: break;
    }
}

- (void)mp_buildWKFindBarIfNeeded
{
    if (self.wkFindBar)
        return;

    NSSearchField *field = [[NSSearchField alloc] init];
    field.translatesAutoresizingMaskIntoConstraints = NO;
    field.placeholderString = NSLocalizedString(@"Buscar en el visor", @"preview find");
    field.target = self;
    field.action = @selector(mp_wkFindNext:);
    field.delegate = (id<NSSearchFieldDelegate>)self;
    [field.widthAnchor constraintGreaterThanOrEqualToConstant:180].active = YES;
    self.wkFindField = field;

    NSTextField *status = [NSTextField labelWithString:@""];
    status.translatesAutoresizingMaskIntoConstraints = NO;
    status.textColor = [NSColor secondaryLabelColor];
    status.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
    self.wkFindStatus = status;

    NSButton *prev = [NSButton buttonWithTitle:@"‹" target:self action:@selector(mp_wkFindPrev:)];
    NSButton *next = [NSButton buttonWithTitle:@"›" target:self action:@selector(mp_wkFindNext:)];
    NSButton *done = [NSButton buttonWithTitle:@"✕" target:self action:@selector(mp_hideWKFindBar:)];
    for (NSButton *b in @[prev, next, done]) b.bezelStyle = NSBezelStyleRounded;

    NSStackView *stack = [NSStackView stackViewWithViews:@[field, prev, next, status, done]];
    stack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    stack.spacing = 4;
    stack.edgeInsets = NSEdgeInsetsMake(5, 8, 5, 8);
    stack.translatesAutoresizingMaskIntoConstraints = NO;

    NSView *bar = [[NSView alloc] initWithFrame:NSZeroRect];
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    bar.wantsLayer = YES;
    bar.layer.backgroundColor =
        [[NSColor windowBackgroundColor] colorWithAlphaComponent:0.98].CGColor;
    bar.layer.borderColor = [NSColor separatorColor].CGColor;
    bar.layer.borderWidth = 1.0;
    bar.layer.cornerRadius = 6.0;
    [bar addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:bar.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:bar.bottomAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor],
    ]];
    self.wkFindBar = bar;
}

- (void)mp_showWKFindBar
{
    [self mp_buildWKFindBarIfNeeded];
    NSView *host = self.preview;     // contenedor donde vive el wkPreview
    if (self.wkFindBar.superview != host)
    {
        [host addSubview:self.wkFindBar];
        [NSLayoutConstraint activateConstraints:@[
            [self.wkFindBar.trailingAnchor constraintEqualToAnchor:host.trailingAnchor constant:-14],
            [self.wkFindBar.topAnchor constraintEqualToAnchor:host.topAnchor constant:12],
        ]];
    }
    self.wkFindBar.hidden = NO;
    [self.wkFindBar.window makeFirstResponder:self.wkFindField];
}

- (IBAction)mp_hideWKFindBar:(id)sender
{
    self.wkFindBar.hidden = YES;
    self.wkFindStatus.stringValue = @"";
    if (self.wkPreview)
        [self.wkPreview.window makeFirstResponder:self.wkPreview];
}

- (IBAction)mp_wkFindNext:(id)sender { [self mp_findInPreviewForward:YES]; }
- (IBAction)mp_wkFindPrev:(id)sender { [self mp_findInPreviewForward:NO]; }

- (void)mp_findInPreviewForward:(BOOL)forward
{
    NSString *q = self.wkFindField.stringValue;
    if (q.length == 0 || !self.wkPreview)
    {
        self.wkFindStatus.stringValue = @"";
        return;
    }
    WKFindConfiguration *cfg = [[WKFindConfiguration alloc] init];
    cfg.backwards = !forward;
    cfg.caseSensitive = NO;
    cfg.wraps = YES;
    __weak MPDocument *weak = self;
    [self.wkPreview findString:q withConfiguration:cfg
             completionHandler:^(WKFindResult *result) {
        weak.wkFindStatus.stringValue = result.matchFound
            ? @"" : NSLocalizedString(@"Sin coincidencias", @"preview find");
    }];
}

// Esc en el campo de búsqueda cierra el find bar (NSControlTextEditingDelegate).
- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView
    doCommandBySelector:(SEL)commandSelector
{
    if (control == self.wkFindField && commandSelector == @selector(cancelOperation:))
    {
        [self mp_hideWKFindBar:nil];
        return YES;
    }
    return NO;
}

#pragma mark - Selección conectada editor→visor

// Al mover el cursor/selección en el editor, resalta en el visor el bloque que cubre
// esas líneas (mapeo por data-sourcepos). El sentido inverso (visor→editor) llega por
// el mensaje "selection". suppressLinkedSelectionUntil corta el eco entre ambos.
- (void)textViewDidChangeSelection:(NSNotification *)notification
{
    if (![self usesWKWebView] || !self.wkPreview)
        return;
    if ([NSDate timeIntervalSinceReferenceDate] < self.suppressLinkedSelectionUntil)
        return;
    NSRange sel = self.editor.selectedRange;
    NSUInteger startLine = [self mp_editorLineForCharIndex:sel.location];
    NSUInteger endLine = sel.length > 0
        ? [self mp_editorLineForCharIndex:NSMaxRange(sel) - 1] : startLine;
    NSString *js = [NSString stringWithFormat:
        @"window.macdownHighlightLines&&window.macdownHighlightLines(%lu,%lu);",
        (unsigned long)startLine, (unsigned long)endLine];
    [self.wkPreview evaluateJavaScript:js completionHandler:nil];
}

// Número de línea (1-based) que contiene el índice de carácter dado.
- (NSUInteger)mp_editorLineForCharIndex:(NSUInteger)idx
{
    NSString *s = self.editor.string;
    if (idx > s.length)
        idx = s.length;
    NSUInteger line = 1;
    NSRange range = NSMakeRange(0, idx);
    NSRange nl;
    while ((nl = [s rangeOfString:@"\n" options:0 range:range]).location != NSNotFound)
    {
        line++;
        NSUInteger next = nl.location + 1;
        range = NSMakeRange(next, idx - next);
    }
    return line;
}

// Rango de caracteres (sin el salto final) que abarcan las líneas [startLine, endLine].
- (NSRange)mp_editorCharRangeForLines:(NSInteger)startLine to:(NSInteger)endLine
{
    if (startLine < 1)
        return NSMakeRange(NSNotFound, 0);
    if (endLine < startLine)
        endLine = startLine;
    NSString *s = self.editor.string;
    __block NSUInteger cur = 0;
    __block NSUInteger startLoc = NSNotFound;
    __block NSUInteger endLoc = s.length;
    [s enumerateSubstringsInRange:NSMakeRange(0, s.length)
        options:NSStringEnumerationByLines | NSStringEnumerationSubstringNotRequired
        usingBlock:^(NSString *sub, NSRange subRange, NSRange enclosing, BOOL *stop) {
            cur++;
            if (cur == (NSUInteger)startLine)
                startLoc = enclosing.location;
            if (cur == (NSUInteger)endLine)
            {
                endLoc = NSMaxRange(subRange);
                *stop = YES;
            }
        }];
    if (startLoc == NSNotFound)
        return NSMakeRange(NSNotFound, 0);
    if (endLoc < startLoc)
        endLoc = startLoc;
    return NSMakeRange(startLoc, endLoc - startLoc);
}

#pragma mark - WKScriptMessageHandler (puente genérico macdown)

- (void)userContentController:(WKUserContentController *)userContentController
      didReceiveScriptMessage:(WKScriptMessage *)message
{
    if (![message.name isEqualToString:@"macdown"])
        return;
    NSDictionary *body = [message.body isKindOfClass:[NSDictionary class]]
        ? message.body : nil;
    NSString *type = body[@"type"];

    if ([type isEqualToString:@"scroll"])
    {
        if (!self.preferences.editorSyncScrolling)
            return;
        // Ignora el eco de nuestros propios scrolls editor→preview (anti-bucle).
        if ([NSDate timeIntervalSinceReferenceDate] < self.suppressPreviewScrollUntil)
            return;
        [self syncEditorToPreviewScrollY:[body[@"y"] doubleValue]];
    }
    else if ([type isEqualToString:@"mathjaxDone"])
    {
        // MathJax renderiza async tras cargar la página y cambia el layout, así que
        // las posiciones cacheadas en didFinishNavigation quedan obsoletas. Al
        // terminar, se re-cachean y se reposiciona el preview al editor.
        if (self.preferences.editorSyncScrolling)
        {
            self.suppressPreviewScrollUntil =
                [NSDate timeIntervalSinceReferenceDate] + 0.4;
            [self updateEditorHeaderLocations];
            __weak MPDocument *weak = self;
            [self refreshWKPreviewMetricsThen:^{ [weak syncScrollersWK]; }];
        }
    }
    else if ([type isEqualToString:@"block"] || [type isEqualToString:@"selection"])
    {
        // Mapeo por bloque. "block" viene de mover el cursor en el editor (el visor ya
        // se recuadró por JS; aquí recuadramos el editor). "selection" viene de un clic
        // en el visor (recuadra el editor y además lleva el cursor allí).
        NSInteger startLine = [body[@"startLine"] integerValue];
        NSRange r = (startLine >= 1)
            ? [self mp_editorCharRangeForLines:startLine to:[body[@"endLine"] integerValue]]
            : NSMakeRange(NSNotFound, 0);
        self.editor.linkedBlockRange = r;     // recuadro en el editor (o lo limpia)
        if ([type isEqualToString:@"selection"] && r.location != NSNotFound
            && [NSDate timeIntervalSinceReferenceDate] >= self.suppressLinkedSelectionUntil)
        {
            self.suppressLinkedSelectionUntil =
                [NSDate timeIntervalSinceReferenceDate] + 0.35;
            // Solo llevamos el cursor al inicio del bloque (sin seleccionar el texto):
            // la selección queda reservada para la futura sincronización de selección.
            // Suprimimos el sync editor→preview mientras movemos el editor: el clic es
            // en el VISOR, así que el visor NO debe desplazarse (era el bug del salto
            // al inicio al pulsar tras hacer scroll).
            BOOL prevSync = self.shouldHandleBoundsChange;
            self.shouldHandleBoundsChange = NO;
            self.editor.selectedRange = NSMakeRange(r.location, 0);
            [self.editor scrollRangeToVisible:r];
            self.shouldHandleBoundsChange = prevSync;
        }
    }
    else if ([type isEqualToString:@"inlineToggle"])
    {
        // El botón flotante del visor pide alternar el modo escritura. Sólo aplica en
        // sólo-visor (su hogar único); se conmuta y se empuja de vuelta al JS.
        if ([self mp_isPreviewOnly])
        {
            self.inlineWritingMode = !self.inlineWritingMode;
            [self.wkPreview evaluateJavaScript:[NSString stringWithFormat:
                @"window.macdownSetWritingMode&&window.macdownSetWritingMode(%@);",
                self.inlineWritingMode ? @"true" : @"false"] completionHandler:nil];
        }
    }
    else if ([type isEqualToString:@"inlineEdit"])
    {
        // Edición inline (M1): el visor pide el FUENTE Markdown de un bloque (rango de
        // líneas vía sourcepos) para abrir su mini-editor. Se lo devolvemos por JS.
        NSInteger s = [body[@"startLine"] integerValue];
        NSInteger e = [body[@"endLine"] integerValue];
        NSRange r = [self mp_editorCharRangeForLines:s to:e];
        if (r.location == NSNotFound || NSMaxRange(r) > self.editor.string.length)
            return;
        NSString *src = [self.editor.string substringWithRange:r];
        NSString *js = [NSString stringWithFormat:
            @"window.macdownOpenInlineEditor&&window.macdownOpenInlineEditor(%ld,%ld,%@);",
            (long)s, (long)e, MPJSStringLiteral(src)];
        [self.wkPreview evaluateJavaScript:js completionHandler:nil];
    }
    else if ([type isEqualToString:@"inlineEditCommit"])
    {
        // El mini-editor confirma: reescribimos el rango EXACTO del fuente por el
        // pipeline normal del NSTextView (registra undo y dispara el re-render vía
        // NSTextDidChangeNotification → editorTextDidChange:).
        NSInteger s = [body[@"startLine"] integerValue];
        NSInteger e = [body[@"endLine"] integerValue];
        NSString *text = [body[@"text"] isKindOfClass:[NSString class]] ? body[@"text"] : nil;
        if (!text)
            return;
        NSRange r = [self mp_editorCharRangeForLines:s to:e];
        if (r.location == NSNotFound || NSMaxRange(r) > self.editor.string.length)
            return;
        NSTextView *tv = self.editor;
        if ([tv shouldChangeTextInRange:r replacementString:text])
        {
            [tv.textStorage replaceCharactersInRange:r withString:text];
            [tv didChangeText];
        }
    }
}

// Inversa de syncScrollersWK: dada la Y de scroll de la vista, interpola la
// posición equivalente en el editor y lo desplaza. Guarda shouldHandleBoundsChange
// para que ese scroll del editor no rebote de vuelta a la vista.
- (void)syncEditorToPreviewScrollY:(CGFloat)previewY
{
    NSArray<NSNumber *> *pv = _webViewHeaderLocations;
    NSArray<NSNumber *> *ed = _editorHeaderLocations;
    // La lista del editor está filtrada (omite los encabezados del último
    // pantallazo), la de la vista los tiene todos. Solo son fiables los índices
    // COMUNES; más allá del último, se interpola hasta el final del documento.
    NSInteger n = MIN((NSInteger)pv.count, (NSInteger)ed.count);
    if (n == 0)
        return;

    CGFloat editorContentHeight = ceilf(NSHeight(self.editor.enclosingScrollView.documentView.bounds));
    CGFloat editorVisibleHeight = ceilf(NSHeight(self.editor.enclosingScrollView.contentView.bounds));
    CGFloat editorMax = MAX(0, editorContentHeight - editorVisibleHeight);
    CGFloat previewMax = MAX(0, self.wkPreviewContentHeight - self.wkPreviewVisibleHeight);

    // idx = último encabezado común con pv[idx] <= previewY.
    NSInteger idx = -1;
    for (NSInteger i = 0; i < n; i++)
    {
        if ([pv[i] doubleValue] <= previewY)
            idx = i;
        else
            break;
    }

    // La siguiente cabecera es "alcanzable" solo si su posición en el preview cae
    // dentro del rango scrolleable (<= previewMax). Las cabeceras del último
    // pantallazo del visor quedan por encima de previewMax: no se pueden llevar
    // arriba scrolleando, así que el último tramo alcanzable debe mapear hasta el
    // fondo de AMBOS (previewMax → editorMax). Si no, el editor se queda corto y la
    // sección final nunca se alcanza.
    BOOL nextReachable = (idx + 1 < n) && ([pv[idx + 1] doubleValue] <= previewMax);
    CGFloat topPv, botPv, topEd, botEd;
    if (idx < 0)                       // antes del primer encabezado
    {
        topPv = 0;                  botPv = (n > 0 ? [pv[0] doubleValue] : previewMax);
        topEd = 0;                  botEd = (n > 0 ? [ed[0] doubleValue] : editorMax);
    }
    else if (!nextReachable)           // último tramo alcanzable → hasta el fondo
    {
        topPv = [pv[idx] doubleValue];     botPv = previewMax;
        topEd = [ed[idx] doubleValue];     botEd = editorMax;
    }
    else                               // entre dos encabezados alcanzables
    {
        topPv = [pv[idx] doubleValue];     botPv = [pv[idx + 1] doubleValue];
        topEd = [ed[idx] doubleValue];     botEd = [ed[idx + 1] doubleValue];
    }

    CGFloat frac = (botPv > topPv) ? MAX(0, MIN(1.0, (previewY - topPv) / (botPv - topPv))) : 0;
    CGFloat editorY = topEd + (botEd - topEd) * frac;
    editorY = MAX(0, MIN(editorY, editorMax));

    BOOL prev = self.shouldHandleBoundsChange;
    self.shouldHandleBoundsChange = NO;
    NSClipView *clip = self.editor.enclosingScrollView.contentView;
    NSRect b = clip.bounds;
    b.origin.y = editorY;
    clip.bounds = b;
    self.shouldHandleBoundsChange = prev;
}

- (void)loadHTMLInWKWebView:(NSString *)html baseURL:(NSURL *)baseUrl
{
    // WKWebView no carga subrecursos file:// con loadHTMLString:baseURL:. Se
    // escribe el HTML a un fichero temporal en el directorio del documento (para
    // que resuelvan las rutas relativas del doc) y se carga con loadFileURL:
    // dando lectura a "/" para que resuelvan también los recursos absolutos del
    // bundle. (En la migración real esto será un WKURLSchemeHandler, sin disco.)
    NSURL *dir;
    if (baseUrl.isFileURL)
        // baseUrl es el fichero .md en docs guardados, o ya un directorio en
        // documentos sin guardar.
        dir = (baseUrl.hasDirectoryPath ? baseUrl
               : [baseUrl URLByDeletingLastPathComponent]);
    else
        dir = [NSURL fileURLWithPath:NSTemporaryDirectory()];
    // Nombre ÚNICO por documento: si no, dos docs del mismo directorio escriben el
    // mismo fichero y se pisan (el preview mostraba el otro doc hasta un Cmd+R).
    if (!self.wkPreviewID)
        self.wkPreviewID = [[NSUUID UUID] UUIDString];
    NSString *name = [NSString stringWithFormat:@".macdown-wk-preview-%@.html",
                      self.wkPreviewID];
    NSURL *tempURL = [dir URLByAppendingPathComponent:name];
    NSError *err = nil;
    if (![html writeToURL:tempURL atomically:YES
                 encoding:NSUTF8StringEncoding error:&err])
    {
        tempURL = [[NSURL fileURLWithPath:NSTemporaryDirectory()]
                   URLByAppendingPathComponent:name];
        [html writeToURL:tempURL atomically:YES
                encoding:NSUTF8StringEncoding error:NULL];
    }
    self.wkPreviewTempURL = tempURL;

    // Las operaciones de WKWebView (crear + loadFileURL) DEBEN ir en el hilo
    // principal y no reentrantes: el render puede venir de una cola de fondo, y
    // loadFileURL durante el arranque del WebProcess crashea con "lock recursively".
    // Diferir a la cola principal rompe ambos problemas.
    NSURL *finalURL = tempURL;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self setupWKPreviewIfNeeded];
        [self.wkPreview loadFileURL:finalURL
            allowingReadAccessToURL:[NSURL fileURLWithPath:@"/"]];
    });
}

- (void)webView:(WKWebView *)webView
        didFinishNavigation:(WKNavigation *)navigation
{
    self.isPreviewReady = YES;
    self.alreadyRenderingInWeb = NO;
    if (self.renderToWebPending)
        [self.renderer parseAndRenderNow];
    self.renderToWebPending = NO;

    // El inspector se reinyecta con cada HTML nuevo (arranca en lectura): reaplica la
    // disponibilidad (sólo-visor) y el modo escritura del documento tras el re-render.
    [self mp_pushInlineStateToPreview];

    if (self.preferences.editorShowWordCount)
        [self updateWordCount];

    // Re-aplica el zoom del preview tras cargar el HTML nuevo.
    [self scaleWebview];

    if (self.preferences.editorSyncScrolling)
    {
        // Al recargar, el preview WK vuelve al tope. Reposiciónalo a la posición
        // del editor (cuando lleguen las métricas) para que NO salte arriba en cada
        // tecla, y suprime el preview→editor mientras se reasienta (si no, ese
        // salto arrastraría el editor: "no estoy donde creo estar").
        self.suppressPreviewScrollUntil =
            [NSDate timeIntervalSinceReferenceDate] + 0.6;
        [self updateEditorHeaderLocations];
        __weak MPDocument *weak = self;
        [self refreshWKPreviewMetricsThen:^{ [weak syncScrollersWK]; }];
    }
}

- (void)webView:(WKWebView *)webView
        didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error
{
    self.alreadyRenderingInWeb = NO;
    self.renderToWebPending = NO;
}

- (void)webView:(WKWebView *)webView
        didFailProvisionalNavigation:(WKNavigation *)navigation
        withError:(NSError *)error
{
    self.alreadyRenderingInWeb = NO;
    self.renderToWebPending = NO;
}


#pragma mark - Notification handler

- (void)editorTextDidChange:(NSNotification *)notification
{
    if (self.needsHtml)
        [self.renderer parseAndRenderLater];
}

- (void)userDefaultsDidChange:(NSNotification *)notification
{
    MPRenderer *renderer = self.renderer;

    // Force update if we're switching from manual to auto, or render
    // settings changed.
    if (!self.preferences.markdownManualRender && self.manualRender)
    {
        [renderer parseAndRenderLater];
    }
    else
    {
        [renderer parseIfPreferencesChanged];
        [renderer renderIfPreferencesChanged];
    }
}

- (void)editorFrameDidChange:(NSNotification *)notification
{
    if (self.preferences.editorWidthLimited)
        [self adjustEditorInsets];
}

- (void)willStartLiveScroll:(NSNotification *)notification
{
    [self updateHeaderLocations];
    _inLiveScroll = YES;
}

-(void)didEndLiveScroll:(NSNotification *)notification
{
    _inLiveScroll = NO;
}

- (void)editorBoundsDidChange:(NSNotification *)notification
{
    if (!self.shouldHandleBoundsChange)
        return;

    if (self.preferences.editorSyncScrolling)
    {
        @synchronized(self) {
            self.shouldHandleBoundsChange = NO;
            if(!_inLiveScroll){
                [self updateHeaderLocations];
            }
            
            [self syncScrollers];
            self.shouldHandleBoundsChange = YES;
        }
    }
}

- (void)didRequestEditorReload:(NSNotification *)notification
{
    NSString *key =
        notification.userInfo[MPDidRequestEditorSetupNotificationKeyName];
    [self setupEditor:key];
}

- (void)didRequestPreviewReload:(NSNotification *)notification
{
    [self render:nil];
}

- (void)previewDidLiveScroll:(NSNotification *)notification
{
    NSClipView *contentView = self.preview.enclosingScrollView.contentView;
    self.lastPreviewScrollTop = contentView.bounds.origin.y;
}


#pragma mark - KVO

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object
                        change:(NSDictionary *)change context:(void *)context
{
    if (object == self.editor)
    {
        if (!self.highlighter.isActive)
            return;
        id value = change[NSKeyValueChangeNewKey];
        NSString *preferenceKey = MPEditorPreferenceKeyWithValueKey(keyPath);
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        [defaults setObject:value forKey:preferenceKey];
    }
    else if (object == [NSUserDefaults standardUserDefaults])
    {
        if (self.highlighter.isActive)
            [self setupEditor:keyPath];
        [self redrawDivider];
    }
}


#pragma mark - IBAction

- (IBAction)copyHtml:(id)sender
{
    // Dis-select things in WebView so that it's more obvious we're NOT
    // respecting the selection range.
    [self.preview setSelectedDOMRange:nil affinity:NSSelectionAffinityUpstream];

    // If the preview is hidden, the HTML are not updating on text change.
    // Perform one extra rendering so that the HTML is up to date, and do the
    // copy in the rendering callback.
    if (!self.needsHtml)
    {
        self.copying = YES;
        [self.renderer parseAndRenderNow];
        return;
    }
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard clearContents];
    [pasteboard writeObjects:@[self.renderer.currentHtml]];
}

- (IBAction)exportHtml:(id)sender
{
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.allowedFileTypes = @[@"html"];
    if (self.presumedFileName)
        panel.nameFieldStringValue = self.presumedFileName;

    MPExportPanelAccessoryViewController *controller =
        [[MPExportPanelAccessoryViewController alloc] init];
    controller.stylesIncluded = (BOOL)self.preferences.htmlStyleName;
    controller.highlightingIncluded = self.preferences.htmlSyntaxHighlighting;
    panel.accessoryView = controller.view;

    NSWindow *w = self.windowForSheet;
    [panel beginSheetModalForWindow:w completionHandler:^(NSInteger result) {
        if (result != NSFileHandlingPanelOKButton)
            return;
        BOOL styles = controller.stylesIncluded;
        BOOL highlighting = controller.highlightingIncluded;
        NSString *html = [self.renderer HTMLForExportWithStyles:styles
                                                   highlighting:highlighting];
        [html writeToURL:panel.URL atomically:NO encoding:NSUTF8StringEncoding
                   error:NULL];
    }];
}

- (IBAction)exportPdf:(id)sender
{
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.allowedFileTypes = @[@"pdf"];
    if (self.presumedFileName)
        panel.nameFieldStringValue = self.presumedFileName;
    
    NSWindow *w = nil;
    NSArray *windowControllers = self.windowControllers;
    if (windowControllers.count > 0)
        w = [windowControllers[0] window];

    [panel beginSheetModalForWindow:w completionHandler:^(NSInteger result) {
        if (result != NSFileHandlingPanelOKButton)
            return;

        NSDictionary *settings = @{
            NSPrintJobDisposition: NSPrintSaveJob,
            NSPrintJobSavingURL: panel.URL,
        };
        [self printDocumentWithSettings:settings showPrintPanel:NO delegate:nil
                       didPrintSelector:NULL contextInfo:NULL];
    }];
}

- (IBAction)convertToH1:(id)sender
{
    [self.editor makeHeaderForSelectedLinesWithLevel:1];
}

- (IBAction)convertToH2:(id)sender
{
    [self.editor makeHeaderForSelectedLinesWithLevel:2];
}

- (IBAction)convertToH3:(id)sender
{
    [self.editor makeHeaderForSelectedLinesWithLevel:3];
}

- (IBAction)convertToH4:(id)sender
{
    [self.editor makeHeaderForSelectedLinesWithLevel:4];
}

- (IBAction)convertToH5:(id)sender
{
    [self.editor makeHeaderForSelectedLinesWithLevel:5];
}

- (IBAction)convertToH6:(id)sender
{
    [self.editor makeHeaderForSelectedLinesWithLevel:6];
}

- (IBAction)convertToParagraph:(id)sender
{
    [self.editor makeHeaderForSelectedLinesWithLevel:0];
}

- (IBAction)toggleStrong:(id)sender
{
    [self.editor toggleForMarkupPrefix:@"**" suffix:@"**"];
}

- (IBAction)toggleEmphasis:(id)sender
{
    [self.editor toggleForMarkupPrefix:@"*" suffix:@"*"];
}

- (IBAction)toggleInlineCode:(id)sender
{
    [self.editor toggleForMarkupPrefix:@"`" suffix:@"`"];
}

- (IBAction)toggleStrikethrough:(id)sender
{
    [self.editor toggleForMarkupPrefix:@"~~" suffix:@"~~"];
}

- (IBAction)toggleComment:(id)sender
{
    [self.editor toggleForMarkupPrefix:@"<!--" suffix:@"-->"];
}

- (IBAction)toggleLink:(id)sender
{
    BOOL inserted = [self.editor toggleForMarkupPrefix:@"[" suffix:@"]()"];
    if (!inserted)
        return;

    NSRange selectedRange = self.editor.selectedRange;
    NSUInteger location = selectedRange.location + selectedRange.length + 2;
    selectedRange = NSMakeRange(location, 0);

    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    NSString *url = [pb URLForType:NSPasteboardTypeString].absoluteString;
    if (url)
    {
        [self.editor insertText:url replacementRange:selectedRange];
        selectedRange.length = url.length;
    }
    self.editor.selectedRange = selectedRange;
}

- (IBAction)toggleImage:(id)sender
{
    BOOL inserted = [self.editor toggleForMarkupPrefix:@"![" suffix:@"]()"];
    if (!inserted)
        return;

    NSRange selectedRange = self.editor.selectedRange;
    NSUInteger location = selectedRange.location + selectedRange.length + 2;
    selectedRange = NSMakeRange(location, 0);

    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    NSString *url = [pb URLForType:NSPasteboardTypeString].absoluteString;
    if (url)
    {
        [self.editor insertText:url replacementRange:selectedRange];
        selectedRange.length = url.length;
    }
    self.editor.selectedRange = selectedRange;
}

- (IBAction)toggleOrderedList:(id)sender
{
    [self.editor toggleBlockWithPattern:@"^[0-9]+ \\S" prefix:@"1. "];
}

- (IBAction)toggleUnorderedList:(id)sender
{
    NSString *marker = self.preferences.editorUnorderedListMarker;
    [self.editor toggleBlockWithPattern:@"^[\\*\\+-] \\S" prefix:marker];
}

- (IBAction)toggleBlockquote:(id)sender
{
    [self.editor toggleBlockWithPattern:@"^> \\S" prefix:@"> "];
}

- (IBAction)indent:(id)sender
{
    NSString *padding = @"\t";
    if (self.preferences.editorConvertTabs)
        padding = @"    ";
    [self.editor indentSelectedLinesWithPadding:padding];
}

- (IBAction)unindent:(id)sender
{
    [self.editor unindentSelectedLines];
}

- (IBAction)insertNewParagraph:(id)sender
{
    NSRange range = self.editor.selectedRange;
    NSUInteger location = range.location;
    NSUInteger length = range.length;
    NSString *content = self.editor.string;
    NSInteger newlineBefore = [content locationOfFirstNewlineBefore:location];
    NSUInteger newlineAfter =
        [content locationOfFirstNewlineAfter:location + length - 1];

    // If we are on an empty line, treat as normal return key; otherwise insert
    // two newlines.
    if (location == newlineBefore + 1 && location == newlineAfter)
        [self.editor insertNewline:self];
    else
        [self.editor insertText:@"\n\n"];
}

- (IBAction)setEditorOneQuarter:(id)sender
{
    [self setSplitViewDividerLocation:0.25];
}

- (IBAction)setEditorThreeQuarters:(id)sender
{
    [self setSplitViewDividerLocation:0.75];
}

- (IBAction)setEqualSplit:(id)sender
{
    [self setSplitViewDividerLocation:0.5];
}

#pragma mark - Font zoom

- (IBAction)makeFontLarger:(id)sender
{
    [self changeEditorFontSizeBy:1.0];
}

- (IBAction)makeFontSmaller:(id)sender
{
    [self changeEditorFontSizeBy:-1.0];
}

- (IBAction)resetFontSize:(id)sender
{
    NSFont *font = [self.preferences.editorBaseFont copy];
    if (!font)
        return;
    self.preferences.editorBaseFont =
        [NSFont fontWithName:font.fontName size:kMPEditorFontPointSizeDefault];
}

// Nudges the stored base font size. Its setter writes editorBaseFontInfo,
// which is KVO-observed and flows through setupEditor: -> scaleWebview to
// update both the editor font and the preview zoom.
//
// scaleWebview only scales the preview when previewZoomRelativeToBaseFontSize
// is on, so an explicit zoom enables it first — this makes ⌘⌃+/− behave like
// a browser zoom (both panes) and persists across re-renders, since the
// preview-load handler re-applies scaleWebview. Set the pref before the font
// so the resulting scaleWebview already sees it enabled.
- (void)changeEditorFontSizeBy:(CGFloat)delta
{
    NSFont *font = [self.preferences.editorBaseFont copy];
    if (!font)
        return;
    CGFloat size = MIN(MAX(font.pointSize + delta, kMPEditorFontPointSizeMin),
                       kMPEditorFontPointSizeMax);
    self.preferences.previewZoomRelativeToBaseFontSize = YES;
    self.preferences.editorBaseFont = [NSFont fontWithName:font.fontName
                                                      size:size];
}

#pragma mark - View modes (Light / Dark / Sepia)

- (IBAction)setLightMode:(id)sender
{
    [self applyViewMode:MPViewModeLight];
}

- (IBAction)setDarkMode:(id)sender
{
    [self applyViewMode:MPViewModeDark];
}

- (IBAction)setSepiaMode:(id)sender
{
    [self applyViewMode:MPViewModeSepia];
}

// Swaps the editor theme (editorStyleName, KVO -> setupEditor:) and preview
// CSS (htmlStyleName, picked up by userDefaultsDidChange: -> the renderer),
// then matches the window chrome via NSAppearance.
- (void)applyViewMode:(MPViewMode)mode
{
    self.preferences.appViewMode = mode;
    switch (mode)
    {
        case MPViewModeDark:
            self.preferences.editorStyleName = @"Mou Night";
            self.preferences.htmlStyleName = @"Clearness Dark";
            break;
        case MPViewModeSepia:
            self.preferences.editorStyleName = @"Sepia";
            self.preferences.htmlStyleName = @"Sepia";
            break;
        case MPViewModeLight:
        default:
            self.preferences.editorStyleName = @"Tomorrow+";   // current default
            self.preferences.htmlStyleName = @"GitHub2";       // current default
            break;
    }
    [self applyWindowAppearanceForViewMode:mode];
}

- (void)applyWindowAppearanceForViewMode:(MPViewMode)mode
{
    if (@available(macOS 10.14, *))
    {
        NSWindow *window = self.windowControllers.firstObject.window;
        NSString *name = (mode == MPViewModeDark) ? NSAppearanceNameDarkAqua
                                                   : NSAppearanceNameAqua;
        window.appearance = [NSAppearance appearanceNamed:name];
    }
}

- (IBAction)toggleToolbar:(id)sender
{
    [self.windowForSheet toggleToolbarShown:sender];
}

#pragma mark - Edición inline (modo escritura)

// La edición inline vive SÓLO en sólo-visor (el visor a pantalla completa es su hogar
// único). Ahí se activa con un botón flotante translúcido del propio visor (#mdi-fab),
// que postea 'inlineToggle'. En split/editor no hay inspector (se edita en el editor).
- (BOOL)mp_isPreviewOnly
{
    return self.previewVisible && !self.editorVisible;
}

// Empuja al JS del visor: disponibilidad (= sólo-visor → muestra el botón flotante) y el
// modo escritura. Se reinyecta el inspector en cada re-render, por eso también se llama
// desde didFinishNavigation:.
- (void)mp_pushInlineStateToPreview
{
    if (![self usesWKWebView] || !self.wkPreview)
        return;
    BOOL avail = [self mp_isPreviewOnly];
    NSString *js = [NSString stringWithFormat:
        @"window.macdownSetInlineAvailable&&window.macdownSetInlineAvailable(%@);"
        @"window.macdownSetWritingMode&&window.macdownSetWritingMode(%@);",
        avail ? @"true" : @"false",
        (avail && self.inlineWritingMode) ? @"true" : @"false"];
    [self.wkPreview evaluateJavaScript:js completionHandler:nil];
}

// Al cambiar de modo de vista: en sólo-visor se oculta la toolbar (estás leyendo) y se
// habilita la edición inline; en cualquier otro modo, toolbar a la vista y modo escritura
// forzado a OFF (la edición inline no existe fuera del sólo-visor).
- (void)mp_syncChromeForLayout:(MPDefaultLayout)mode
{
    BOOL previewOnly = (mode == MPDefaultLayoutPreviewOnly);
    self.windowForSheet.toolbar.visible = !previewOnly;
    if (!previewOnly)
        self.inlineWritingMode = NO;
    [self mp_pushInlineStateToPreview];
}

- (IBAction)togglePreviewPane:(id)sender
{
    [self toggleSplitterCollapsingEditorPane:NO];
}

- (IBAction)toggleEditorPane:(id)sender
{
    [self toggleSplitterCollapsingEditorPane:YES];
}

#pragma mark - Quick view-mode switching

- (void)applyLayoutMode:(MPDefaultLayout)mode
{
    // ratio 0.0 colapsa el panel izquierdo, 1.0 el derecho. El editor es el
    // izquierdo salvo que editorOnRight los intercambie.
    BOOL editorOnRight = self.preferences.editorOnRight;
    switch (mode)
    {
        case MPDefaultLayoutEditorOnly:     // solo editor (oculta la vista)
            [self setSplitViewDividerLocation:(editorOnRight ? 0.0 : 1.0)];
            break;
        case MPDefaultLayoutPreviewOnly:    // solo vista (oculta el editor)
            [self setSplitViewDividerLocation:(editorOnRight ? 1.0 : 0.0)];
            break;
        case MPDefaultLayoutBoth:
        default:                            // ambos paneles, split equilibrado
        {
            CGFloat ratio = self.previousSplitRatio;
            if (ratio <= 0.0 || ratio >= 1.0)
                ratio = 0.5;
            [self setSplitViewDividerLocation:ratio];
            break;
        }
    }
    [self mp_syncChromeForLayout:mode];
}

- (IBAction)showEditorAndPreview:(id)sender
{
    [self applyLayoutMode:MPDefaultLayoutBoth];
}

- (IBAction)showEditorOnly:(id)sender
{
    [self applyLayoutMode:MPDefaultLayoutEditorOnly];
}

- (IBAction)showPreviewOnly:(id)sender
{
    [self applyLayoutMode:MPDefaultLayoutPreviewOnly];
}

- (IBAction)cycleViewMode:(id)sender
{
    // Rota Editor&Preview -> Solo Editor -> Solo Vista -> Editor&Preview.
    MPDefaultLayout next;
    if (self.editorVisible && self.previewVisible)
        next = MPDefaultLayoutEditorOnly;
    else if (self.editorVisible)
        next = MPDefaultLayoutPreviewOnly;
    else
        next = MPDefaultLayoutBoth;
    [self applyLayoutMode:next];
}

- (IBAction)render:(id)sender
{
    [self.renderer parseAndRenderLater];
}


#pragma mark - Private

- (void)toggleSplitterCollapsingEditorPane:(BOOL)forEditorPane
{
    BOOL isVisible = forEditorPane ? self.editorVisible : self.previewVisible;
    BOOL editorOnRight = self.preferences.editorOnRight;

    float targetRatio = ((forEditorPane == editorOnRight) ? 1.0 : 0.0);

    if (isVisible)
    {
        CGFloat oldRatio = self.splitView.dividerLocation;
        if (oldRatio != 0.0 && oldRatio != 1.0)
        {
            // We don't want to save these values, since they are meaningless.
            // The user should be able to switch between 100% editor and 100%
            // preview without losing the old ratio.
            self.previousSplitRatio = oldRatio;
        }
        [self setSplitViewDividerLocation:targetRatio];
    }
    else
    {
        // We have an inconsistency here, let's just go back to 0.5,
        // otherwise nothing will happen
        if (self.previousSplitRatio < 0.0)
            self.previousSplitRatio = 0.5;

        [self setSplitViewDividerLocation:self.previousSplitRatio];
    }
}

- (void)setupEditor:(NSString *)changedKey
{
    [self.highlighter deactivate];

    if (!changedKey || [changedKey isEqualToString:@"extensionFootnotes"])
    {
        int extensions = pmh_EXT_NOTES;
        if (self.preferences.extensionFootnotes)
            extensions = pmh_EXT_NONE;
        self.highlighter.extensions = extensions;
    }

    if (!changedKey || [changedKey isEqualToString:@"editorHorizontalInset"]
            || [changedKey isEqualToString:@"editorVerticalInset"]
            || [changedKey isEqualToString:@"editorWidthLimited"]
            || [changedKey isEqualToString:@"editorMaximumWidth"])
    {
        [self adjustEditorInsets];
    }

    if (!changedKey || [changedKey isEqualToString:@"editorBaseFontInfo"]
            || [changedKey isEqualToString:@"editorStyleName"]
            || [changedKey isEqualToString:@"editorLineSpacing"])
    {
        NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
        style.lineSpacing = self.preferences.editorLineSpacing;
        self.editor.defaultParagraphStyle = [style copy];
        NSFont *font = [self.preferences.editorBaseFont copy];
        if (font)
            self.editor.font = font;
        self.editor.textColor = nil;
        self.editor.backgroundColor = [NSColor clearColor];
        self.highlighter.styles = nil;
        [self.highlighter readClearTextStylesFromTextView];

        NSString *themeName = [self.preferences.editorStyleName copy];
        if (themeName.length)
        {
            NSString *path = MPThemePathForName(themeName);
            NSString *themeString = MPReadFileOfPath(path);
            [self.highlighter applyStylesFromStylesheet:themeString
                                       withErrorHandler:
                ^(NSArray *errorMessages) {
                    self.preferences.editorStyleName = nil;
                }];
        }

        CALayer *layer = [CALayer layer];
        CGColorRef backgroundCGColor = self.editor.backgroundColor.CGColor;
        if (backgroundCGColor)
            layer.backgroundColor = backgroundCGColor;
        self.editorContainer.layer = layer;
    }
    
    if ([changedKey isEqualToString:@"editorBaseFontInfo"])
    {
        [self scaleWebview];
    }

    if (!changedKey || [changedKey isEqualToString:@"editorShowWordCount"])
    {
        if (self.preferences.editorShowWordCount)
        {
            self.wordCountWidget.hidden = NO;
            self.editorPaddingBottom.constant = 35.0;
            [self updateWordCount];
        }
        else
        {
            self.wordCountWidget.hidden = YES;
            self.editorPaddingBottom.constant = 0.0;
        }
    }

    if (!changedKey || [changedKey isEqualToString:@"editorScrollsPastEnd"])
    {
        self.editor.scrollsPastEnd = self.preferences.editorScrollsPastEnd;
        NSRect contentRect = self.editor.contentRect;
        NSSize minSize = self.editor.enclosingScrollView.contentSize;
        if (contentRect.size.height < minSize.height)
            contentRect.size.height = minSize.height;
        if (contentRect.size.width < minSize.width)
            contentRect.size.width = minSize.width;
        self.editor.frame = contentRect;
    }

    if (!changedKey)
    {
        NSClipView *contentView = self.editor.enclosingScrollView.contentView;
        contentView.postsBoundsChangedNotifications = YES;

        NSDictionary *keysAndDefaults = MPEditorKeysToObserve();
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        for (NSString *key in keysAndDefaults)
        {
            NSString *preferenceKey = MPEditorPreferenceKeyWithValueKey(key);
            id value = [defaults objectForKey:preferenceKey];
            value = value ? value : keysAndDefaults[key];
            [self.editor setValue:value forKey:key];
        }
    }

    if (!changedKey || [changedKey isEqualToString:@"editorOnRight"])
    {
        BOOL editorOnRight = self.preferences.editorOnRight;
        NSArray *subviews = self.splitView.subviews;
        if ((!editorOnRight && subviews[0] == self.preview)
            || (editorOnRight && subviews[1] == self.preview))
        {
            [self.splitView swapViews];
            if (!self.previewVisible && self.previousSplitRatio >= 0.0)
                self.previousSplitRatio = 1.0 - self.previousSplitRatio;

            // Need to queue this or the views won't be initialised correctly.
            // Don't really know why, but this works.
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                self.splitView.needsLayout = YES;
            }];
        }
    }

    [self.highlighter activate];
    self.editor.automaticLinkDetectionEnabled = NO;
}

- (void)adjustEditorInsets
{
    CGFloat x = self.preferences.editorHorizontalInset;
    CGFloat y = self.preferences.editorVerticalInset;
    if (self.preferences.editorWidthLimited)
    {
        CGFloat editorWidth = self.editor.frame.size.width;
        CGFloat maxWidth = self.preferences.editorMaximumWidth;
        if (editorWidth > 2 * x + maxWidth)
            x = (editorWidth - maxWidth) * 0.45;
        // We tend to expect things in an editor to shift to left a bit.
        // Hence the 0.45 instead of 0.5 (which whould feel a bit too much).
    }
    self.editor.textContainerInset = NSMakeSize(x, y);
}

- (void)redrawDivider
{
    if (!self.editorVisible)
    {
        // If the editor is not visible, detect preview's background color via
        // DOM query and use it instead. This is more expensive; we should try
        // to avoid it.
        // TODO: Is it possible to cache this until the user switches the style?
        // Will need to take account of the user MODIFIES the style without
        // switching. Complicated. This will do for now.
        self.splitView.dividerColor = MPGetWebViewBackgroundColor(self.preview);
    }
    else if (!self.previewVisible)
    {
        // If the editor is visible, match its background color.
        self.splitView.dividerColor = self.editor.backgroundColor;
    }
    else
    {
        // If both sides are visible, draw a default "transparent" divider.
        // This works around the possibile problem of divider's color being too
        // similar to both the editor and preview and being obscured.
        self.splitView.dividerColor = nil;
    }
}

- (void)scaleWebview
{
    if (!self.preferences.previewZoomRelativeToBaseFontSize)
        return;

    CGFloat fontSize = self.preferences.editorBaseFontSize;
    if (fontSize <= 0.0)
        return;

    static const CGFloat defaultSize = 14.0;
    CGFloat scale = fontSize / defaultSize;

    if (self.usesWKWebView)
    {
        // WKWebView: zoom CSS sobre el documento. Reflota como el legacy (a
        // diferencia de magnification, que solo amplía visualmente) y se queda en
        // el mismo sistema de coordenadas que usa el scroll-sync.
        NSString *js = [NSString stringWithFormat:
            @"document.documentElement.style.zoom='%.4f';", (double)scale];
        [self.wkPreview evaluateJavaScript:js completionHandler:nil];
        return;
    }

    // Legacy WebView: API privada, NO App-Store-safe.
    [self.preview setPageSizeMultiplier:scale];
}

-(void) updateHeaderLocations
{
    if (self.usesWKWebView)
    {
        // WKWebView: la mitad "editor" es síncrona; las posiciones del preview se
        // leen de forma asíncrona (no hay DOM síncrono). Se cachean y syncScrollers
        // usa la caché por-frame (el contenido no se reflota durante un scroll).
        [self updateEditorHeaderLocations];
        [self refreshWKPreviewMetricsThen:nil];
        return;
    }

    CGFloat offset = NSMinY(self.preview.enclosingScrollView.contentView.bounds);
    NSMutableArray<NSNumber *> *locations = [NSMutableArray array];

    _webViewHeaderLocations = [[self.preview.mainFrame.javaScriptContext evaluateScript:@"var arr = Array.prototype.slice.call(document.querySelectorAll(\"h1, h2, h3, h4, h5, h6, img:only-child\")); arr.map(function(n){ return n.getBoundingClientRect().top })"] toArray];

    // add offset to all numbers
    for (NSNumber *location in _webViewHeaderLocations)
    {
        [locations addObject:@([location floatValue] + offset)];
    }

    _webViewHeaderLocations = [locations copy];

    [self updateEditorHeaderLocations];
}

// Mitad "editor" de updateHeaderLocations: posiciones Y de cada encabezado/imagen
// en el editor (vía layout manager). Compartida por la ruta legacy y la WK.
- (void)updateEditorHeaderLocations
{
    NSMutableArray<NSNumber *> *locations = [NSMutableArray array];
    NSInteger characterCount = 0;
    NSLayoutManager *layoutManager = [self.editor layoutManager];
    NSArray<NSString *> *documentLines = [self.editor.string componentsSeparatedByString:@"\n"];
    [locations removeAllObjects];

    // These are the patterns for markdown headers and images respectively. we're only going to
    // handle images that are not inline with other text/images
    NSRegularExpression *dashRegex = [NSRegularExpression regularExpressionWithPattern:@"^([-]+)$" options:0 error:nil];
    NSRegularExpression *headerRegex = [NSRegularExpression regularExpressionWithPattern:@"^(#+)\\s" options:0 error:nil];
    NSRegularExpression *imgRegex = [NSRegularExpression regularExpressionWithPattern:@"^!\\[[^\\]]*\\]\\([^)]*\\)$" options:0 error:nil];
    BOOL previousLineHadContent = NO;

    // We start by splitting our document into lines, and then searching
    // line by line for headers or images.
    for (NSInteger lineNumber = 0; lineNumber < [documentLines count]; lineNumber++)
    {
        NSString *line = documentLines[lineNumber];
        
        if ((previousLineHadContent && [dashRegex numberOfMatchesInString:line options:0 range:NSMakeRange(0, [line length])]) ||
            [imgRegex numberOfMatchesInString:line options:0 range:NSMakeRange(0, [line length])] ||
            [headerRegex numberOfMatchesInString:line options:0 range:NSMakeRange(0, [line length])])
        {
            // Calculate where this header/image appears vertically in the editor
            NSRange glyphRange = [layoutManager glyphRangeForCharacterRange:NSMakeRange(characterCount, [line length]) actualCharacterRange:nil];
            NSRect topRect = [layoutManager boundingRectForGlyphRange:glyphRange inTextContainer:[self.editor textContainer]];
            CGFloat headerY = NSMidY(topRect);

            // Se incluyen TODAS las cabeceras (también las del último pantallazo).
            // Antes se filtraban las finales, lo que dejaba sin resolución el último
            // tramo del preview→editor (la sección final no era alcanzable). La
            // dirección editor→preview ya ignora esas cabeceras por su cuenta.
            [locations addObject:@(headerY)];
        }
        
        previousLineHadContent = [line length] && ![dashRegex numberOfMatchesInString:line options:0 range:NSMakeRange(0, [line length])];
        
        characterCount += [line length] + 1;
    }

    _editorHeaderLocations = [locations copy];
}

- (void)syncScrollers
{
    if (self.usesWKWebView)
    {
        [self syncScrollersWK];
        return;
    }

    CGFloat editorContentHeight = ceilf(NSHeight(self.editor.enclosingScrollView.documentView.bounds));
    CGFloat editorVisibleHeight = ceilf(NSHeight(self.editor.enclosingScrollView.contentView.bounds));
    CGFloat previewContentHeight = ceilf(NSHeight(self.preview.enclosingScrollView.documentView.bounds));
    CGFloat previewVisibleHeight = ceilf(NSHeight(self.preview.enclosingScrollView.contentView.bounds));
    NSInteger relativeHeaderIndex = -1; // -1 is start of document, before any other header
    CGFloat currY = NSMinY(self.editor.enclosingScrollView.contentView.bounds);
    CGFloat minY = 0;
    CGFloat maxY = 0;
    
    // align the documents at the middle of the screen, except at top/bottom of document
    CGFloat topTaper = MAX(0, MIN(1.0, currY / editorVisibleHeight));
    CGFloat bottomTaper = 1.0 - MAX(0, MIN(1.0, (currY - editorContentHeight + 2 * editorVisibleHeight) / editorVisibleHeight));
    CGFloat adjustmentForScroll = topTaper * bottomTaper * editorVisibleHeight / 2;

    // We start by splitting our document into lines, and then searching
    // line by line for headers or images.
    for (NSNumber *headerYNum in _editorHeaderLocations) {
        CGFloat headerY = [headerYNum floatValue];
        headerY -= adjustmentForScroll;
        
        if (headerY < currY)
        {
            // The header is before our current scroll position. the closest
            // of these will be our first reference node
            relativeHeaderIndex += 1;
            minY = headerY;
        } else if (maxY == 0 && headerY < editorContentHeight - editorVisibleHeight)
        {
            // Skip any headers that are within the last screen of the editor.
            // we'll interpolate to the end of the document in that case.
            maxY = headerY;
        }
    }
    
    // Usually, we'll be scrolling between two reference nodes, but toward the end
    // of the document we'll ignore nodes and reference the end of the document instead
    BOOL interpolateToEndOfDocument = NO;
    
    if (maxY == 0)
    {
        // We only have a reference node before our current position,
        // but not after, so we'll use the end of the document.
        maxY = editorContentHeight - editorVisibleHeight + adjustmentForScroll;
        interpolateToEndOfDocument = YES;
    }

    // We are currently at currY offset, between minY and maxY, which represent
    // headers indexed by relativeHeaderIndex and relativeHeaderIndex+1.
    currY = MAX(0, currY - minY);
    maxY -= minY;
    minY -= minY;
    CGFloat percentScrolledBetweenHeaders = MAX(0, MIN(1.0, currY / maxY));
    
    // Now that we know where the editor position is relative to two reference nodes,
    // we need to find the positions of those nodes in the HTML preview
    CGFloat topHeaderY = 0;
    CGFloat bottomHeaderY = previewContentHeight - previewVisibleHeight;
    
    // Find the Y positions in the preview window that we're scrolling between
    if ([_webViewHeaderLocations count] > relativeHeaderIndex)
    {
        topHeaderY = floorf([_webViewHeaderLocations[relativeHeaderIndex] doubleValue]) - adjustmentForScroll;
    }
    
    if (!interpolateToEndOfDocument && [_webViewHeaderLocations count] > relativeHeaderIndex + 1)
    {
        bottomHeaderY = ceilf([_webViewHeaderLocations[relativeHeaderIndex + 1] doubleValue]) - adjustmentForScroll;
    }
    
    // Now we scroll percentScrolledBetweenHeaders percent between those two positions in the webview
    CGFloat previewY = topHeaderY + (bottomHeaderY - topHeaderY) * percentScrolledBetweenHeaders;
    NSRect contentBounds = self.preview.enclosingScrollView.contentView.bounds;
    contentBounds.origin.y = previewY;
    self.preview.enclosingScrollView.contentView.bounds = contentBounds;
}

// Lee de forma asíncrona las posiciones Y absolutas de los encabezados del preview
// WK más el alto de contenido y de viewport, y las cachea. WKWebView devuelve los
// objetos/arrays JS como NSDictionary/NSArray, así que no hace falta parsear JSON.
- (void)refreshWKPreviewMetricsThen:(void (^)(void))then
{
    if (!self.wkPreview)
        return;
    NSString *js =
        @"(function(){var hs=document.querySelectorAll('h1,h2,h3,h4,h5,h6,img:only-child');"
        @"var ys=[];for(var i=0;i<hs.length;i++){ys.push(hs[i].getBoundingClientRect().top+window.pageYOffset);}"
        @"return {ys:ys,content:(document.body?document.body.scrollHeight:0),visible:window.innerHeight};})()";
    __weak MPDocument *weak = self;
    [self.wkPreview evaluateJavaScript:js completionHandler:^(id result, NSError *err) {
        MPDocument *strong = weak;
        if ([result isKindOfClass:[NSDictionary class]] && strong)
        {
            NSArray *ys = result[@"ys"];
            if ([ys isKindOfClass:[NSArray class]])
                strong->_webViewHeaderLocations = ys;
            strong.wkPreviewContentHeight = [result[@"content"] doubleValue];
            strong.wkPreviewVisibleHeight = [result[@"visible"] doubleValue];
        }
        if (then)
            then();
    }];
}

// Versión WK de syncScrollers: misma interpolación, pero con las métricas cacheadas
// del preview y aplicando el scroll con window.scrollTo (instantáneo, fire-and-forget).
- (void)syncScrollersWK
{
    if (!self.wkPreview)
        return;

    CGFloat editorContentHeight = ceilf(NSHeight(self.editor.enclosingScrollView.documentView.bounds));
    CGFloat editorVisibleHeight = ceilf(NSHeight(self.editor.enclosingScrollView.contentView.bounds));
    CGFloat previewContentHeight = self.wkPreviewContentHeight;
    CGFloat previewVisibleHeight = self.wkPreviewVisibleHeight;
    if (previewContentHeight <= 0 || previewVisibleHeight <= 0)
        return;   // métricas del preview aún no leídas (async)

    NSInteger relativeHeaderIndex = -1;
    CGFloat currY = NSMinY(self.editor.enclosingScrollView.contentView.bounds);
    CGFloat minY = 0;
    CGFloat maxY = 0;

    CGFloat topTaper = MAX(0, MIN(1.0, currY / editorVisibleHeight));
    CGFloat bottomTaper = 1.0 - MAX(0, MIN(1.0, (currY - editorContentHeight + 2 * editorVisibleHeight) / editorVisibleHeight));
    CGFloat adjustmentForScroll = topTaper * bottomTaper * editorVisibleHeight / 2;

    for (NSNumber *headerYNum in _editorHeaderLocations) {
        CGFloat headerY = [headerYNum floatValue] - adjustmentForScroll;
        if (headerY < currY) {
            relativeHeaderIndex += 1;
            minY = headerY;
        } else if (maxY == 0 && headerY < editorContentHeight - editorVisibleHeight) {
            maxY = headerY;
        }
    }

    BOOL interpolateToEndOfDocument = NO;
    if (maxY == 0) {
        maxY = editorContentHeight - editorVisibleHeight + adjustmentForScroll;
        interpolateToEndOfDocument = YES;
    }

    currY = MAX(0, currY - minY);
    maxY -= minY;
    minY -= minY;
    CGFloat percentScrolledBetweenHeaders = (maxY > 0) ? MAX(0, MIN(1.0, currY / maxY)) : 0;

    CGFloat topHeaderY = 0;
    CGFloat bottomHeaderY = previewContentHeight - previewVisibleHeight;
    NSInteger headerCount = (NSInteger)_webViewHeaderLocations.count;

    if (relativeHeaderIndex >= 0 && headerCount > relativeHeaderIndex)
        topHeaderY = floorf([_webViewHeaderLocations[relativeHeaderIndex] doubleValue]) - adjustmentForScroll;

    if (!interpolateToEndOfDocument && relativeHeaderIndex + 1 >= 0
        && headerCount > relativeHeaderIndex + 1)
        bottomHeaderY = ceilf([_webViewHeaderLocations[relativeHeaderIndex + 1] doubleValue]) - adjustmentForScroll;

    CGFloat previewY = topHeaderY + (bottomHeaderY - topHeaderY) * percentScrolledBetweenHeaders;
    if (previewY < 0)
        previewY = 0;

    // Suprime el eco preview→editor de este scroll que provocamos nosotros.
    self.suppressPreviewScrollUntil = [NSDate timeIntervalSinceReferenceDate] + 0.25;

    NSString *js = [NSString stringWithFormat:
        @"window.scrollTo({top:%.1f,left:0,behavior:'instant'});", (double)previewY];
    [self.wkPreview evaluateJavaScript:js completionHandler:nil];
}

- (void)setSplitViewDividerLocation:(CGFloat)ratio
{
    BOOL wasVisible = self.previewVisible;
    [self.splitView setDividerLocation:ratio];
    if (!wasVisible && self.previewVisible
            && !self.preferences.markdownManualRender)
        [self.renderer parseAndRenderNow];
    [self setupEditor:NSStringFromSelector(@selector(editorHorizontalInset))];
}

- (NSString *)presumedFileName
{
    if (self.fileURL)
        return self.fileURL.lastPathComponent.stringByDeletingPathExtension;

    NSString *title = nil;
    NSString *string = self.editor.string;
    if (self.preferences.htmlDetectFrontMatter)
        title = [[[string frontMatter:NULL] objectForKey:@"title"] description];
    if (title)
        return title;

    title = string.titleString;
    if (!title)
        return NSLocalizedString(@"Untitled", @"default filename if no title can be determined");

    static NSRegularExpression *regex = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        regex = [NSRegularExpression regularExpressionWithPattern:@"[/|:]"
                                                          options:0 error:NULL];
    });

    NSRange range = NSMakeRange(0, title.length);
    title = [regex stringByReplacingMatchesInString:title options:0 range:range
                                       withTemplate:@"-"];
    return title;
}

- (void)updateWordCount
{
    // Cuenta la prosa renderizada desde renderer.currentHtml (disponible en ambos
    // motores) en vez del DOM del WebView legacy — que en modo WKWebView está
    // vacío. Quita código/scripts/estilos, las etiquetas y decodifica entidades.
    NSString *html = self.renderer.currentHtml ?: @"";

    static NSRegularExpression *blockRe = nil, *tagRe = nil, *wsRe = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSRegularExpressionOptions o = NSRegularExpressionCaseInsensitive
            | NSRegularExpressionDotMatchesLineSeparators;
        // Bloques que no cuentan como prosa: código, scripts, estilos, head.
        blockRe = [NSRegularExpression regularExpressionWithPattern:
            @"<(script|style|pre|head)\\b[^>]*>.*?</\\1>" options:o error:NULL];
        tagRe = [NSRegularExpression regularExpressionWithPattern:@"<[^>]+>"
            options:0 error:NULL];
        wsRe = [NSRegularExpression regularExpressionWithPattern:@"\\s+"
            options:0 error:NULL];
    });

    NSMutableString *text = [html mutableCopy];
    NSRange all = NSMakeRange(0, text.length);
    [blockRe replaceMatchesInString:text options:0 range:all withTemplate:@" "];
    all = NSMakeRange(0, text.length);
    [tagRe replaceMatchesInString:text options:0 range:all withTemplate:@" "];

    NSString *plain = text;
    // Entidades más comunes; &amp; al final para no romper "&amp;lt;".
    NSArray<NSArray<NSString *> *> *ents = @[
        @[@"&nbsp;", @" "], @[@"&lt;", @"<"], @[@"&gt;", @">"],
        @[@"&quot;", @"\""], @[@"&#39;", @"'"], @[@"&apos;", @"'"],
        @[@"&amp;", @"&"]];
    for (NSArray<NSString *> *e in ents)
        plain = [plain stringByReplacingOccurrencesOfString:e[0] withString:e[1]];

    // Normaliza espacios (runs → 1) y recorta.
    plain = [wsRe stringByReplacingMatchesInString:plain options:0
        range:NSMakeRange(0, plain.length) withTemplate:@" "];
    plain = [plain stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];

    NSUInteger words = 0;
    for (NSString *p in [plain componentsSeparatedByString:@" "])
        if (p.length)
            words++;
    NSString *noSpaces = [[plain componentsSeparatedByCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]]
        componentsJoinedByString:@""];

    self.totalWords = (plain.length ? words : 0);
    self.totalCharacters = plain.length;
    self.totalCharactersNoSpaces = noSpaces.length;

    if (self.isPreviewReady)
        self.wordCountWidget.enabled = YES;
}

- (BOOL)isCurrentBaseUrl:(NSURL *)another
{
    NSString *mine = self.currentBaseUrl.absoluteBaseURLString;
    NSString *theirs = another.absoluteBaseURLString;
    return mine == theirs || [mine isEqualToString:theirs];
}


#define OPEN_FAIL_ALERT_INFORMATIVE NSLocalizedString( \
@"Please check the path of your link is correct. Turn on \
“Automatically create link targets” If you want MacDown to \
create nonexistent link targets for you.", \
@"preview navigation error information")

#define AUTO_CREATE_FAIL_ALERT_INFORMATIVE NSLocalizedString( \
@"MacDown can’t create a file for the clicked link because \
the current file is not saved anywhere yet. Save the \
current file somewhere to enable this feature.", \
@"preview navigation error information")


- (void)openOrCreateFileForUrl:(NSURL *)url
{
    // Simply open the file if it is not local, or exists already.
    BOOL file = url.isFileURL;
    BOOL reachable = !file || [url checkResourceIsReachableAndReturnError:NULL];
    
    // If the file is local but doesn't exist, check if a file with
    // the .md extension exists.
    if (file && !reachable && [url.pathExtension isEqualToString:@""])
    {
        NSURL *markdownURL = [url URLByAppendingPathExtension:@"md"];
        if ([markdownURL checkResourceIsReachableAndReturnError:NULL])
        {
            reachable = YES;
            url = markdownURL;
        }
    }
    
    if (reachable)
    {
        [[NSWorkspace sharedWorkspace] openURL:url];
        return;
    }

    // Show an error if the user doesn't want us to create it automatically.
    if (!self.preferences.createFileForLinkTarget)
    {
        NSAlert *alert = [[NSAlert alloc] init];
        NSString *template = NSLocalizedString(
            @"File not found at path:\n%@",
            @"preview navigation error message");
        alert.messageText = [NSString stringWithFormat:template, url.path];
        alert.informativeText = OPEN_FAIL_ALERT_INFORMATIVE;
        [alert runModal];
        return;
    }

    // We can only create a file if the current file is saved. (Why?)
    if (!self.fileURL)
    {
        NSAlert *alert = [[NSAlert alloc] init];
        NSString *template = NSLocalizedString(
            @"Can’t create file:\n%@", @"preview navigation error message");
        alert.messageText = [NSString stringWithFormat:template,
                             url.lastPathComponent];
        alert.informativeText = AUTO_CREATE_FAIL_ALERT_INFORMATIVE;
        [alert runModal];
    }

    // Try to created the file.
    NSDocumentController *controller =
        [NSDocumentController sharedDocumentController];

    NSError *error = nil;
    id doc = [controller createNewEmptyDocumentForURL:url
                                              display:YES error:&error];
    if (!doc)
    {
        NSAlert *alert = [[NSAlert alloc] init];
        NSString *template = NSLocalizedString(
            @"Can’t create file:\n%@",
            @"preview navigation error message");
        alert.messageText =
            [NSString stringWithFormat:template, url.lastPathComponent];
        template = NSLocalizedString(
            @"An error occurred while creating the file:\n%@",
            @"preview navigation error information");
        alert.informativeText =
            [NSString stringWithFormat:template, error.localizedDescription];
        [alert runModal];
    }
}


- (void)document:(NSDocument *)doc didPrint:(BOOL)ok context:(void *)context
{
    if ([doc respondsToSelector:@selector(setPrinting:)])
        ((MPDocument *)doc).printing = NO;
    if (context)
    {
        NSInvocation *invocation = (__bridge NSInvocation *)context;
        if ([invocation isKindOfClass:[NSInvocation class]])
        {
            [invocation setArgument:&doc atIndex:0];
            [invocation setArgument:&ok atIndex:1];
            [invocation invoke];
        }
    }
}

@end
