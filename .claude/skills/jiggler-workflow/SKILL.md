---
name: jiggler-workflow
description: Workflow-Regeln für den Jiggler-Fork (timokox/Jiggler). Diesen Skill immer aktivieren bei Git-/Build-/Test-/PR-bezogener Arbeit am Jiggler-Repo, auch ohne explizite Erwähnung. Konkrete Trigger: `git commit`, `git push`, `gh pr create`, „PR öffnen", „mergen", „Branch erstellen", „Branch protecten", „build", „xcodebuild", „kompilieren", „testen ob es läuft", „smoke-test", „crash-report", „DerivedData", „release bauen", „archive", „notarize", „App starten", „rebase auf master", „force-push", Konfliktauflösung. Auch greifen bei allem, was später als Commit/Branch enden könnte. Wichtigste Regeln, die hier kodiert sind: PRs only (master ist protected), keinerlei „Claude"/„AI"/Co-Authored-By Trailer in Commits oder PR-Bodies (User-Anweisung), immer `xcodebuild` vor „verifiziert" Aussagen, Smoke-Test via direkter Binary-Aufruf, gh-CLI ist konfiguriert. Greift präventiv, weil Fehlverhalten hier (z.B. direkter Push auf master, AI-Trailer im Commit) entweder hart blockiert oder unangenehm ist.
---

# jiggler-workflow — Wie man im Jiggler-Fork arbeitet

## Harte Regeln (nicht verhandelbar)

### 1. PRs only — master ist protected

`master` hat GitHub-Branch-Protection. Direkte Pushes werden vom Server abgelehnt. Force-Push und Branch-Delete sind hart blockiert. Workflow ist immer:

```bash
git checkout -b kurzer-aussagekraeftiger-name
# ... arbeiten, committen ...
git push -u origin kurzer-aussagekraeftiger-name
gh pr create -R timokox/Jiggler --head <branch> --base master \
  --title "Kurz, präzise" --body "..."
# Solo-Dev → direkt mergen
gh pr merge -R timokox/Jiggler <pr-num-oder-branch> --merge --delete-branch
```

Bei `--merge` macht GitHub einen Merge-Commit. Falls du linear bleiben willst, geht auch `--squash` oder `--rebase` (aber Branch-Protection erlaubt aktuell alle drei).

### 2. Keine „Claude"-/„AI"-Spuren in Commits oder PR-Bodies

Der Repo-Owner hat das explizit eingefordert. Konkret heißt das **niemals**:

- ❌ `Co-Authored-By: Claude <noreply@anthropic.com>` Trailer
- ❌ „🤖 Generated with [Claude Code]" Footer
- ❌ „This commit was made with AI assistance" / ähnliche Hinweise
- ❌ Erwähnung von „Claude", „Anthropic", „AI", „LLM" in Commit-Messages oder PR-Beschreibungen

Commits werden im Namen des Repo-Owners verfasst, ohne Authorship-Trailer. PR-Bodies enthalten technische Begründungen, keine Meta-Hinweise zur Erstellungsweise.

### 3. „Verifiziert" heißt: gebaut

Bevor du sagst „Change funktioniert" oder „ist fertig", **immer** durchlaufen lassen:

```bash
xcodebuild -project Jiggler.xcodeproj -scheme Jiggler -configuration Debug build 2>&1 | tail -3
```

Erwartet: `** BUILD SUCCEEDED **`. Wenn nicht:

```bash
xcodebuild -project Jiggler.xcodeproj -scheme Jiggler -configuration Debug build 2>&1 | grep -E "error:|warning:" | grep -v "no rule\|note:" | head -40
```

→ zeigt nur Errors und Warnings. Errors fixen, Warnings interpretieren.

Output ist **groß** (~100 KB), deshalb nie blind `xcodebuild` ohne Filter dumpen.

### 4. Smoke-Test nach Build (wenn Verhalten zur Laufzeit relevant ist)

```bash
APP="/Users/timokox/Library/Developer/Xcode/DerivedData/Jiggler-gguuyrflclwikfeggldtkvouggeg/Build/Products/Debug/Jiggler.app"
# Pfad kann variieren — generischer:
APP="$(find ~/Library/Developer/Xcode/DerivedData/Jiggler-*/Build/Products/Debug -name 'Jiggler.app' -maxdepth 2 -type d | head -1)"

"$APP/Contents/MacOS/Jiggler" > /tmp/jiggler.stdout 2> /tmp/jiggler.stderr &
PID=$!
sleep 20
if kill -0 $PID 2>/dev/null; then
  echo "STATUS: alive ✅"
  kill -TERM $PID; sleep 1; kill -KILL $PID 2>/dev/null
else
  echo "STATUS: crashed ❌"
fi

# Crash-Reports prüfen:
find ~/Library/Logs/DiagnosticReports/ -name '*Jiggler*' -mtime -1
# Unified Logs der letzten Minute:
/usr/bin/log show --predicate 'process == "Jiggler"' --last 1m --style compact | tail -50
```

Wichtige Hinweise:
- **`/usr/bin/log`** (absoluter Pfad), nicht `log` — die Shell hat oft eine Builtin/Alias-Kollision.
- App lebt nach Cmd-Q nicht weiter; `kill -TERM` reicht meistens.
- TCC-Permission-Dialog kann beim Erststart aufpoppen; in CI-Kontexten ggf. vorher granten.

### 5. PR-Body-Stil

Aussagekräftig, knapp, mit Begründung. Vorlagen-Struktur, die im Repo etabliert ist:

```markdown
Fixes #N. (oder: Closes #N. / Likely also fixes #M.)

Kurze Zusammenfassung in 1–2 Sätzen — warum die Änderung.

## Changes
- Bullet-Point pro logischer Änderung
- mit Datei-Referenz bei größeren PRs

## Hardening / Backwards compatibility / Notes
- alles, was Reviewer wissen müssen, ohne den Code zu lesen

## Verification
- Build status: `xcodebuild ... BUILD SUCCEEDED`
- Optional: was lokal getestet wurde
```

Markdown-Tabellen sind willkommen wenn sie helfen (vgl. PR #3).

## Standard-Operationen

### Issue checken

```bash
gh issue view <N> -R bhaller/Jiggler           # Upstream
gh issue list -R bhaller/Jiggler --state open --limit 30
```

Für Issues in unserem Fork: `-R timokox/Jiggler`.

### Feature-Branch von aktuellem master

```bash
git fetch origin master
git checkout master && git pull --ff-only
git checkout -b feature-xyz
```

`pull --ff-only` schützt davor, dass lokale Commits an `master` ungewollt mit Remote vermischt werden — sollte aber wegen Branch-Protection eh nicht vorkommen.

### Rebase auf master nach lange dauernder Arbeit

```bash
git fetch origin master
git rebase origin/master
# Konflikte lösen, dann:
git rebase --continue
git push --force-with-lease origin <branch>   # Force ist OK auf Feature-Branches
```

`--force-with-lease` statt plain `--force` — bricht ab wenn remote inzwischen mehr Commits hat.

### PR-Konflikt nach Merge eines vorherigen PR

Wenn du mehrere abhängige PRs offen hast und der erste gemerged wird, hat der zweite ggf. Konflikte. Lösung:

```bash
git checkout feature-2
git fetch origin master
git rebase origin/master
# Konflikte lösen, force-push
git push --force-with-lease
```

GitHub erkennt automatisch und stellt den PR auf „mergeable".

### Build verifizieren bevor PR

Immer machen, auch wenn die Änderung trivial aussieht:

```bash
xcodebuild -project Jiggler.xcodeproj -scheme Jiggler -configuration Debug build 2>&1 | grep -E "error:|warning:|SUCCEEDED|FAILED" | tail -5
```

Saubere Output sieht so aus: `** BUILD SUCCEEDED **`. Warnings sind OK, müssen aber bewusst sein.

### Commits stilistisch

Imperativ-Form, kurze erste Zeile (≤ 70 Zeichen), Leerzeile, dann Begründung. Erste Zeile beantwortet „Was?", Body beantwortet „Warum?".

```
Restore previously-removed activity assertions (fix #44)

Commit e9ef994 shifted Zen jiggle to a single IOPMAssertion... and
removed two older activity signals. Per the maintainer's note on the
issue, those should come back — different APIs target different layers
of macOS's activity tracking...
```

Heredoc-Pattern fürs Commit-Message-Übergeben (vermeidet Quoting-Probleme):

```bash
git commit -m "$(cat <<'EOF'
Kurze Titelzeile

Längere Begründung über mehrere
Zeilen wenn nötig.
EOF
)"
```

## Tooling-State (wissen, ohne nachzufragen)

- **gh CLI:** authentifiziert als `timokox`, Token-Scopes: `gist`, `read:org`, `repo`, `workflow`. Reicht für alles was wir brauchen inkl. Branch-Protection.
- **Xcode:** 26.5, Build 17F42, arm64.
- **Deployment Target:** `MACOSX_DEPLOYMENT_TARGET = 10.15` (Catalina).
- **macOS-Tahoe-Host:** ja (User entwickelt selbst auf 26.x).
- **Branch-Protection auf master:** PR erforderlich (0 Reviews), Force-Push und Delete blockiert, Conversation-Resolution erforderlich, Admins nicht enforced.
- **Upstream:** `bhaller/Jiggler` — wir entwickeln **nicht** für Upstream, sondern unseren Fork weiter. Issues von Upstream sind referierbar, aber keine PRs gegen Upstream eröffnen ohne expliziten Auftrag.

## Anti-Patterns (nicht machen)

- ❌ `git push origin master` — wird abgelehnt, peinlich.
- ❌ `git commit --amend` auf gepushte Commits eines PR-Branches ohne `--force-with-lease`-Push.
- ❌ „Quick fix" direkt auf master ohne PR. Selbst Einzeiler gehen über PR.
- ❌ Commit-Message ohne Begründung im Body, wenn die Änderung nicht offensichtlich ist.
- ❌ `xcodebuild` mit voller Output-Ausgabe — die ~100 KB lassen den Kontext explodieren. Immer pipen.
- ❌ App via `open` starten und dann nicht killen — bleibt im Hintergrund und Status-Item-Icon stapelt sich.
- ❌ Issues mit Maintainer-spezifischen Themen (z.B. „bekomme dev account" / „App Store") — wir maintainen einen Fork ohne Distribution.

## Wenn ein PR-Build fehlschlägt

1. Erst lokal reproduzieren mit `xcodebuild` (oben).
2. Errors lesen — Compile-Errors haben Datei:Zeile:Spalte.
3. Wenn ARC-Bridge fehlt (`error: cast of Objective-C pointer type 'NSDictionary *' to C pointer type 'CFDictionaryRef'`): siehe `objc-macos-dev`-Skill.
4. Fix als **neuer Commit** auf demselben Feature-Branch (nicht amend, nicht squash bevor merge).

## Release-Build (wenn jemals nötig)

```bash
xcodebuild -project Jiggler.xcodeproj -scheme Jiggler -configuration Release build
```

Liegt unter `~/Library/Developer/Xcode/DerivedData/Jiggler-*/Build/Products/Release/Jiggler.app`. Für Distribution wäre `codesign` + `xcrun notarytool` nötig — ist aktuell **nicht** eingerichtet, kein Apple Developer Account konfiguriert. Lokale Release-Builds laufen, aber sind nicht signiert.
