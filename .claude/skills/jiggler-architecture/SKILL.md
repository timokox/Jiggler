---
name: jiggler-architecture
description: Projektspezifisches Architektur-Wissen über den Jiggler-Code. Diesen Skill immer aktivieren, sobald `AppDelegate.m/.h`, `PrefsController.m/.h`, `JigglerOverlayWindow.m/.h`, `TimedQuitController.m/.h`, `SSPanels.m/.h`, `SSProgressPanel.m/.h`, `SSVersionChecker.m/.h`, `SSCPU.m/.h`, `CocoaExtra.m/.h` oder `Base.lproj/*.xib` angefasst werden. Auch greifen bei den Themen: Idle-Detection, Jiggle-Scheduling, Aktivitäts-Assertions (`IOPMAssertion*`, `UpdateSystemActivity`, `IOPMAssertionDeclareUserActivity`), Zen-Jiggle, Click-Jiggle, Standard-Jiggle, jiggleStyle 0/1/2, Music-Detection (`com.apple.Music.playerInfo`, `kPSP`, AppleScript player state), Master-Switch, Timed-Quit, NSStatusItem-Icon, App-Nap-Prevention (`beginActivityWithOptions:`), CPU-Usage-Detection (SSCPU), Bedingungen wie „Only with X" (CPU-Usage / Removable Disks / Music playing / Apps named X / not on battery / not when screen locked / not with front apps named X), `JigglerIdleTime()`, `CGEventSourceSecondsSinceLastEventType`, das 0.25-Sekunden-NSTimer, screensaver delay. Auch greifen bei „Jiggler bleibt nicht wach", „Teams stay awake bug", „Zen-Mode jiggle funktioniert nicht", „Music-Bedingung greift nicht". Greift präventiv, weil viele Codeteile koordiniert geändert werden müssen (Aktivitäts-Signale parallel, Defaults-Keys backwards-kompatibel, jiggleStyle-Branches symmetrisch).
---

# jiggler-architecture — Architektur und Mechanik von Jiggler

## Was Jiggler tut, in einem Satz

Verhindern, dass der Mac in Sleep/Screensaver fällt, indem er entweder die Maus bewegt (Standard-Jiggle), die System-Idle-Zeit durch Aktivitäts-Signale resettet ohne sichtbare Maus-Bewegung (Zen-Jiggle), oder einen Maus-Klick ohne Bewegung postet (Click-Jiggle).

## Dateilandkarte

| Datei                          | Was drin ist                                                                                                                                              |
|--------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------|
| **`AppDelegate.{h,m}`**        | Herzstück. NSTimer-Loop, Aktivitäts-Assertions, Jiggle-Dispatch, NSStatusItem, Music-Detection, App-Nap-Prevention, Master-Switch, Accessibility-Check.   |
| **`PrefsController.{h,m}`**    | Singleton (`dispatch_once`), liest/schreibt NSUserDefaults, hält Preferences-Window (`Preferences.xib`), implementiert „Launch on Login" via LSSharedFileList. |
| **`JigglerOverlayWindow.{h,m}`** | Floating-Window mit Jiggler-Icon, das während des Jiggle-Vorgangs einblendet (wenn aktiviert). NSPanel mit Fade-In/Out.                                  |
| **`TimedQuitController.{h,m}`** | „Quit in X hours" Feature, NSTimer-basiert. Eigener Singleton-Pattern (klassisch, nicht dispatch_once — bewusst).                                         |
| **`SSPanels.{h,m}`**           | Custom-About-Panel (das chunky Window mit Apple-Icon, Stickman, Links). Reines Code-Layout, kein Nib.                                                     |
| **`SSProgressPanel.{h,m}`**    | Generischer Progress-Panel, hier nur vom Versions-Check genutzt. Eigenes Modal-Loop-Handling, sheet-fähig.                                                |
| **`SSVersionChecker.{h,m}`**   | Holt `sticksoftware.com/versions`, vergleicht mit Bundle-Version, zeigt Update-Hinweis. Macht eigene Alpha/Beta-Vergleichslogik.                          |
| **`SSCPU.{h,m}`**              | Mach-Host-Statistics-Wrapper für CPU-Usage in Prozent (für die „Only with CPU usage" Bedingung).                                                          |
| **`CocoaExtra.{h,m}`**         | Alle Utility-Categorys: `NSScreen+primaryScreen`, `NSPanel performKeyEquivalent:` (Cmd-W), Alert-Wrapper, `RunningOnBatteryOnly()`, `ScreenIsLocked()`, NSImage-Tinting. |
| **`main.m`**                   | Standard `@autoreleasepool { return NSApplicationMain(…); }`.                                                                                              |
| **`Jiggler_Prefix.h`**         | Stellt `NSLog` auf no-op in Release-Builds. **Wichtig** — Debug-Logs sind in Produktion gratis.                                                            |
| **`Info.plist`**               | `LSUIElement = YES` (kein Dock-Icon), Bundle-ID, Version (`MARKETING_VERSION` in pbxproj: aktuell 1.10).                                                   |
| **`Jiggler.entitlements`**     | Aktuell minimal — kein Sandboxing.                                                                                                                         |

## Der Main-Loop

In `-applicationDidFinishLaunching:`:

```objc
jiggleTimer = [NSTimer timerWithTimeInterval:0.25 target:self selector:@selector(periodicJiggleStatusCheck:) userInfo:nil repeats:YES];
[jiggleTimer setTolerance:0.10];   // Energy-Save-Toleranz
```

Wird in `NSRunLoopCommonModes`, `NSModalPanelRunLoopMode`, `NSEventTrackingRunLoopMode` eingehängt — damit er auch läuft, wenn ein Menü oder Modal offen ist. **0.25 s ist absichtlich** — schnell genug, dass das Overlay-Fade smooth ist; langsam genug, dass die CPU schläft.

Jede Iteration ruft `-periodicJiggleStatusCheck:` auf, die folgenden Pseudocode hat:

1. Wenn Master-Switch aus → return.
2. Wenn `notWhenScreenLocked` und Screen gerade locked → return (vgl. `ScreenIsLocked()`).
3. Wenn `notOnBattery` und nur Akku → return (vgl. `RunningOnBatteryOnly()`).
4. Wenn `notWithFrontAppsNamedX` und Front-App matched → return.
5. Idle-Zeit holen via `JigglerIdleTime()` → `CGEventSourceSecondsSinceLastEventType(kCGEventSourceStateCombinedSessionState, kCGAnyInputEventType)`.
6. Wenn Idle < `jiggleSeconds` → return (User ist gerade aktiv).
7. `-jiggleConditionsMet` prüfen (CPU-Threshold, removable disks, Music, App-Name-Matches). Wenn keine Bedingungen gesetzt → automatisch met.
8. Wenn met → `-jiggleMouse:` aufrufen (je nach `jiggleStyle`), dann `-declareUserActivity`, dann `timeOfLastJiggle = jetzt`.
9. Wenn nicht met → `timeOfLastJiggle` setzen auf `jetzt - jiggleSeconds + 5`, damit nicht jeder Tick voll evaluiert.

## Die drei Jiggle-Stile

Gespeichert in NSUserDefaults `JiggleStyle` (Int), Default `-1` (= „nicht gesetzt") fällt auf alten Bool-Key `ZenJiggle` zurück.

| `jiggleStyle` | Name                | Was passiert                                                                                                                                       |
|---------------|---------------------|----------------------------------------------------------------------------------------------------------------------------------------------------|
| **0**         | Standard-Jiggle     | 35 verzögerte Maus-Moves (`performSelector:withObject:afterDelay:` von 0.0 bis 0.34 s in 0.01-Schritten). Cursor wird sichtbar gewackelt.          |
| **1**         | Zen-Jiggle          | Maus wird **nicht** bewegt. Statt dessen Aktivitäts-Assertions (siehe unten) + auf 10.15+ ein zusätzlicher No-Move-`CGEventMouseMoved` an aktueller Position. |
| **2**         | Click-Jiggle        | `kCGEventLeftMouseDown` + 10 ms Sleep + `kCGEventLeftMouseUp` an aktueller Cursor-Position. Maus bewegt sich nicht, aber Apps sehen einen Klick.   |

Nach dem stil-spezifischen Block läuft für **alle Stile** geteilte Bookkeeping-Logik:
- `[self declareUserActivity]` → die vier Aktivitäts-Signale (siehe nächster Abschnitt)
- `timeOfLastJiggle = jetzt`
- `[self setJigglingActive:YES]` → Status-Item-Icon grün + Overlay-Window einblenden

## Aktivitäts-Assertions — kritisch, parallel emittieren

Jiggler emittiert **drei verschiedene Aktivitäts-Signale parallel** in `-declareUserActivity` (`AppDelegate.m`):

```objc
// (1) UpdateSystemActivity — Classic Mac API, deprecated seit 10.8, weak-linked
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
if (UpdateSystemActivity != NULL)
    UpdateSystemActivity(UsrActivity);
#pragma clang diagnostic pop

// (2) IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep)
//     — Erzeugt eine kurzlebige Assertion. Hat in Zen-Mode auf 10.15+ den Zen-Jiggle-Fix bewirkt.
IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep,
                            kIOPMAssertionLevelOn,
                            CFSTR("Jiggler Zen Jiggle Activity"),
                            &_userActivityAssertion);

// (3) IOPMAssertionDeclareUserActivity(kIOPMUserActiveLocal)
//     — Self-managing API, gleiche assertionID wiederverwendet.
static IOPMAssertionID userActivityDeclaration = kIOPMNullAssertionID;
IOPMAssertionDeclareUserActivity(CFSTR("Jiggler"), kIOPMUserActiveLocal, &userActivityDeclaration);
```

Plus im **Zen-Jiggle-Branch nur** (`jiggleStyle == 1`), unter `if (@available(macOS 15.0, *))`:

```objc
// (4) No-move CGEventMouseMoved an aktueller Cursor-Position
CGEventRef eventMoved = CGEventCreateMouseEvent(sourceRef, kCGEventMouseMoved, cgMouseLocation, kCGMouseButtonLeft);
CGEventPost(kCGHIDEventTap, eventMoved);
```

### Warum vier Signale?

Jedes Signal adressiert **eine andere Schicht** des macOS-Idle-Tracking:

- `UpdateSystemActivity` — alt, manche Tools fragen es noch ab.
- `kIOPMAssertionTypePreventUserIdleDisplaySleep` — der „moderne" Display-Sleep-Blocker.
- `IOPMAssertionDeclareUserActivity` mit `kIOPMUserActiveLocal` — manche Apple-Subsysteme (TCC, App-Nap, Power-Management) reagieren nur darauf.
- `CGEventMouseMoved` — was Apps wie Microsoft Teams selbst hooken, um „User ist da" zu prüfen.

**Issue #44** dokumentiert das explizit. Wenn jemand „aufräumt" und Signale entfernt, gehen Bugs wieder auf wie #43 (Teams). **Nichts hier entfernen ohne Issue + Begründung.**

## Music-Detection (vorher iTunes)

Zwei orthogonale Mechanismen, beide notwendig:

1. **Distributed Notification** `com.apple.Music.playerInfo` — Music.app broadcastet bei Play/Pause/Stop. `-musicChanged:` setzt `musicIsPlaying`.
2. **Polling per AppleScript** in `-musicIsPlayingNow`:
   ```objc
   NSAppleScript *musicScript = [[NSAppleScript alloc] initWithSource:@"tell application \"Music\"\nget player state\nend tell"];
   returnDesc = [musicScript executeAndReturnError:&errorDict];
   return [[returnDesc stringValue] isEqualToString:@"kPSP"];   // Four-Char-Code für "playing"
   ```

`kPSP` ist absichtlich roh als String hardcoded — Music.app gibt das genauso wie iTunes damals zurück. Wenn das jemals bricht, dann kommt von Apple was wie `kAPlaying` oder ein anderes FourCC; aktuell stabil.

`-musicIsRunningNow` prüft Bundle-ID `com.apple.Music` / Localized Name `"Music"` über `[NSWorkspace runningApplications]`.

**Defaults-Key:** `OnlyWithITunesPlayingDefaultsKey = @"OnlyWithITunesPlaying"` — der C-Identifier wurde auf Music umbenannt, das Literal-String muss aber `@"OnlyWithITunesPlaying"` bleiben (backwards-compat für bestehende Prefs).

## App-Nap-Prevention

In `-applicationDidFinishLaunching:`:

```objc
activityToken = [[NSProcessInfo processInfo] beginActivityWithOptions:NSActivityUserInitiatedAllowingIdleSystemSleep
                                                                reason:@"No napping on the job!"];
```

`activityToken` ist ein strong ivar (ARC). In `-applicationWillTerminate:`:

```objc
[[NSProcessInfo processInfo] endActivity:activityToken];
activityToken = nil;
```

Zusätzlich `NSAppSleepDisabled = YES` in `registerDefaults` — Gürtel und Hosenträger.

## Accessibility-Permission

Auf 10.15–14: `AXIsProcessTrusted()`-Check und Alert, wenn nicht granted. Auf 15+ via `AXIsProcessTrustedWithOptions` mit `kAXTrustedCheckOptionPrompt = false` (no-prompt-Variante, weil 15 das Verhalten geändert hat). Wenn nicht trusted → Quit. Siehe Code rund um Zeile 134 in `AppDelegate.m`.

## NSStatusItem

```objc
NSStatusItem *statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength];
[statusItem setMenu:[self statusItemMenu]];
```

Drei Icon-Varianten via `imageTintedWithColor:` aus `NSImage (JigglerTinting)`-Kategorie:
- `scaledJigglerImage` (neutral) — wenn Master aus oder idle
- `scaledJigglerImageGreen` (40 % Grün-Tint) — wenn `jigglingActive`
- `scaledJigglerImageRed` (40 % Rot-Tint) — wenn `timedQuitTimer` läuft

`-fixStatusItemIcon` synchronisiert das, jedes Mal wenn sich der State ändert.

## Preferences-Bedingungen (Cheat-Sheet)

Aktiv wenn jeweilige Checkbox an + Bedingung erfüllt:

| Defaults-Key                                | Bedeutung                                                                                          |
|---------------------------------------------|----------------------------------------------------------------------------------------------------|
| `OnlyWithCPUUsage` + `CPUUsageThreshold`    | Nur jiggeln wenn CPU-Busy-Index ≥ Threshold (vgl. `SSCPU`).                                        |
| `OnlyWithRemovableWritableDisks`            | Nur jiggeln wenn mounted removable writable Disk vorhanden (Backup-Use-Case).                       |
| `OnlyWithITunesPlaying` (= Music)           | Nur jiggeln wenn Music gerade „playing".                                                            |
| `OnlyWithApplicationsNamedX` + `…Component`| Nur wenn eine laufende App im Namen `…Component` enthält.                                          |
| `NotWhenScreenLocked`                       | Nicht jiggeln wenn Lock-Screen aktiv.                                                              |
| `NotOnBattery`                              | Nicht jiggeln wenn nur Akku.                                                                       |
| `NotWithFrontAppsNamedX` + `…Component`    | Nicht jiggeln wenn Front-App matched.                                                              |

`Only*`-Bedingungen sind **OR-verknüpft** (eine reicht). `Not*`-Bedingungen sind **AND-verknüpft** (jede einzelne darf nicht zutreffen).

## Timed-Quit

`TimedQuitController` hält einen NSTimer der minütlich `minutesRemainingToTimedQuit` dekrementiert. Bei 0 → `[NSApp terminate:nil]`. Menu-Item-Title wird via `-fixTimedQuitMenuItem` aktualisiert (zeigt `Timed Quit (Xh Ym)`).

## XIBs (Base.lproj/)

- `MainMenu.xib` — Status-Item-Menu (kein klassisches Menubar-Menu, weil `LSUIElement`).
- `Preferences.xib` — Big-ass Preferences-Window. Owner: `PrefsController`. Outlets stehen oben in der File.
- `TimedQuit.xib` — kleines Modal. Owner: `TimedQuitController`.
- `Read Me.html` — wird beim „Read Me" Menu-Item geöffnet via Workspace.

**XIB-Bearbeitung:** mit Vorsicht. Outlet-Properties-Namen müssen 1:1 zu `IBOutlet`-Declarations im Header passen. Action-Selektoren müssen 1:1 zu `- (IBAction)…` matchen. Bei Renames in Code immer XIB nachziehen, sonst silent NSException zur Laufzeit.

## Häufige Fallen beim Editieren von AppDelegate.m

- **`-applicationDidFinishLaunching:`** ist groß und hat viele Side-Effects. Nicht „mal eben aufräumen" — die Reihenfolge ist teilweise bedeutsam (Status-Item muss vor Accessibility-Check existieren, weil bei Quit der Cleanup-Code es braucht).
- **NSTimer-Modes** (siehe oben): wenn man einen neuen Timer hinzufügt, muss er in alle drei Modes, sonst friert er ein bei offenem Menu.
- **NSDistributedNotificationCenter**: muss in `-applicationWillTerminate:` removed werden, sonst Crash beim Quit (object lifetime mismatch).
- **`@available(macOS XX, *)`**: Deployment Target ist 10.15. Heißt: kein `@available(macOS 10.15, *)` nötig, aber alles ≥ 11 muss gegated sein. Aktuell relevant: 15+ wegen `AXIsProcessTrustedWithOptions`-Verhaltensänderung und 15+ wegen Zen-Mode-CGEventMouseMoved.
