---
name: objc-macos-dev
description: Senior-Objective-C-/-macOS-/-AppKit-Entwickler-Perspektive für die Jiggler-Codebase. Diesen Skill immer aktivieren, wenn `.m`- oder `.h`-Dateien bearbeitet werden, oder sobald folgende Themen auftauchen — auch beiläufig: ARC (Automatic Reference Counting), `retain`/`release`/`autorelease`, `__bridge` / `CFBridgingRelease` / `__bridge_transfer` / `__bridge_retained`, Toll-Free Bridging, Retain-Cycles in Blocks (`__weak typeof(self) weakSelf`), strong/weak Delegate-Properties, `NSNotification`/`NSDistributedNotificationCenter`, IB-Outlets (`@property (strong) IBOutlet`), `dispatch_once`-Singletons, deprecated Apple-APIs (LSSharedFileList, UpdateSystemActivity, NSAlertDefaultReturn), IOKit, `IOPMAssertion*`, AppleScript-Bridge (`NSAppleScript`), `NSAppleEventDescriptor`, `CGEvent*`, AXIsProcessTrustedWithOptions, NSStatusItem, NSWorkspace-Notifications. Auch greifen bei „Memory-Leak", „EXC_BAD_ACCESS", „zombie object", „weak self in block", „Sandbox-Entitlement", „Deployment Target". Greift präventiv bei jedem Code-Review eines `.m`/`.h`-Files — weil Obj-C-Ownership-Fehler nicht durch Compile-Errors auffallen, sondern erst zur Laufzeit als Crash oder Leak.
---

# objc-macos-dev — Senior-Objective-C-Perspektive für Jiggler

Du schreibst, reviewst oder debuggst Objective-C-Code im Jiggler-Projekt. Halte dich an die folgenden Konventionen und Gotchas — sie sind nicht generisch, sondern aus echten Bugs in genau diesem Code destilliert.

## Projektkontext (auswendig wissen)

- **Deployment Target:** `MACOSX_DEPLOYMENT_TARGET = 10.15` — Catalina+. Heißt: Music.app statt iTunes, dispatch APIs durchgängig verfügbar, `NSWindowStyleMask*` statt `NSTitledWindowMask`, kein iOS-Bridging.
- **ARC ist an** (`CLANG_ENABLE_OBJC_ARC = YES` in beiden Configs). Manuelles `retain`/`release`/`autorelease` ist seit Kurzem komplett raus — wenn du es zurückbringst, ist das ein Compile-Error, kein Hinweis.
- **MRC → ARC ist gerade frisch passiert.** Heißt: Retain-Cycles, fehlende `__bridge`-Casts und Use-after-free sind die wahrscheinlichsten Regressionen.
- **Singletons** verwenden `dispatch_once` (siehe `+[PrefsController sharedPrefsController]`). Niemals den alten Singleton-Pattern mit `[self dealloc]` bei doppeltem `init` zurückbringen — unter ARC ist `[self dealloc]` ein Compile-Error.

## Backwards-Compat-Invariante (NICHT brechen)

Die NSUserDefaults-Key-**Strings** dürfen sich nie ändern, weil sonst die Prefs bestehender User verloren gehen. Konkretes Beispiel:

```objc
static NSString *OnlyWithMusicPlayingDefaultsKey = @"OnlyWithITunesPlaying";	// historical key name retained for backwards compatibility with stored prefs
```

Die C-Identifier dürfen umbenannt werden (z.B. `OnlyWithITunesPlayingDefaultsKey` → `OnlyWithMusicPlayingDefaultsKey`), aber das `@"..."`-Literal bleibt für immer. Falls du irgendwo einen Defaults-Key umbenennst, müsste eine Migrations-Funktion im `-init` mitkommen, die den alten Key liest und auf den neuen umschreibt — Aufwand meistens nicht wert.

## CF/NS-Bridging — die häufigste ARC-Falle

Core Foundation lebt außerhalb von ARC. Sobald CF-Typen mit Obj-C-Pointern getauscht werden, muss explizit gecastet werden, sonst sagt der Compiler dir das. Die Regeln sind:

| Vorher (MRC)                                | Nachher (ARC)                                              | Wann                                                                                                |
|---------------------------------------------|------------------------------------------------------------|-----------------------------------------------------------------------------------------------------|
| `(NSDictionary *)cfDict`                    | `(__bridge NSDictionary *)cfDict`                          | CF→NS-Cast ohne Eigentumsübergang. Caller behält weiter `CFRelease`-Pflicht.                        |
| `[(id)copiedCFThing autorelease]`           | `(NSType *)CFBridgingRelease(copiedCFThing)`               | CF-Funktion gab `Copy`/`Create` (also +1) zurück; jetzt soll ARC den Besitz übernehmen.             |
| `NSMakeCollectable(cfThing)`                | `CFBridgingRelease(cfThing)`                               | `NSMakeCollectable` ist GC-Ära, vollständig deprecated.                                             |
| `(CFURLRef)nsURL`                           | `(__bridge CFURLRef)nsURL`                                 | NS→CF-Cast für einen Funktions-Aufruf, kein Eigentumsübergang.                                      |
| `(CFURLRef)[nsURL retain]`                  | `(CFURLRef)CFBridgingRetain(nsURL)`                        | NS→CF mit Eigentumsübergang an einen CF-Konsumenten, der später `CFRelease` macht.                  |

**Live-Beispiele aus dem Code** — wenn du in der Nähe etwas änderst, behalte das Pattern:

```objc
// PrefsController.m — -launchOnLogin
CFArrayRef snapshotRef = LSSharedFileListCopySnapshot(loginItemsListRef, NULL);
NSArray *loginItems = (NSArray *)CFBridgingRelease(snapshotRef);           // Copy → ARC übernimmt

for (id item in loginItems) {
    LSSharedFileListItemRef itemRef = (__bridge LSSharedFileListItemRef)item;  // NS→CF, keine Übergabe
    CFURLRef itemURLRef = LSSharedFileListItemCopyResolvedURL(itemRef, 0, NULL);
    NSURL *itemURL = (NSURL *)CFBridgingRelease(itemURLRef);               // Copy → ARC übernimmt
}

// PrefsController.m — -setLaunchOnLogin:
LSSharedFileListInsertItemURL(loginItemsListRef, kLSSharedFileListItemLast, NULL, NULL,
                              (__bridge CFURLRef)bundleURL,                // NS→CF, kein Transfer
                              (__bridge CFDictionaryRef)properties, NULL);

// CocoaExtra.m — ScreenIsLocked()
CFDictionaryRef sessionDict = CGSessionCopyCurrentDictionary();
BOOL isLocked = ([((__bridge NSDictionary *)sessionDict)[@"CGSSessionScreenIsLocked"] intValue] == 1);
CFRelease(sessionDict);   // Wir haben CF behalten → CF müssen wir freigeben
```

`LSSharedFileList*` ist seit 10.10 deprecated, deshalb stehen die Aufrufe innerhalb von `#pragma clang diagnostic ignored "-Wdeprecated-declarations"`. Wenn du dort was modernisierst, müsstest du auf `SMAppService` (10.13+) bzw. `SMLoginItemSetEnabled` umstellen — das ist eine größere Änderung, kein Drive-by-Fix.

## Retain-Cycles in Blocks

Wenn ein Block `self` capturet und der Block in `self` gespeichert wird oder von etwas, das `self` ownt, hast du einen Zyklus. Standard-Lösung:

```objc
__weak __typeof(self) weakSelf = self;
self.someBlock = ^{
    __typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf) return;
    [strongSelf doStuff];
};
```

In Jiggler aktuell relevant: der `dataTaskWithURL:completionHandler:` in `SSVersionChecker.m` captured `self` — funktioniert hier ohne Zyklus, weil `NSURLSession` den Block nach Completion freigibt. Aber bei jedem neuen `self.handler = ^{ [self foo]; }`-Muster: erst überlegen.

## Strong vs. Weak

| Beziehung                                              | Annotation                              |
|--------------------------------------------------------|-----------------------------------------|
| Owner → ownedObject (z.B. `NSDate *timeOfLastJiggle`)  | `@property (strong)` / strong ivar (default für Obj-C-Ivars) |
| Delegate-Pointer (Parent zeigt zurück auf Owner)       | `@property (weak)`                      |
| IBOutlet auf Top-Level-Nib-Objekt (Window, Menu)       | `@property (strong)`                    |
| IBOutlet auf View innerhalb eines Window-Contents      | `@property (weak)` reicht (Superview hält strong) |

Jiggler nutzt durchgängig `@property (strong)` für IBOutlets — das ist konservativ aber sicher. Wenn du eine neue Klasse mit Delegate-Pattern einführst, mach den Delegate `weak`, sonst Crash beim Dealloc.

## Apple-deprecated APIs in der Codebase

| Stelle                                  | Status                                                                   |
|-----------------------------------------|--------------------------------------------------------------------------|
| `UpdateSystemActivity(UsrActivity)`     | Deprecated seit 10.8, weak-linked (`__attribute__((weak_import))`) und in `#pragma clang diagnostic ignored "-Wdeprecated-declarations"` gewickelt. Bleibt drin als zusätzliches Signal, siehe `jiggler-architecture`-Skill. |
| `LSSharedFileList*`                     | Deprecated seit 10.10. Komplett in `#pragma` eingewickelt. Ersatz: `SMAppService` (siehe Issue #37). |
| `NSMakeCollectable`                     | Ist raus — durch `CFBridgingRelease` ersetzt.                            |
| `kPSP` als Player-State-Vergleich      | Four-Char-Code; Music.app gibt das immer noch zurück. Bleibt.            |

## Activity-Assertions (kein Faux-pas — siehe `jiggler-architecture`)

Wenn du die `-declareUserActivity`-Methode anfasst: dort werden **drei** Signale parallel emittiert (`UpdateSystemActivity`, `IOPMAssertionCreateWithName`, `IOPMAssertionDeclareUserActivity`). Plus im Zen-Jiggle-Branch zusätzlich ein No-Move-`CGEventMouseMoved`-Post auf 10.15+. **Keines davon einfach entfernen**, auch wenn es redundant aussieht — jedes adressiert eine andere macOS-Idle-Tracking-Schicht. Issue #44 ist genau dazu da, damit niemand das nochmal versehentlich „aufräumt".

## Auto-Format-Bug-Vermeidung

Beim Bulk-Refactor mit `sed`/`perl`: hüte dich vor Patterns, die geschachtelte `[…]`-Brackets falsch parsen. Konkretes Beispiel aus der ARC-Migration:

```objc
// Original (MRC):
ssAboutPanel = [[NSWindow standardSSAboutPanelFor…] retain];
// Falsche Naive-sed-Ersetzung (` retain];` → `];`):
ssAboutPanel = [[NSWindow standardSSAboutPanelFor…]];  // ⚠️ doppelte Bracket → "expected identifier"
// Korrekt:
ssAboutPanel = [NSWindow standardSSAboutPanelFor…];
```

Wenn ein Bulk-Replace gemacht wird, immer hinterher `xcodebuild` laufen lassen — viele dieser Fehler fängt erst der Compiler.

## Code-Style des Projekts

- 4-Space-Tabs (genauer: Tab-Zeichen, in Xcode auf 4 Spaces dargestellt). Achte beim Editieren auf konsistente Whitespace-Charakters.
- Methoden-Bodies öffnen `{` auf neuer Zeile (BSD/Allman-Style), keine K&R-Klammern.
- `NSLog` ist erlaubt — in Release-Builds wird er via `Jiggler_Prefix.h` auf `do {} while(0)` gemappt. Heißt: ausführliche Debug-Logs schaden Produktion nicht. Aber per-Tick-Spam (alle 0.25 Sekunden mehrfach) macht selbst Debug-Builds unbenutzbar — dann lieber raus.
- `// MARK:` / `#pragma mark` werden benutzt um Methoden-Gruppen zu kennzeichnen — beim Hinzufügen neuer Sektionen den Stil halten.
