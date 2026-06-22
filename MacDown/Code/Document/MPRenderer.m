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

// Defined further down; forward-declared here because MPHTMLFromMarkdown (below)
// calls it before its definition. Internal — not exposed in the header.
@interface MPRenderer ()
+ (NSString *)HTMLByAddingTOCHeadingIDs:(NSString *)html;
@end

#pragma mark - Protección de math (cmark-gfm no conoce math)

// Rangos de bloques de código fenced (```/~~~), para no extraer math dentro.
static NSArray<NSValue *> *MPFencedCodeRanges(NSString *md)
{
    static NSRegularExpression *re = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        re = [NSRegularExpression regularExpressionWithPattern:
            @"(?ms)^[ \\t]*(`{3,}|~{3,}).*?^[ \\t]*\\1[ \\t]*$" options:0 error:NULL];
    });
    NSMutableArray<NSValue *> *ranges = [NSMutableArray array];
    [re enumerateMatchesInString:md options:0 range:NSMakeRange(0, md.length)
        usingBlock:^(NSTextCheckingResult *m, NSMatchingFlags f, BOOL *s) {
            [ranges addObject:[NSValue valueWithRange:m.range]];
        }];
    return ranges;
}

static BOOL MPLocationInRanges(NSUInteger loc, NSArray<NSValue *> *ranges)
{
    for (NSValue *v in ranges) {
        NSRange r = v.rangeValue;
        if (loc >= r.location && loc < r.location + r.length)
            return YES;
    }
    return NO;
}

// Sustituye las fórmulas por placeholders inertes (que cmark-gfm no mangla) y las
// guarda en outSpans listas para MathJax: display como $$..$$, inline como \(..\)
// (delimitador seguro, así no hay que activar el $ naive). Heurística anti-monedas
// para el inline $..$: apertura pegada a no-espacio/no-dígito; cierre pegado a
// no-espacio y no seguido de dígito (descarta $5, $10, $20,000). No toca código.
static NSString *MPProtectMath(NSString *md, NSMutableArray<NSString *> *outSpans)
{
    static NSRegularExpression *reList[4]; static BOOL reDisplay[4];
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSRegularExpressionOptions dot = NSRegularExpressionDotMatchesLineSeparators;
        reList[0] = [NSRegularExpression regularExpressionWithPattern:@"(?<!\\\\)\\$\\$(.+?)\\$\\$" options:dot error:NULL]; reDisplay[0]=YES;
        reList[1] = [NSRegularExpression regularExpressionWithPattern:@"(?<!\\\\)\\\\\\[(.+?)\\\\\\]" options:dot error:NULL]; reDisplay[1]=YES;
        reList[2] = [NSRegularExpression regularExpressionWithPattern:@"(?<!\\\\)\\\\\\((.+?)\\\\\\)" options:dot error:NULL]; reDisplay[2]=NO;
        reList[3] = [NSRegularExpression regularExpressionWithPattern:@"(?<!\\\\)\\$(?=[^\\s\\d$])([^\\n$]*?\\S)\\$(?!\\d)" options:0 error:NULL]; reDisplay[3]=NO;
    });

    NSArray<NSValue *> *code = MPFencedCodeRanges(md);
    NSMutableArray<NSValue *> *ranges = [NSMutableArray array];
    NSMutableArray<NSString *> *spans = [NSMutableArray array];

    for (int i = 0; i < 4; i++) {
        NSRegularExpression *re = reList[i]; BOOL disp = reDisplay[i];
        [re enumerateMatchesInString:md options:0 range:NSMakeRange(0, md.length)
            usingBlock:^(NSTextCheckingResult *m, NSMatchingFlags f, BOOL *s) {
                if (MPLocationInRanges(m.range.location, code))
                    return;
                NSString *inner = [md substringWithRange:[m rangeAtIndex:1]];
                NSString *span = disp ? [NSString stringWithFormat:@"$$%@$$", inner]
                                      : [NSString stringWithFormat:@"\\(%@\\)", inner];
                [ranges addObject:[NSValue valueWithRange:m.range]];
                [spans addObject:span];
            }];
    }
    if (ranges.count == 0)
        return md;

    // Ordena por posición e ignora solapamientos (display delimita sobre inline).
    NSMutableArray<NSNumber *> *idx = [NSMutableArray array];
    for (NSUInteger i = 0; i < ranges.count; i++) [idx addObject:@(i)];
    [idx sortUsingComparator:^NSComparisonResult(NSNumber *a, NSNumber *b) {
        NSUInteger la = [ranges[a.unsignedIntegerValue] rangeValue].location;
        NSUInteger lb = [ranges[b.unsignedIntegerValue] rangeValue].location;
        return (la < lb) ? NSOrderedAscending : (la > lb ? NSOrderedDescending : NSOrderedSame);
    }];

    NSMutableArray<NSValue *> *keptRanges = [NSMutableArray array];
    NSMutableArray<NSString *> *keptSpans = [NSMutableArray array];
    NSUInteger lastEnd = 0;
    for (NSNumber *n in idx) {
        NSRange r = [ranges[n.unsignedIntegerValue] rangeValue];
        if (r.location < lastEnd) continue;                 // solapa → descarta
        [keptRanges addObject:[NSValue valueWithRange:r]];
        [keptSpans addObject:spans[n.unsignedIntegerValue]];
        lastEnd = r.location + r.length;
    }

    // Reemplaza de atrás hacia delante por placeholders inertes.
    NSMutableString *out = [md mutableCopy];
    for (NSInteger i = keptRanges.count - 1; i >= 0; i--) {
        NSRange r = [keptRanges[i] rangeValue];
        [outSpans insertObject:keptSpans[i] atIndex:0];     // mantiene el orden
        NSString *ph = [NSString stringWithFormat:@"xMACDOWNMATHx%ldx", (long)i];
        [out replaceCharactersInRange:r withString:ph];
    }
    return [out copy];
}

// Reinserta el math tras renderizar. Escapa &<> del contenido (como haría cmark)
// para que el navegador no lo lea como HTML; MathJax recibe el texto correcto.
static NSString *MPReinsertMath(NSString *html, NSArray<NSString *> *spans)
{
    if (spans.count == 0)
        return html;
    NSMutableString *out = [html mutableCopy];
    for (NSInteger i = spans.count - 1; i >= 0; i--) {
        NSString *esc = [[[spans[i]
            stringByReplacingOccurrencesOfString:@"&" withString:@"&amp;"]
            stringByReplacingOccurrencesOfString:@"<" withString:@"&lt;"]
            stringByReplacingOccurrencesOfString:@">" withString:@"&gt;"];
        NSString *ph = [NSString stringWithFormat:@"xMACDOWNMATHx%ldx", (long)i];
        [out replaceOccurrencesOfString:ph withString:esc options:0
                                  range:NSMakeRange(0, out.length)];
    }
    return [out copy];
}

#pragma mark - Extensiones inline propias (cmark-gfm no las trae)

// Rangos de spans de código inline (`...`), para no tocar ==/^ dentro de código.
static NSArray<NSValue *> *MPInlineCodeRanges(NSString *md)
{
    static NSRegularExpression *re = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        re = [NSRegularExpression regularExpressionWithPattern:
            @"(`+)([^\\n]+?)\\1" options:0 error:NULL];
    });
    NSMutableArray<NSValue *> *ranges = [NSMutableArray array];
    [re enumerateMatchesInString:md options:0 range:NSMakeRange(0, md.length)
        usingBlock:^(NSTextCheckingResult *m, NSMatchingFlags f, BOOL *s) {
            [ranges addObject:[NSValue valueWithRange:m.range]];
        }];
    return ranges;
}

// Resaltado ==texto== -> <mark> y superíndice ^texto^ -> <sup>: dos extensiones que
// hoedown tenía y cmark-gfm no. Se aplican sobre el markdown (cmark va con UNSAFE, así
// que el HTML inline pasa) y el interior se procesa como markdown normal. Se respetan
// bloques y spans de código. Importante: llamar DESPUÉS de proteger el math, así el ^
// de las fórmulas (ya como placeholder) no se confunde con superíndice.
static NSString *MPApplyInlineExtensions(NSString *md)
{
    static NSRegularExpression *reList[2];
    static NSString *tmplList[2];
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // Resaltado: ==texto==, contenido sin espacios pegados a los delimitadores.
        reList[0] = [NSRegularExpression regularExpressionWithPattern:
            @"(?<!=)==(?=\\S)([^\\n]*?\\S)==(?!=)" options:0 error:NULL];
        tmplList[0] = @"<mark>$1</mark>";
        // Superíndice: ^texto^, sin espacios ni ^ dentro.
        reList[1] = [NSRegularExpression regularExpressionWithPattern:
            @"(?<!\\^)\\^(?=\\S)([^\\s^]+?)\\^(?!\\^)" options:0 error:NULL];
        tmplList[1] = @"<sup>$1</sup>";
    });

    NSMutableArray<NSValue *> *code = [NSMutableArray array];
    [code addObjectsFromArray:MPFencedCodeRanges(md)];
    [code addObjectsFromArray:MPInlineCodeRanges(md)];

    // Recoge los reemplazos (rango -> html) fuera de código.
    NSMutableArray<NSValue *> *ranges = [NSMutableArray array];
    NSMutableArray<NSString *> *repls = [NSMutableArray array];
    for (int i = 0; i < 2; i++) {
        NSRegularExpression *re = reList[i];
        NSString *tmpl = tmplList[i];
        [re enumerateMatchesInString:md options:0 range:NSMakeRange(0, md.length)
            usingBlock:^(NSTextCheckingResult *m, NSMatchingFlags f, BOOL *s) {
                if (MPLocationInRanges(m.range.location, code))
                    return;
                NSString *html = [re replacementStringForResult:m inString:md
                                                         offset:0 template:tmpl];
                [ranges addObject:[NSValue valueWithRange:m.range]];
                [repls addObject:html];
            }];
    }
    if (ranges.count == 0)
        return md;

    // Ordena por posición, descarta solapamientos, reemplaza de atrás hacia delante.
    NSMutableArray<NSNumber *> *idx = [NSMutableArray array];
    for (NSUInteger i = 0; i < ranges.count; i++) [idx addObject:@(i)];
    [idx sortUsingComparator:^NSComparisonResult(NSNumber *a, NSNumber *b) {
        NSUInteger la = [ranges[a.unsignedIntegerValue] rangeValue].location;
        NSUInteger lb = [ranges[b.unsignedIntegerValue] rangeValue].location;
        return (la < lb) ? NSOrderedAscending : (la > lb ? NSOrderedDescending : NSOrderedSame);
    }];

    NSMutableArray<NSValue *> *keptR = [NSMutableArray array];
    NSMutableArray<NSString *> *keptV = [NSMutableArray array];
    NSUInteger lastEnd = 0;
    for (NSNumber *n in idx) {
        NSRange r = [ranges[n.unsignedIntegerValue] rangeValue];
        if (r.location < lastEnd) continue;
        [keptR addObject:[NSValue valueWithRange:r]];
        [keptV addObject:repls[n.unsignedIntegerValue]];
        lastEnd = r.location + r.length;
    }

    NSMutableString *out = [md mutableCopy];
    for (NSInteger i = keptR.count - 1; i >= 0; i--) {
        NSRange r = [keptR[i] rangeValue];
        [out replaceCharactersInRange:r withString:keptV[i]];
    }
    return [out copy];
}

NS_INLINE NSString *MPHTMLFromMarkdown(
    NSString *text, NSArray<NSString *> *extensions, int options,
    MPCmarkRenderFlags renderFlags, BOOL hasTOC, BOOL hasMathJax, NSString *frontMatter,
    MPLanguageCallback languageCallback,
    NSMutableArray<NSString *> *outLanguages)
{
    // Protege el math antes de cmark-gfm (que lo mangla) y lo reinserta después.
    NSMutableArray<NSString *> *mathSpans = nil;
    if (hasMathJax)
    {
        mathSpans = [NSMutableArray array];
        text = MPProtectMath(text, mathSpans);
    }

    // Extensiones propias (resaltado ==, superíndice ^) tras proteger el math.
    text = MPApplyInlineExtensions(text);

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

        // The [TOC] macro emits "#toc_N" links; cmark-gfm renders headings
        // without ids, so give each heading its matching id="toc_N".
        result = [MPRenderer HTMLByAddingTOCHeadingIDs:result];
    }

    // Give headings GitHub-style id anchors so in-document TOC links resolve.
    result = [MPRenderer HTMLByAddingHeadingAnchors:result];

    // Reinserta las fórmulas protegidas (ya como $$..$$ / \(..\) para MathJax).
    if (mathSpans.count)
        result = MPReinsertMath(result, mathSpans);

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

// Vista previa de un fragmento (edición inline): mismo motor que el documento, pero sin
// TOC ni front-matter (un fragmento no los resuelve). No toca el estado del renderer.
- (NSString *)previewHTMLForMarkdownFragment:(NSString *)markdown
{
    if (![markdown isKindOfClass:[NSString class]])
        return @"";
    id<MPRendererDelegate> delegate = self.delegate;

    int cmarkOptions = CMARK_OPT_DEFAULT;
    if ([delegate rendererHasSmartyPants:self])
        cmarkOptions |= CMARK_OPT_SMART;
    if ([delegate rendererHasHardWrap:self])
        cmarkOptions |= CMARK_OPT_HARDBREAKS;
    if ([delegate rendererHasFootnotes:self])
        cmarkOptions |= CMARK_OPT_FOOTNOTES;

    NSArray<NSString *> *extNames = [delegate rendererCmarkExtensions:self];
    MPCmarkRenderFlags renderFlags = [delegate rendererCmarkRenderFlags:self];
    MPLanguageCallback langCallback = MPMakeLanguageCallback(self);
    NSMutableArray<NSString *> *langs = [NSMutableArray array];   // efímero, no muta self

    return MPHTMLFromMarkdown(markdown, extNames, cmarkOptions, renderFlags,
                              NO, [delegate rendererHasMathJax:self], nil,
                              langCallback, langs);
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
    BOOL hasMathJax = [delegate rendererHasMathJax:self];

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
    // Emite data-sourcepos="L:C-L:C" en cada elemento: habilita el mapeo por bloque
    // markdown↔HTML (selección conectada editor↔visor y scroll-sync más preciso).
    cmarkOptions |= CMARK_OPT_SOURCEPOS;

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
        hasTOC, hasMathJax, [frontMatter HTMLTable],
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

#pragma mark - Heading anchors

+ (NSString *)anchorSlugForHeadingText:(NSString *)text
{
    // Slug: fold accents to ASCII, lowercase, keep letters/digits/'-'/'_', turn
    // spaces into hyphens, drop everything else. e.g.
    //   "1. Product Overview"               -> "1-product-overview"
    //   "6. Authentication & Authorization" -> "6-authentication--authorization"
    //   "Instalación"                       -> "instalacion"
    //   "Año Nuevo"                         -> "ano-nuevo"
    // Note: accent folding diverges from GitHub/hoedown (which keep accents) by
    // deliberate choice on the cmark-gfm line — hand-written anchors are easier
    // to type without diacritics.
    NSLocale *posix = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    NSString *folded = [text stringByFoldingWithOptions:NSDiacriticInsensitiveSearch
                                                 locale:posix];
    NSString *lower = [folded lowercaseString];
    NSCharacterSet *alnum = [NSCharacterSet alphanumericCharacterSet];
    NSMutableString *slug = [NSMutableString stringWithCapacity:lower.length];
    [lower enumerateSubstringsInRange:NSMakeRange(0, lower.length)
                              options:NSStringEnumerationByComposedCharacterSequences
                           usingBlock:^(NSString *ch, NSRange r, NSRange er, BOOL *stop) {
        unichar first = [ch characterAtIndex:0];
        if ([ch rangeOfCharacterFromSet:alnum].location != NSNotFound
                || first == '-' || first == '_')
            [slug appendString:ch];
        else if (first == ' ')
            [slug appendString:@"-"];
        // anything else (punctuation) is dropped
    }];
    return [slug copy];
}

// Strips inline tags and decodes the handful of entities hoedown emits, so a
// heading's text matches what the user sees (and what GitHub would slug).
+ (NSString *)plainTextFromHeadingHTML:(NSString *)html
{
    static NSRegularExpression *tagRegex = nil;
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        tagRegex = [[NSRegularExpression alloc] initWithPattern:@"<[^>]+>"
                                                        options:0 error:NULL];
    });
    NSString *text = [tagRegex stringByReplacingMatchesInString:html options:0
                            range:NSMakeRange(0, html.length) withTemplate:@""];
    text = [text stringByReplacingOccurrencesOfString:@"&lt;" withString:@"<"];
    text = [text stringByReplacingOccurrencesOfString:@"&gt;" withString:@">"];
    text = [text stringByReplacingOccurrencesOfString:@"&quot;" withString:@"\""];
    text = [text stringByReplacingOccurrencesOfString:@"&#39;" withString:@"'"];
    text = [text stringByReplacingOccurrencesOfString:@"&apos;" withString:@"'"];
    // &amp; last so "&amp;lt;" doesn't become "<".
    text = [text stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"];
    return text;
}

+ (NSString *)HTMLByAddingHeadingAnchors:(NSString *)html
{
    if (!html.length)
        return html;

    static NSRegularExpression *headingRegex = nil;
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        // <hN ...attrs...>inner</hN>, attrs and inner captured.
        NSRegularExpressionOptions ops = NSRegularExpressionCaseInsensitive
            | NSRegularExpressionDotMatchesLineSeparators;
        headingRegex = [[NSRegularExpression alloc]
            initWithPattern:@"<h([1-6])([^>]*)>(.*?)</h\\1>" options:ops error:NULL];
    });

    NSArray<NSTextCheckingResult *> *matches =
        [headingRegex matchesInString:html options:0
                                range:NSMakeRange(0, html.length)];
    if (!matches.count)
        return html;

    // First pass (document order): compute slugs, de-duplicating repeats.
    // hoedown already gives headings an id="toc_N" (used by the [TOC] feature),
    // so rather than touch that we insert an empty anchor at the start of the
    // heading's content to carry the slug — additive and non-breaking.
    NSCountedSet *seen = [NSCountedSet set];
    NSMutableArray<NSNumber *> *locations = [NSMutableArray array];
    NSMutableArray<NSString *> *anchors = [NSMutableArray array];
    for (NSTextCheckingResult *match in matches)
    {
        NSString *inner = [html substringWithRange:[match rangeAtIndex:3]];
        NSString *base =
            [self anchorSlugForHeadingText:[self plainTextFromHeadingHTML:inner]];
        if (!base.length)
            continue;

        NSUInteger n = [seen countForObject:base];
        [seen addObject:base];
        NSString *slug = n ? [NSString stringWithFormat:@"%@-%lu",
                              base, (unsigned long)n] : base;

        [locations addObject:@([match rangeAtIndex:3].location)];
        [anchors addObject:[NSString stringWithFormat:
            @"<a class=\"md-heading-anchor\" id=\"%@\"></a>", slug]];
    }

    // Second pass (reverse): insert from the end so earlier offsets stay valid.
    NSMutableString *out = [html mutableCopy];
    for (NSInteger i = locations.count - 1; i >= 0; i--)
        [out insertString:anchors[i]
                  atIndex:locations[i].unsignedIntegerValue];
    return [out copy];
}

// Injects id="toc_N" into each heading in document order so the auto [TOC] macro's
// "#toc_N" links resolve. cmark-gfm (unlike hoedown) renders headings as a bare
// "<hN>" with no id, so its [TOC] was dead; this mirrors hoedown's behaviour. The
// numbering is positional and matches MPCmarkGFMGenerateTOC, which counts every
// h1..h6 in the same document order (kMPRendererTOCLevel == 6, so none are skipped).
// Runs before HTMLByAddingHeadingAnchors: so the slug anchor is added inside, keeping
// id="toc_N" on the <hN> intact (same layout hoedown produces on the stable line).
+ (NSString *)HTMLByAddingTOCHeadingIDs:(NSString *)html
{
    if (!html.length)
        return html;

    static NSRegularExpression *headingOpenRegex = nil;
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        // cmark-gfm emits headings as "<hN>" with no attributes.
        headingOpenRegex = [[NSRegularExpression alloc]
            initWithPattern:@"<h([1-6])>" options:0 error:NULL];
    });

    NSArray<NSTextCheckingResult *> *matches =
        [headingOpenRegex matchesInString:html options:0
                                    range:NSMakeRange(0, html.length)];
    if (!matches.count)
        return html;

    // Replace in reverse so earlier offsets stay valid; the toc index is the
    // forward position of the match (matches come in document order).
    NSMutableString *out = [html mutableCopy];
    for (NSInteger i = matches.count - 1; i >= 0; i--)
    {
        NSTextCheckingResult *match = matches[i];
        NSString *level = [html substringWithRange:[match rangeAtIndex:1]];
        [out replaceCharactersInRange:[match range] withString:
            [NSString stringWithFormat:@"<h%@ id=\"toc_%ld\">", level, (long)i]];
    }
    return [out copy];
}

@end
