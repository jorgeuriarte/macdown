//
//  MPMainController.m
//  MacDown
//
//  Created by Tzu-ping Chung  on 7/06/2014.
//  Copyright (c) 2014 Tzu-ping Chung . All rights reserved.
//

#import "MPMainController.h"
#import <MASPreferences/MASPreferencesWindowController.h>
#import <Sparkle/Sparkle.h>
#import "MPGlobals.h"
#import "MPUtilities.h"
#import "NSDocumentController+Document.h"
#import "NSUserDefaults+Suite.h"
#import "MPPreferences.h"
#import "MPGeneralPreferencesViewController.h"
#import "MPMarkdownPreferencesViewController.h"
#import "MPEditorPreferencesViewController.h"
#import "MPHtmlPreferencesViewController.h"
#import "MPTerminalPreferencesViewController.h"
#import "MPDocument.h"


static NSString * const kMPTreatLastSeenStampKey = @"treatLastSeenStamp";


NS_INLINE void MPOpenBundledFile(NSString *resource, NSString *extension)
{
    NSURL *source = [[NSBundle mainBundle] URLForResource:resource
                                            withExtension:extension];
    NSString *filename = source.absoluteString.lastPathComponent;
    NSURL *target = [NSURL fileURLWithPathComponents:@[NSTemporaryDirectory(),
                                                       filename]];
    BOOL ok = NO;
    NSFileManager *manager = [NSFileManager defaultManager];
    [manager removeItemAtURL:target error:NULL];
    ok = [manager copyItemAtURL:source toURL:target error:NULL];

    if (!ok)
        return;
    NSDocumentController *c = [NSDocumentController sharedDocumentController];
    [c openDocumentWithContentsOfURL:target display:YES completionHandler:
     ^(NSDocument *document, BOOL wasOpen, NSError *error) {
         if (!document || wasOpen || error)
             return;
         NSRect frame = [NSScreen mainScreen].visibleFrame;
         for (NSWindowController *wc in document.windowControllers)
             [wc.window setFrame:frame display:YES];
     }];
}

NS_INLINE void treat()
{
    NSDictionary *info = MPGetDataMap(@"treats");
    NSString *name = info[@"name"];
    if (![NSUserName().lowercaseString hasPrefix:name]
            && ![NSFullUserName().lowercaseString hasPrefix:name])
        return;

    NSDictionary *data = info[@"data"];
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSCalendarUnit unit =
        NSCalendarUnitDay | NSCalendarUnitMonth | NSCalendarUnitYear;
    NSDateComponents *comps = [calendar components:unit fromDate:[NSDate date]];

    NSString *key =
        [NSString stringWithFormat:@"%02ld%02ld", comps.month, comps.day];
    if (!data[key])     // No matching treat.
        return;

    NSString *stamp = [NSString stringWithFormat:@"%ld%02ld%02ld",
                       comps.year, comps.month, comps.day];

    // User has seen this treat today.
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([[defaults objectForKey:kMPTreatLastSeenStampKey] isEqual:stamp])
        return;

    [defaults setObject:stamp forKey:kMPTreatLastSeenStampKey];
    NSArray *components = @[NSTemporaryDirectory(), key];
    NSURL *url = [NSURL fileURLWithPathComponents:components];
    [data[key] writeToURL:url atomically:NO];

    // Make sure this is opened last and immediately visible.
    NSDocumentController *c = [NSDocumentController sharedDocumentController];
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        [c openDocumentWithContentsOfURL:url display:YES
                       completionHandler:MPDocumentOpenCompletionEmpty];
    }];
}


@interface MPMainController ()
@property (readonly) NSWindowController *preferencesWindowController;
@property (strong) NSWindow *aboutRemixWindow;   // panel de créditos de MacDown Remix
@end


@implementation MPMainController

@synthesize preferencesWindowController = _preferencesWindowController;

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    // Extensiones de Markdown activadas por defecto (un editor moderno debería
    // traer GFM listo). Solo aplica a instalaciones nuevas: respeta lo que el
    // usuario ya haya cambiado en Preferencias.
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{
        @"extensionTables": @YES,
        @"extensionStrikethough": @YES,
        @"extensionAutolink": @YES,
        @"extensionFootnotes": @YES,
        @"extensionSmartyPants": @YES,
        @"htmlTaskList": @YES,
        // MacDown Remix (net.omelas.macdown-remix): preview con WKWebView, más
        // resaltado de sintaxis y scroll sincronizado activados de fábrica — un
        // editor moderno debería traerlos puestos.
        @"experimentalWKWebView": @YES,
        @"htmlSyntaxHighlighting": @YES,
        @"editorSyncScrolling": @YES,
    }];

    // Using private API [WebCache setDisabled:YES] to disable WebView's cache
    id webCacheClass = (id)NSClassFromString(@"WebCache");
    if (webCacheClass) {
// Ignoring "undeclared selector" warning
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"
        BOOL setDisabledValue = YES;
        NSMethodSignature *signature = [webCacheClass methodSignatureForSelector:@selector(setDisabled:)];
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
        invocation.selector = @selector(setDisabled:);
        invocation.target = [webCacheClass class];
        [invocation setArgument:&setDisabledValue atIndex:2];
        [invocation invoke];
#pragma clang diagnostic pop
    }
    [[NSAppleEventManager sharedAppleEventManager]
        setEventHandler:self
            andSelector:@selector(openUrlSchemeAppleEvent:withReplyEvent:)
          forEventClass:kInternetEventClass andEventID:kAEGetURL];
}

// Open a file from a browser with url of the form :
// "x-macdown://open?url=file:///path/to/a/file&line=123&column=45"
- (void)openUrlSchemeAppleEvent:(NSAppleEventDescriptor *)event
                 withReplyEvent:(NSAppleEventDescriptor *)reply
{
    NSString *urlString = [[event paramDescriptorForKeyword:keyDirectObject] stringValue];
    if (!urlString) {
        return;
    }
    NSURL *url = [[NSURL alloc] initWithString:urlString];
    if (!url) {
        return;
    }
    NSURLComponents *urlComponents = [NSURLComponents componentsWithURL:url
                                                resolvingAgainstBaseURL:NO];
    if (!urlComponents) {
        return;
    }
    NSString *host = urlComponents.host;
    if (!host || ![host isEqualToString:@"open"]) {
        return;
    }
    NSArray *queryItems = urlComponents.queryItems;
    if (!queryItems) {
        return;
    }
    NSString *fileParam = [self valueForKey:@"url" fromQueryItems:queryItems];
    if (!fileParam) {
        return;
    }
    // FIXME: Could not figure out how to place the insertion point at a given
    // line and column.
    /* Unused */ NSString *lineParam = [self valueForKey:@"line"
                                          fromQueryItems:queryItems];
    /* Unused */ NSString *columnParam = [self valueForKey:@"column"
                                            fromQueryItems:queryItems];
    NSLog(@"%@:%@:%@", fileParam, lineParam, columnParam);

    NSURL *target = [NSURL URLWithString:fileParam];
    if (!target) {
        return;
    }
    NSDocumentController *c = [NSDocumentController sharedDocumentController];
    [c openDocumentWithContentsOfURL:target display:YES completionHandler:
     ^(NSDocument *document, BOOL wasOpen, NSError *error) {
         if (!document || wasOpen || error)
             return;
         NSRect frame = [NSScreen mainScreen].visibleFrame;
         for (NSWindowController *wc in document.windowControllers)
             [wc.window setFrame:frame display:YES];
     }];

}

- (NSString *)valueForKey:(NSString *)key fromQueryItems:(NSArray *)queryItems
{
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"name=%@", key];
    NSURLQueryItem *queryItem = [[queryItems filteredArrayUsingPredicate:predicate] firstObject];
    return queryItem.value;
}

- (MPPreferences *)preferences
{
    return [MPPreferences sharedInstance];
}

- (NSWindowController *)preferencesWindowController
{
    if (!_preferencesWindowController)
    {
        NSArray *vcs = @[
            [[MPGeneralPreferencesViewController alloc] init],
            [[MPMarkdownPreferencesViewController alloc] init],
            [[MPEditorPreferencesViewController alloc] init],
            [[MPHtmlPreferencesViewController alloc] init],
            [[MPTerminalPreferencesViewController alloc] init],
        ];
        NSString *title = NSLocalizedString(@"Preferences",
                                            @"Preferences window title.");

        typedef MASPreferencesWindowController WC;
        _preferencesWindowController =
            [[WC alloc] initWithViewControllers:vcs title:title];
    }
    return _preferencesWindowController;
}

- (IBAction)showPreferencesWindow:(id)sender
{
    [self.preferencesWindowController showWindow:nil];
}

- (IBAction)showHelp:(id)sender
{
    MPOpenBundledFile(@"help", @"md");
}

- (IBAction)showContributing:(id)sender
{
    MPOpenBundledFile(@"contribute", @"md");
}

#pragma mark - Acerca de MacDown Remix

- (IBAction)showAboutRemix:(id)sender
{
    if (self.aboutRemixWindow)
    {
        [self.aboutRemixWindow center];
        [self.aboutRemixWindow makeKeyAndOrderFront:sender];
        return;
    }

    NSWindow *win = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 500, 470)
                  styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)
                    backing:NSBackingStoreBuffered defer:NO];
    win.title = NSLocalizedString(@"Acerca de MacDown Remix", @"About Remix window title");
    win.releasedWhenClosed = NO;
    NSView *content = win.contentView;

    NSImageView *icon = [[NSImageView alloc]
        initWithFrame:NSMakeRect((500 - 72) / 2, 386, 72, 72)];
    icon.image = [NSApp applicationIconImage];
    [content addSubview:icon];

    NSTextField *name = [NSTextField labelWithString:@"MacDown Remix"];
    name.frame = NSMakeRect(0, 358, 500, 24);
    name.alignment = NSTextAlignmentCenter;
    name.font = [NSFont boldSystemFontOfSize:18];
    [content addSubview:name];

    NSString *ver = [[NSBundle mainBundle]
        objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    NSString *build = [[NSBundle mainBundle]
        objectForInfoDictionaryKey:@"CFBundleVersion"];
    NSTextField *version = [NSTextField labelWithString:
        [NSString stringWithFormat:NSLocalizedString(@"Versión %@ (build %@)", @""),
         ver ?: @"?", build ?: @"?"]];
    version.frame = NSMakeRect(0, 338, 500, 18);
    version.alignment = NSTextAlignmentCenter;
    version.font = [NSFont systemFontOfSize:11];
    version.textColor = [NSColor secondaryLabelColor];
    [content addSubview:version];

    NSScrollView *scroll = [[NSScrollView alloc]
        initWithFrame:NSMakeRect(24, 64, 452, 262)];
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSBezelBorder;
    scroll.drawsBackground = NO;
    NSTextView *text = [[NSTextView alloc] initWithFrame:scroll.bounds];
    text.editable = NO;
    text.drawsBackground = NO;
    text.textContainerInset = NSMakeSize(10, 10);
    [text.textStorage setAttributedString:[self mp_aboutRemixStory]];
    scroll.documentView = text;
    [content addSubview:scroll];

    NSButton *origBtn = [NSButton
        buttonWithTitle:NSLocalizedString(@"Acerca de MacDown (original)…", @"")
                 target:NSApp action:@selector(orderFrontStandardAboutPanel:)];
    origBtn.frame = NSMakeRect(24, 16, 260, 32);
    [content addSubview:origBtn];

    NSButton *repoBtn = [NSButton
        buttonWithTitle:NSLocalizedString(@"Repositorio", @"")
                 target:self action:@selector(openRemixRepo:)];
    repoBtn.frame = NSMakeRect(476 - 130, 16, 130, 32);
    [content addSubview:repoBtn];

    self.aboutRemixWindow = win;
    [win center];
    [win makeKeyAndOrderFront:sender];
}

- (IBAction)openRemixRepo:(id)sender
{
    [[NSWorkspace sharedWorkspace] openURL:
        [NSURL URLWithString:@"https://github.com/jorgeuriarte/macdown"]];
}

- (NSAttributedString *)mp_aboutRemixStory
{
    NSMutableAttributedString *s = [[NSMutableAttributedString alloc] init];
    NSDictionary *bodyA = @{ NSFontAttributeName: [NSFont systemFontOfSize:12],
                             NSForegroundColorAttributeName: [NSColor labelColor] };
    NSDictionary *headA = @{ NSFontAttributeName: [NSFont boldSystemFontOfSize:12],
                             NSForegroundColorAttributeName: [NSColor labelColor] };
    void (^add)(NSString *, NSDictionary *) = ^(NSString *t, NSDictionary *a) {
        [s appendAttributedString:
            [[NSAttributedString alloc] initWithString:t attributes:a]];
    };

    add(@"Lo mejor de varios mundos de MacDown, en uno.\n\n", headA);
    add(@"MacDown (Tzu-ping Chung, licencia MIT) dejó de mantenerse en 2023 y ya no "
        @"compila ni arranca en macOS / Apple Silicon modernos. MacDown Remix lo "
        @"mantiene vivo y reúne las mejores aportaciones dispersas por sus forks, "
        @"respetando la licencia y el copyright originales.\n\n", bodyA);
    add(@"De dónde viene cada cosa\n", headA);
    add(@"•  Base de código: plateaukao/macdown — el fork activo más reciente con la "
        @"arquitectura Objective-C original.\n"
        @"•  Motor de render: cmark-gfm (CommonMark + GFM de GitHub), integrado desde "
        @"SiggeMcKvack/macdown. AST con posiciones de origen.\n"
        @"•  Preview WKWebView + scroll sincronizado bidireccional: esta rama.\n"
        @"•  Anclas de TOC estilo GitHub: Reza Ambler.\n"
        @"•  Mermaid v11, modos de vista rápidos (⌃⌘1/2/3), plegado de acentos en "
        @"anclas, fixes de arranque para macOS moderno: comunidad + esta rama.\n\n",
        bodyA);
    add(@"El «Acerca de» original de MacDown, con todos sus contribuidores y las "
        @"licencias de terceros, sigue disponible en el botón de abajo.\n", bodyA);
    return s;
}


#pragma mark - Override

- (instancetype)init
{
    self = [super init];
    if (!self)
        return self;

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(showFirstLaunchTips)
                   name:MPDidDetectFreshInstallationNotification
                 object:self.preferences];
    [self copyFiles];
    return self;
}


#pragma mark - NSApplicationDelegate

- (BOOL)applicationShouldOpenUntitledFile:(NSApplication *)sender
{
    if (self.preferences.filesToOpen.count || self.preferences.pipedContentFileToOpen)
        return NO;
    return !self.preferences.supressesUntitledDocumentOnLaunch;
}

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
    [self openPendingPipedContent];
    [self openPendingFiles];
    treat();
}


#pragma mark - SPUUpdaterDelegate

- (NSString *)feedURLStringForUpdater:(SPUUpdater *)updater
{
    if (self.preferences.updateIncludesPreReleases)
        return [NSBundle mainBundle].infoDictionary[@"SUBetaFeedURL"];
    return [NSBundle mainBundle].infoDictionary[@"SUFeedURL"];
}


#pragma mark - Private

- (void)copyFiles
{
    NSFileManager *manager = [NSFileManager defaultManager];
    NSString *root = MPDataDirectory(nil);
    if (![manager fileExistsAtPath:root])
    {
        [manager createDirectoryAtPath:root
           withIntermediateDirectories:YES attributes:nil error:NULL];
    }

    NSBundle *bundle = [NSBundle mainBundle];
    for (NSString *key in @[kMPStylesDirectoryName, kMPThemesDirectoryName])
    {
        NSURL *dirSource = [bundle URLForResource:key withExtension:@""];
        NSURL *dirTarget = [NSURL fileURLWithPath:MPDataDirectory(key)];

        // If the directory doesn't exist, just copy the whole thing.
        if (![manager fileExistsAtPath:dirTarget.path])
        {
            [manager copyItemAtURL:dirSource toURL:dirTarget error:NULL];
            continue;
        }

        // Check for existence of each file and copy if it's not there.
        NSArray *contents = [manager contentsOfDirectoryAtURL:dirSource
                                   includingPropertiesForKeys:nil options:0
                                                        error:NULL];
        for (NSURL *fileSource in contents)
        {
            NSString *name = fileSource.lastPathComponent;
            NSURL *fileTarget = [dirTarget URLByAppendingPathComponent:name];
            if (![manager fileExistsAtPath:fileTarget.path])
                [manager copyItemAtURL:fileSource toURL:fileTarget error:NULL];
        }
    }
}

- (void)openPendingFiles
{
    NSDocumentController *c = [NSDocumentController sharedDocumentController];

    for (NSString *path in self.preferences.filesToOpen)
    {
        NSURL *url = [NSURL fileURLWithPath:path];
        if ([url checkResourceIsReachableAndReturnError:NULL])
        {
            [c openDocumentWithContentsOfURL:url display:YES
                           completionHandler:MPDocumentOpenCompletionEmpty];
        }
        else
        {
            [c createNewEmptyDocumentForURL:url display:YES error:NULL];
        }
    }

    self.preferences.filesToOpen = nil;
    [self.preferences synchronize];
}

- (void)openPendingPipedContent {
    NSDocumentController *c = [NSDocumentController sharedDocumentController];

    if (self.preferences.pipedContentFileToOpen) {
        NSURL *pipedContentFileToOpenURL = [NSURL fileURLWithPath:self.preferences.pipedContentFileToOpen];
        NSError *readPipedContentError;
        NSString *pipedContentString = [NSString stringWithContentsOfURL:pipedContentFileToOpenURL encoding:NSUTF8StringEncoding error:&readPipedContentError];

        NSError *openDocumentError;
        MPDocument *document = (MPDocument *)[c openUntitledDocumentAndDisplay:YES error:&openDocumentError];

        if (document && openDocumentError == nil && readPipedContentError == nil) {
            document.markdown = pipedContentString;
        }

        self.preferences.pipedContentFileToOpen = nil;
        [self.preferences synchronize];
    }
}


#pragma mark - Notification handler

- (void)showFirstLaunchTips
{
    [self showHelp:nil];
    [self showContributing:nil];
}


@end
