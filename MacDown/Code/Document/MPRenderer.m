//
//  MPRenderer.m
//  MacDown
//
//  Created by Tzu-ping Chung  on 26/6.
//  Copyright (c) 2014 Tzu-ping Chung . All rights reserved.
//

#import "MPRenderer.h"
#import <limits.h>
#import <cmark-gfm/cmark-gfm.h>
#import <cmark-gfm/cmark-gfm-core-extensions.h>
#import <HBHandlebars/HBHandlebars.h>
#import "cmark_gfm_rendering.h"
#import "NSJSONSerialization+File.h"
#import "NSObject+HTMLTabularize.h"
#import "NSString+Lookup.h"
#import "MPUtilities.h"
#import "MPAsset.h"
#import "MPPreferences.h"

// Warning: If the version of MathJax is ever updated, please check the status
// of https://github.com/mathjax/MathJax/issues/548. If the fix has been merged
// in to MathJax, then the WebResourceLoadDelegate can be removed from MPDocument
// and MathJax.js can be removed from this project.
static NSString * const kMPMathJaxCDN =
    @"https://cdnjs.cloudflare.com/ajax/libs/mathjax/2.7.3/MathJax.js"
    @"?config=TeX-AMS-MML_HTMLorMML";
static NSString * const kMPPrismScriptDirectory = @"Prism/components";
static NSString * const kMPPrismThemeDirectory = @"Prism/themes";
static NSString * const kMPPrismPluginDirectory = @"Prism/plugins";
static int kMPRendererTOCLevel = 6;  // h1 to h6.


NS_INLINE NSURL *MPExtensionURL(NSString *name, NSString *extension)
{
    NSBundle *bundle = [NSBundle mainBundle];
    NSURL *url = [bundle URLForResource:name withExtension:extension
                           subdirectory:@"Extensions"];
    return url;
}

NS_INLINE NSURL *MPPrismPluginURL(NSString *name, NSString *extension)
{
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *dirPath =
        [NSString stringWithFormat:@"%@/%@", kMPPrismPluginDirectory, name];

    NSString *filename = [NSString stringWithFormat:@"prism-%@.min", name];
    NSURL *url = [bundle URLForResource:filename withExtension:extension
                           subdirectory:dirPath];
    if (url)
        return url;

    filename = [NSString stringWithFormat:@"prism-%@", name];
    url = [bundle URLForResource:filename withExtension:extension
                    subdirectory:dirPath];
    return url;
}

NS_INLINE NSArray *MPPrismScriptURLsForLanguage(NSString *language)
{
    NSURL *baseUrl = nil;
    NSURL *extraUrl = nil;
    NSBundle *bundle = [NSBundle mainBundle];

    language = [language lowercaseString];
    NSString *baseFileName =
        [NSString stringWithFormat:@"prism-%@", language];
    NSString *extraFileName =
        [NSString stringWithFormat:@"prism-%@-extras", language];

    for (NSString *ext in @[@"min.js", @"js"])
    {
        if (!baseUrl)
        {
            baseUrl = [bundle URLForResource:baseFileName withExtension:ext
                                subdirectory:kMPPrismScriptDirectory];
        }
        if (!extraUrl)
        {
            extraUrl = [bundle URLForResource:extraFileName withExtension:ext
                                 subdirectory:kMPPrismScriptDirectory];
        }
    }

    NSMutableArray *urls = [NSMutableArray array];
    if (baseUrl)
        [urls addObject:baseUrl];
    if (extraUrl)
        [urls addObject:extraUrl];
    return urls;
}

NS_INLINE NSString *MPHTMLFromMarkdown(
    NSString *text, NSArray<NSString *> *extensions, int options,
    MPCmarkRenderFlags renderFlags, BOOL hasTOC, NSString *frontMatter,
    MPLanguageCallback languageCallback,
    NSMutableArray<NSString *> *outLanguages)
{
    NSString *result = MPCmarkGFMToHTML(
        text, extensions, options, renderFlags,
        languageCallback, outLanguages);

    if (hasTOC)
    {
        NSString *toc = MPCmarkGFMGenerateTOC(
            text, extensions, options, kMPRendererTOCLevel);

        static NSRegularExpression *tocRegex = nil;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            NSString *pattern =
                @"<p.*?>\\s*\\[TOC\\]\\s*</p>";
            NSRegularExpressionOptions ops =
                NSRegularExpressionCaseInsensitive;
            tocRegex = [[NSRegularExpression alloc]
                initWithPattern:pattern options:ops
                error:NULL];
        });
        NSRange replaceRange = NSMakeRange(0, result.length);
        result = [tocRegex
            stringByReplacingMatchesInString:result options:0
            range:replaceRange withTemplate:toc];
    }
    if (frontMatter)
        result = [NSString stringWithFormat:@"%@\n%@",
                  frontMatter, result];

    return result;
}

NS_INLINE NSString *MPGetHTML(
    NSString *title, NSString *body, NSArray *styles, MPAssetOption styleopt,
    NSArray *scripts, MPAssetOption scriptopt)
{
    NSMutableArray *styleTags = [NSMutableArray array];
    NSMutableArray *scriptTags = [NSMutableArray array];
    for (MPStyleSheet *style in styles)
    {
        NSString *s = [style htmlForOption:styleopt];
        if (s)
            [styleTags addObject:s];
    }
    for (MPScript *script in scripts)
    {
        NSString *s = [script htmlForOption:scriptopt];
        if (s)
            [scriptTags addObject:s];
    }

    MPPreferences *preferences = [MPPreferences sharedInstance];

    static NSString *f = nil;
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        NSBundle *bundle = [NSBundle mainBundle];
        NSURL *url = [bundle URLForResource:preferences.htmlTemplateName
                              withExtension:@".handlebars"
                               subdirectory:@"Templates"];
        f = [NSString stringWithContentsOfURL:url
                                     encoding:NSUTF8StringEncoding error:NULL];
    });
    NSCAssert(f.length, @"Could not read template");

    NSString *titleTag = @"";
    if (title.length)
        titleTag = [NSString stringWithFormat:@"<title>%@</title>", title];

    NSDictionary *context = @{
        @"title": title ? title : @"",
        @"titleTag": titleTag ? titleTag : @"",
        @"styleTags": styleTags ? styleTags : @[],
        @"body": body ? body : @"",
        @"scriptTags": scriptTags ? scriptTags : @[],
    };
    NSString *html = [HBHandlebars renderTemplateString:f withContext:context
                                                  error:NULL];
    return html;
}

NS_INLINE BOOL MPAreNilableStringsEqual(NSString *s1, NSString *s2)
{
    // The == part takes care of cases where s1 and s2 are both nil.
    return ([s1 isEqualToString:s2] || s1 == s2);
}


@interface MPRenderer ()

@property (strong) NSMutableArray *currentLanguages;
@property (readonly) NSArray *baseStylesheets;
@property (readonly) NSArray *prismStylesheets;
@property (readonly) NSArray *prismScripts;
@property (readonly) NSArray *mathjaxScripts;
@property (readonly) NSArray *mermaidScripts;
@property (readonly) NSArray *graphvizScripts;
@property (readonly) NSArray *stylesheets;
@property (readonly) NSArray *scripts;
@property (copy) NSString *currentHtml;
@property (strong) NSOperationQueue *parseQueue;
@property int extensions;
@property MPCmarkRenderFlags cmarkRenderFlags;
@property BOOL smartypants;
@property BOOL TOC;
@property (copy) NSString *styleName;
@property BOOL frontMatter;
@property BOOL syntaxHighlighting;
@property BOOL mermaid;
@property BOOL graphviz;
@property MPCodeBlockAccessoryType codeBlockAccesory;
@property BOOL lineNumbers;
@property BOOL manualRender;
@property (copy) NSString *highlightingThemeName;

@end


NS_INLINE void add_to_languages(
    NSString *lang, NSMutableArray *languages,
    NSDictionary *languageMap)
{
    NSUInteger index = [languages indexOfObject:lang];
    if (index != NSNotFound)
        [languages removeObjectAtIndex:index];
    [languages insertObject:lang atIndex:0];

    id require = languageMap[lang][@"require"];
    if ([require isKindOfClass:[NSString class]])
    {
        add_to_languages(require, languages, languageMap);
    }
    else if ([require isKindOfClass:[NSArray class]])
    {
        for (NSString *lang in require)
            add_to_languages(lang, languages, languageMap);
    }
    else if (require)
    {
        NSLog(@"Unknown Prism langauge requirement "
              @"%@ dropped for unknown format", require);
    }
}

// Build a language callback block that resolves Prism aliases and
// tracks language dependencies.
NS_INLINE MPLanguageCallback MPMakeLanguageCallback(
    MPRenderer *renderer)
{
    static NSDictionary *aliasMap = nil;
    static NSDictionary *languageMap = nil;
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        NSBundle *bundle = [NSBundle mainBundle];
        NSURL *url = [bundle URLForResource:@"syntax_highlighting"
                              withExtension:@"json"];
        NSDictionary *info =
            [NSJSONSerialization JSONObjectWithFileAtURL:url
                                                options:0
                                                  error:NULL];
        aliasMap = info[@"aliases"];

        url = [bundle URLForResource:@"components"
                       withExtension:@"js"
                        subdirectory:@"Prism"];
        NSString *code = [NSString
            stringWithContentsOfURL:url
            encoding:NSUTF8StringEncoding error:NULL];
        NSDictionary *comp =
            MPGetObjectFromJavaScript(code, @"components");
        languageMap = comp[@"languages"];
    });

    return ^NSString *(NSString *lang) {
        NSString *resolved = aliasMap[lang];
        if (!resolved)
            resolved = lang;

        add_to_languages(
            resolved, renderer.currentLanguages, languageMap);

        // Return mapped name if alias was found.
        return [resolved isEqualToString:lang] ? nil : resolved;
    };
}


@implementation MPRenderer

- (instancetype)init
{
    self = [super init];
    if (!self)
        return nil;

    self.currentHtml = @"";
    self.currentLanguages = [NSMutableArray array];
    self.parseQueue = [[NSOperationQueue alloc] init];
    self.parseQueue.maxConcurrentOperationCount = 1; // Serial queue

    return self;
}

#pragma mark - Accessor

- (NSArray *)baseStylesheets
{
    NSString *defaultStyleName =
        MPStylePathForName([self.delegate rendererStyleName:self]);
    if (!defaultStyleName)
        return @[];
    NSURL *defaultStyle = [NSURL fileURLWithPath:defaultStyleName];
    NSMutableArray *stylesheets = [NSMutableArray array];
    [stylesheets addObject:[MPStyleSheet CSSWithURL:defaultStyle]];
    return stylesheets;
}

- (NSArray *)prismStylesheets
{
    NSString *name = [self.delegate rendererHighlightingThemeName:self];
    MPAsset *stylesheet =
        [MPStyleSheet CSSWithURL:MPHighlightingThemeURLForName(name)];

    NSMutableArray *stylesheets = [NSMutableArray arrayWithObject:stylesheet];

    if (self.cmarkRenderFlags & MPCmarkRenderFlagLineNumbers)
    {
        NSURL *url = MPPrismPluginURL(@"line-numbers", @"css");
        [stylesheets addObject:[MPStyleSheet CSSWithURL:url]];
    }
    if ([self.delegate rendererCodeBlockAccesory:self]
        == MPCodeBlockAccessoryLanguageName)
    {
        NSURL *url = MPPrismPluginURL(@"show-language", @"css");
        [stylesheets addObject:[MPStyleSheet CSSWithURL:url]];
    }

    return stylesheets;
}

- (NSArray *)prismScripts
{
    NSBundle *bundle = [NSBundle mainBundle];
    NSURL *url = [bundle URLForResource:@"prism-core.min" withExtension:@"js"
                           subdirectory:kMPPrismScriptDirectory];
    MPAsset *script = [MPScript javaScriptWithURL:url];
    NSMutableArray *scripts = [NSMutableArray arrayWithObject:script];
    for (NSString *language in self.currentLanguages)
    {
        for (NSURL *url in MPPrismScriptURLsForLanguage(language))
            [scripts addObject:[MPScript javaScriptWithURL:url]];
    }

    if (self.cmarkRenderFlags & MPCmarkRenderFlagLineNumbers)
    {
        NSURL *url = MPPrismPluginURL(@"line-numbers", @"js");
        [scripts addObject:[MPScript javaScriptWithURL:url]];
    }
    if ([self.delegate rendererCodeBlockAccesory:self]
        == MPCodeBlockAccessoryLanguageName)
    {
        NSURL *url = MPPrismPluginURL(@"show-language", @"js");
        [scripts addObject:[MPScript javaScriptWithURL:url]];
    }
    return scripts;
}

- (NSArray *)mathjaxScripts
{
    NSMutableArray *scripts = [NSMutableArray array];
    NSURL *url = [NSURL URLWithString:kMPMathJaxCDN];
    NSBundle *bundle = [NSBundle mainBundle];
    MPEmbeddedScript *script =
        [MPEmbeddedScript assetWithURL:[bundle URLForResource:@"init"
                                                withExtension:@"js"
                                                 subdirectory:@"MathJax"]
                               andType:kMPMathJaxConfigType];
    [scripts addObject:script];
    [scripts addObject:[MPScript javaScriptWithURL:url]];
    return scripts;
}

- (BOOL)currentHTMLHasMermaid
{
    // Mermaid fenced blocks render to <code class="language-mermaid">. Only pull in the
    // (multi-megabyte) mermaid library when the current document actually contains one.
    return [self.currentHtml rangeOfString:@"language-mermaid"].location != NSNotFound;
}

- (NSArray *)mermaidScripts
{
    // TODO
    NSMutableArray *scripts = [NSMutableArray array];

    {
        NSURL *url = MPExtensionURL(@"mermaid.min", @"js");
        [scripts addObject:[MPScript javaScriptWithURL:url]];
    }
    {
        NSURL *url = MPExtensionURL(@"mermaid.init", @"js");
        [scripts addObject:[MPScript javaScriptWithURL:url]];
    }
    
    return scripts;
}

- (NSArray *)graphvizScripts
{
    // TODO
    NSMutableArray *scripts = [NSMutableArray array];

    {
        NSURL *url = MPExtensionURL(@"viz", @"js");
        [scripts addObject:[MPScript javaScriptWithURL:url]];
    }
    {
        NSURL *url = MPExtensionURL(@"viz.init", @"js");
        [scripts addObject:[MPScript javaScriptWithURL:url]];
    }
    
    return scripts;
}

- (NSArray *)stylesheets
{
    id<MPRendererDelegate> delegate = self.delegate;

    NSMutableArray *stylesheets = [self.baseStylesheets mutableCopy];
    if ([delegate rendererHasSyntaxHighlighting:self])
    {
        [stylesheets addObjectsFromArray:self.prismStylesheets];
    }
    // Mermaid v11 styles diagrams entirely via the theme passed to
    // mermaid.initialize() (inline in the rendered SVG), so no external mermaid
    // stylesheet is injected here — the old forest.css hardcoded dark ink that
    // was invisible on dark backgrounds.

    if ([delegate rendererCodeBlockAccesory:self] == MPCodeBlockAccessoryCustom)
    {
        NSURL *url = MPExtensionURL(@"show-information", @"css");
        [stylesheets addObject:[MPStyleSheet CSSWithURL:url]];
    }
    return stylesheets;
}

- (NSArray *)scripts
{
    id<MPRendererDelegate> d = self.delegate;
    NSMutableArray *scripts = [NSMutableArray array];
    if ([d rendererHasSyntaxHighlighting:self])
    {
        [scripts addObjectsFromArray:self.prismScripts];
        // graphviz
        if ([d rendererHasGraphviz:self])
        {
            [scripts addObjectsFromArray:self.graphvizScripts];
        }
    }
    // mermaid (independent of syntax highlighting; only when a diagram is present)
    if ([d rendererHasMermaid:self] && [self currentHTMLHasMermaid])
    {
        [scripts addObjectsFromArray:self.mermaidScripts];
    }
    if ([d rendererHasMathJax:self])
        [scripts addObjectsFromArray:self.mathjaxScripts];
    return scripts;
}

#pragma mark - Public
    
- (void)parseAndRenderWithMaxDelay:(NSTimeInterval)maxDelay {
    [self.parseQueue cancelAllOperations];
    [self.parseQueue addOperationWithBlock:^{
        // Fetch the markdown (from the main thread)
        __block NSString *markdown;
        dispatch_sync(dispatch_get_main_queue(), ^{
            markdown = [[self.dataSource rendererMarkdown:self] copy];
        });

        // Parse in backgound
        [self parseMarkdown:markdown];
        
        // Wait untils is renderer has finished loading OR until the maxDelay has passed
        // This should result in overall faster update times
        NSDate *start = [NSDate date];
        __block BOOL rendererIsLoading = true;
        while (rendererIsLoading || [start timeIntervalSinceNow] >= maxDelay) {
            dispatch_sync(dispatch_get_main_queue(), ^{
                rendererIsLoading = [self.dataSource rendererLoading];
            });
        }
        
        // Render on main thread
        dispatch_async(dispatch_get_main_queue(), ^{
            [self render];
        });
    }];
}

- (void)parseAndRenderNow
{
    [self parseAndRenderWithMaxDelay:0];
}

- (void)parseAndRenderLater
{
    [self parseAndRenderWithMaxDelay:0.5];
}

- (void)parseIfPreferencesChanged
{
    id<MPRendererDelegate> delegate = self.delegate;
    if ([delegate rendererExtensions:self] != self.extensions
            || [delegate rendererHasSmartyPants:self] != self.smartypants
            || [delegate rendererRendersTOC:self] != self.TOC
            || [delegate rendererDetectsFrontMatter:self] != self.frontMatter)
    {
        [self parseMarkdown:[self.dataSource rendererMarkdown:self]];
    }
}

- (void)parseMarkdown:(NSString *)markdown {
    [self.currentLanguages removeAllObjects];

    id<MPRendererDelegate> delegate = self.delegate;
    int extensions = [delegate rendererExtensions:self];
    BOOL smartypants = [delegate rendererHasSmartyPants:self];
    BOOL hasFrontMatter = [delegate rendererDetectsFrontMatter:self];
    BOOL hasTOC = [delegate rendererRendersTOC:self];

    id frontMatter = nil;
    if (hasFrontMatter)
    {
        NSUInteger offset = 0;
        frontMatter = [markdown frontMatter:&offset];
        markdown = [markdown substringFromIndex:offset];
    }

    // Build cmark-gfm options.
    int cmarkOptions = CMARK_OPT_DEFAULT;
    if (smartypants)
        cmarkOptions |= CMARK_OPT_SMART;

    // Get extension names and render flags from delegate.
    NSArray<NSString *> *extNames =
        [delegate rendererCmarkExtensions:self];
    MPCmarkRenderFlags renderFlags =
        [delegate rendererCmarkRenderFlags:self];
    if ([delegate rendererHasHardWrap:self])
        cmarkOptions |= CMARK_OPT_HARDBREAKS;
    if ([delegate rendererHasFootnotes:self])
        cmarkOptions |= CMARK_OPT_FOOTNOTES;

    MPLanguageCallback langCallback =
        MPMakeLanguageCallback(self);

    self.currentHtml = MPHTMLFromMarkdown(
        markdown, extNames, cmarkOptions, renderFlags,
        hasTOC, [frontMatter HTMLTable],
        langCallback, self.currentLanguages);
    self.cmarkRenderFlags = renderFlags;

    self.extensions = extensions;
    self.smartypants = smartypants;
    self.TOC = hasTOC;
    self.frontMatter = hasFrontMatter;
}

- (void)renderIfPreferencesChanged
{
    BOOL changed = NO;
    id<MPRendererDelegate> d = self.delegate;
    if ([d rendererHasSyntaxHighlighting:self] != self.syntaxHighlighting)
        changed = YES;
    else if ([d rendererHasMermaid:self] != self.mermaid)
        changed = YES;
    else if ([d rendererHasGraphviz:self] != self.graphviz)
        changed = YES;
    else if (!MPAreNilableStringsEqual(
            [d rendererHighlightingThemeName:self], self.highlightingThemeName))
        changed = YES;
    else if (!MPAreNilableStringsEqual(
            [d rendererStyleName:self], self.styleName))
        changed = YES;
    else if ([d rendererCodeBlockAccesory:self] != self.codeBlockAccesory)
        changed = YES;

    if (changed)
        [self render];
}

- (void)render
{
    id<MPRendererDelegate> delegate = self.delegate;

    NSString *title = [self.dataSource rendererHTMLTitle:self];
    NSString *html = MPGetHTML(
        title, self.currentHtml, self.stylesheets, MPAssetFullLink,
        self.scripts, MPAssetFullLink);
    [delegate renderer:self didProduceHTMLOutput:html];

    self.styleName = [delegate rendererStyleName:self];
    self.syntaxHighlighting = [delegate rendererHasSyntaxHighlighting:self];
    self.mermaid = [delegate rendererHasMermaid:self];
    self.graphviz = [delegate rendererHasGraphviz:self];
    self.highlightingThemeName = [delegate rendererHighlightingThemeName:self];
    self.codeBlockAccesory = [delegate rendererCodeBlockAccesory:self];
}

- (NSString *)HTMLForExportWithStyles:(BOOL)withStyles
                         highlighting:(BOOL)withHighlighting
{
    MPAssetOption stylesOption = MPAssetNone;
    MPAssetOption scriptsOption = MPAssetNone;
    NSMutableArray *styles = [NSMutableArray array];
    NSMutableArray *scripts = [NSMutableArray array];

    if (withStyles)
    {
        stylesOption = MPAssetEmbedded;
        [styles addObjectsFromArray:self.baseStylesheets];
    }
    if (withHighlighting)
    {
        stylesOption = MPAssetEmbedded;
        scriptsOption = MPAssetEmbedded;
        [styles addObjectsFromArray:self.prismStylesheets];
        [scripts addObjectsFromArray:self.prismScripts];
        if ([self.delegate rendererHasGraphviz:self])
        {
            [scripts addObjectsFromArray:self.graphvizScripts];
        }

    }
    // mermaid (independent of syntax highlighting; only when a diagram is present)
    if ([self.delegate rendererHasMermaid:self] && [self currentHTMLHasMermaid])
    {
        scriptsOption = MPAssetEmbedded;
        // Mermaid v11 themes the SVG inline via mermaid.initialize(); no external
        // mermaid stylesheet is needed (see -stylesheets).
        [scripts addObjectsFromArray:self.mermaidScripts];
    }
    if ([self.delegate rendererHasMathJax:self])
    {
        scriptsOption = MPAssetEmbedded;
        [scripts addObjectsFromArray:self.mathjaxScripts];
    }

    NSString *title = [self.dataSource rendererHTMLTitle:self];
    if (!title)
        title = @"";
    NSString *html = MPGetHTML(
        title, self.currentHtml, styles, stylesOption, scripts, scriptsOption);
    return html;
}

@end
