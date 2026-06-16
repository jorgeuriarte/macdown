//
//  MPGlobals.h
//  MacDown
//
//  Created by Tzu-ping Chung on 02/12.
//  Copyright (c) 2014 Tzu-ping Chung . All rights reserved.
//

#import "version.h"

// These should match the main bundle's values (MacDown Remix identity).
static NSString * const kMPApplicationName = @"MacDown Remix";

#ifdef DEBUG
static NSString * const kMPApplicationBundleIdentifier = @"net.omelas.macdown-remix-debug";
#else
static NSString * const kMPApplicationBundleIdentifier = @"net.omelas.macdown-remix";
#endif

// Suite de NSUserDefaults compartido entre la app y el helper de CLI (rendezvous
// de ficheros a abrir). Se mantiene el dominio histórico a propósito: app y helper
// usan esta misma constante, así que siempre coinciden, y no se migran las prefs
// existentes del usuario. La identidad propia de prefs es un paso aparte.
static NSString * const kMPApplicationSuiteName = @"com.uranusjr.macdown";

static NSString * const MPCommandInstallationPath = @"/usr/local/bin/macdown";
static NSString * const kMPCommandName = @"macdown";

static NSString * const kMPHelpKey = @"help";
static NSString * const kMPVersionKey = @"version";

static NSString * const kMPFilesToOpenKey = @"filesToOpenOnNextLaunch";
static NSString * const kMPPipedContentFileToOpen = @"pipedContentFileToOpenOnNextLaunch";

// Editor/preview appearance modes selectable from View ▸ Appearance.
// Light is the historical default, so it maps to zero (no defaults migration).
typedef NS_ENUM(NSInteger, MPViewMode) {
    MPViewModeLight = 0,
    MPViewModeDark  = 1,
    MPViewModeSepia = 2,
};
