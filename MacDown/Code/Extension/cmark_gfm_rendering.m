//
//  cmark_gfm_rendering.m
//  MacDown
//
//  cmark-gfm rendering utilities for MacDown.
//

#import "cmark_gfm_rendering.h"
#import <cmark-gfm/cmark-gfm.h>
#import <cmark-gfm/cmark-gfm-core-extensions.h>
#import <cmark-gfm/cmark-gfm-extension_api.h>

#pragma mark - Helpers

// Parse result holding the AST, extension list, and parser.
// The parser must stay alive until after cmark_render_html()
// because the extension list is owned by the parser.
typedef struct {
    cmark_node *document;
    cmark_llist *extensions;
    cmark_parser *parser;
} MPCmarkParseResult;

static MPCmarkParseResult MPParseCmarkDocument(
    NSString *markdown, NSArray<NSString *> *extensions,
    int options)
{
    cmark_gfm_core_extensions_ensure_registered();

    cmark_parser *parser = cmark_parser_new(options);

    for (NSString *extName in extensions)
    {
        cmark_syntax_extension *ext =
            cmark_find_syntax_extension(extName.UTF8String);
        if (ext)
            cmark_parser_attach_syntax_extension(parser, ext);
    }

    NSData *data =
        [markdown dataUsingEncoding:NSUTF8StringEncoding];
    cmark_parser_feed(parser, data.bytes, data.length);
    cmark_node *document = cmark_parser_finish(parser);

    cmark_llist *extList =
        cmark_parser_get_syntax_extensions(parser);

    MPCmarkParseResult result;
    result.document = document;
    result.extensions = extList;
    result.parser = parser;

    // Do NOT free the parser here — the extension list is
    // owned by it. Callers must call cmark_parser_free()
    // after they are done with result.extensions.
    return result;
}

static void MPFreeCmarkParseResult(MPCmarkParseResult *result)
{
    if (result->document)
        cmark_node_free(result->document);
    if (result->parser)
        cmark_parser_free(result->parser);
    result->document = NULL;
    result->extensions = NULL;
    result->parser = NULL;
}

#pragma mark - Code block post-processing

// Post-process HTML to add line-numbers class and data-information
// attributes to code blocks.
//
// cmark-gfm renders:
//   <pre><code class="language-X">...</code></pre>
//
// We need:
//   <div><pre class="line-numbers"
//     data-information="info"><code class="language-X">
//     ...</code></pre></div>
//
// When CMARK_OPT_FULL_INFO_STRING is set, the full info string
// (after the language) is preserved. We split on ':' for the
// data-information attribute.
static NSString *MPPostProcessCodeBlocks(
    NSString *html, MPCmarkRenderFlags renderFlags)
{
    if (renderFlags == MPCmarkRenderFlagNone)
        return html;

    BOOL addLineNumbers =
        (renderFlags & MPCmarkRenderFlagLineNumbers) != 0;
    BOOL addInformation =
        (renderFlags & MPCmarkRenderFlagBlockInformation) != 0;

    // Match <pre><code class="language-..."> patterns.
    // We wrap them in <div> and add attributes.
    static NSRegularExpression *preCodeRegex = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *pattern =
            @"<pre><code class=\"language-([^\"]*?)\">";
        preCodeRegex = [NSRegularExpression
            regularExpressionWithPattern:pattern
            options:0
            error:NULL];
    });

    NSMutableString *result = [html mutableCopy];

    // Process matches in reverse to preserve offsets.
    NSArray *matches = [preCodeRegex
        matchesInString:html options:0
        range:NSMakeRange(0, html.length)];

    for (NSTextCheckingResult *match in
         matches.reverseObjectEnumerator)
    {
        NSRange fullRange = [match range];
        NSRange langRange = [match rangeAtIndex:1];
        NSString *langInfo =
            [html substringWithRange:langRange];

        // Split on ':' for language and info.
        NSString *lang = langInfo;
        NSString *info = nil;
        if (addInformation)
        {
            NSRange colonRange =
                [langInfo rangeOfString:@":"];
            if (colonRange.location != NSNotFound)
            {
                lang = [langInfo
                    substringToIndex:colonRange.location];
                info = [langInfo
                    substringFromIndex:
                        colonRange.location + 1];
            }
        }

        NSMutableString *replacement =
            [NSMutableString stringWithString:@"<div><pre"];
        if (addLineNumbers)
            [replacement appendString:@" class=\"line-numbers\""];
        if (info.length)
        {
            [replacement appendFormat:
                @" data-information=\"%@\"", info];
        }
        [replacement appendFormat:
            @"><code class=\"language-%@\">", lang];

        [result replaceCharactersInRange:fullRange
                              withString:replacement];
    }

    // Close the wrapping divs: </code></pre> → </code></pre></div>
    if (matches.count)
    {
        [result replaceOccurrencesOfString:@"</code></pre>"
                                withString:@"</code></pre></div>"
                                   options:0
                                     range:NSMakeRange(0, result.length)];
    }

    // Handle bare code blocks (no language).
    // cmark renders: <pre><code>...</code></pre>
    if (addLineNumbers)
    {
        static NSRegularExpression *barePreRegex = nil;
        static dispatch_once_t bareToken;
        dispatch_once(&bareToken, ^{
            barePreRegex = [NSRegularExpression
                regularExpressionWithPattern:
                    @"<pre><code>(?!.*class=\"language-)"
                options:0
                error:NULL];
        });

        NSArray *bareMatches = [barePreRegex
            matchesInString:result options:0
            range:NSMakeRange(0, result.length)];

        for (NSTextCheckingResult *match in
             bareMatches.reverseObjectEnumerator)
        {
            NSRange r = [match range];
            NSString *rep =
                @"<div><pre class=\"line-numbers\">"
                @"<code class=\"language-none\">";
            [result replaceCharactersInRange:r
                                  withString:rep];
        }
    }

    return [result copy];
}

#pragma mark - Language extraction

// Walk the AST to extract fence info languages and call the
// language callback for alias resolution.
static void MPExtractLanguages(
    cmark_node *document,
    MPLanguageCallback languageCallback,
    NSMutableArray<NSString *> *outLanguages)
{
    if (!outLanguages)
        return;

    cmark_iter *iter = cmark_iter_new(document);
    cmark_event_type evType;

    while ((evType = cmark_iter_next(iter)) != CMARK_EVENT_DONE)
    {
        if (evType != CMARK_EVENT_ENTER)
            continue;

        cmark_node *node = cmark_iter_get_node(iter);
        if (cmark_node_get_type(node) != CMARK_NODE_CODE_BLOCK)
            continue;

        const char *fenceInfo =
            cmark_node_get_fence_info(node);
        if (!fenceInfo || fenceInfo[0] == '\0')
            continue;

        NSString *info = [NSString
            stringWithUTF8String:fenceInfo];

        // Strip anything after ':' (info string separator).
        NSRange colonRange = [info rangeOfString:@":"];
        if (colonRange.location != NSNotFound)
            info = [info substringToIndex:colonRange.location];

        // Strip anything after space (extra info).
        NSRange spaceRange = [info rangeOfString:@" "];
        if (spaceRange.location != NSNotFound)
            info = [info substringToIndex:spaceRange.location];

        if (!info.length)
            continue;

        NSString *resolved = info;
        if (languageCallback)
        {
            NSString *mapped = languageCallback(info);
            if (mapped)
                resolved = mapped;
        }

        if (![outLanguages containsObject:resolved])
            [outLanguages addObject:resolved];
    }

    cmark_iter_free(iter);
}

#pragma mark - Public API

NSString *MPCmarkGFMToHTML(
    NSString *markdown,
    NSArray<NSString *> *extensions,
    int options,
    MPCmarkRenderFlags renderFlags,
    MPLanguageCallback languageCallback,
    NSMutableArray<NSString *> *outLanguages)
{
    if (!markdown.length)
        return @"";

    // Always enable UNSAFE to allow raw HTML pass-through
    // (matches hoedown behavior).
    options |= CMARK_OPT_UNSAFE;

    // Enable full info string so we can extract the
    // data-information part.
    if (renderFlags & MPCmarkRenderFlagBlockInformation)
        options |= CMARK_OPT_FULL_INFO_STRING;

    MPCmarkParseResult parsed =
        MPParseCmarkDocument(markdown, extensions, options);

    // Extract languages before rendering.
    MPExtractLanguages(
        parsed.document, languageCallback, outLanguages);

    char *htmlCStr = cmark_render_html(
        parsed.document, options, parsed.extensions);

    NSString *html =
        [NSString stringWithUTF8String:htmlCStr];
    free(htmlCStr);

    // Free parser and document together — the extension list
    // is owned by the parser, so it must outlive rendering.
    MPFreeCmarkParseResult(&parsed);

    // Post-process code blocks for line numbers and info.
    html = MPPostProcessCodeBlocks(html, renderFlags);

    return html;
}

NSString *MPCmarkGFMGenerateTOC(
    NSString *markdown,
    NSArray<NSString *> *extensions,
    int options,
    int maxLevel)
{
    if (!markdown.length)
        return @"";

    options |= CMARK_OPT_UNSAFE;

    MPCmarkParseResult parsed =
        MPParseCmarkDocument(markdown, extensions, options);
    cmark_iter *iter = cmark_iter_new(parsed.document);
    cmark_event_type evType;

    NSMutableString *toc = [NSMutableString string];
    int currentLevel = 0;
    int headerCount = 0;
    int levelOffset = 0;

    while ((evType = cmark_iter_next(iter)) != CMARK_EVENT_DONE)
    {
        if (evType != CMARK_EVENT_ENTER)
            continue;

        cmark_node *node = cmark_iter_get_node(iter);
        if (cmark_node_get_type(node) != CMARK_NODE_HEADING)
            continue;

        int level = cmark_node_get_heading_level(node);
        if (level > maxLevel)
            continue;

        // Set level offset from first heading.
        if (currentLevel == 0)
            levelOffset = level - 1;

        level -= levelOffset;

        // Get heading text content.
        // We need to render just the inline children to HTML.
        NSMutableString *content = [NSMutableString string];
        cmark_node *child = cmark_node_first_child(node);
        while (child)
        {
            // Render each inline child.
            const char *literal =
                cmark_node_get_literal(child);
            if (literal)
            {
                // cmark returns UTF-8; %s would decode it as the default C
                // string encoding (Mac Roman) and mangle accents. Decode UTF-8.
                NSString *s = [NSString stringWithUTF8String:literal];
                if (s)
                    [content appendString:s];
            }
            else
            {
                // For non-literal nodes (emphasis, links, etc.),
                // render them to HTML.
                char *rendered = cmark_render_html(
                    child, CMARK_OPT_DEFAULT, NULL);
                if (rendered)
                {
                    NSString *s = [NSString stringWithUTF8String:rendered];
                    if (s)
                        [content appendString:s];
                    free(rendered);
                }
            }
            child = cmark_node_next(child);
        }

        // Build TOC structure.
        if (level > currentLevel)
        {
            while (level > currentLevel)
            {
                if (currentLevel == 0)
                    [toc appendString:
                        @"<ul class=\"toc\">\n<li>\n"];
                else
                    [toc appendString:@"<ul>\n<li>\n"];
                currentLevel++;
            }
        }
        else if (level < currentLevel)
        {
            [toc appendString:@"</li>\n"];
            while (level < currentLevel)
            {
                [toc appendString:@"</ul>\n</li>\n"];
                currentLevel--;
            }
            [toc appendString:@"<li>\n"];
        }
        else
        {
            [toc appendString:@"</li>\n<li>\n"];
        }

        [toc appendFormat:
            @"<a href=\"#toc_%d\">%@</a>\n",
            headerCount++, content];
    }

    // Close remaining open tags.
    while (currentLevel > 0)
    {
        [toc appendString:@"</li>\n</ul>\n"];
        currentLevel--;
    }

    cmark_iter_free(iter);
    MPFreeCmarkParseResult(&parsed);

    return [toc copy];
}
