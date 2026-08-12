# Working on this repo

Gebärden is a Flutter app for learning German Sign Language, built on the
SignDict API. No backend, no account, everything stays on the device.

This file describes how work is done here. `README.md` explains the app itself
and how to build it, `docs/adr/` records the decisions behind it, `RELEASING.md`
covers publishing. What is written there is not repeated here.

A note on languages: only the user interface is German. Everything else is
English, documentation, code comments, test names and commit messages
included.

## Rules

Each of these comes from a bug that already reached the main branch.

1. Tests say nothing about platform behaviour. Downloads, notifications,
permissions, files, video and app lifecycle have to run on the emulator. The
downloader passed 522 tests twice while being broken, because the fault was in
the native queue that no fake reproduces.

2. Check a feature by using it. The daily reminder was reported as finished
although it never fired once. `flutter_local_notifications` stopped shipping
its broadcast receivers in version 16, so the alarm went off into nothing and
no error appeared anywhere. That the alarm is registered says nothing about
whether the notification arrives.

3. Test the way between screens, not only the screens. Every screen rendered
correctly while "Diese Liste lernen" crashed the app, because it pushed a tab
shell route onto itself.

4. Measure instead of guessing. If you do not know where the time goes, add
instrumentation and read the number. One log line (`reset cancelled=10` with
7800 files still outstanding) found a cause that had been guessed wrong twice.
For coverage, parse `coverage/lcov.info` and count files lcov never loaded into
the denominator. A reported 70 percent was really 17.

5. Look up versions. Every dependency, action and tool takes the newest release,
checked on pub.dev, the GitHub releases page or PyPI before it is written down.

6. Do not remove the condition under test. Granting the notification permission
with `adb shell pm grant` and then testing the permission request proves
nothing. Uninstall, reinstall, grant nothing.

7. Copy `-wal` and `-shm` along with `gebaerden.sqlite`. The database file alone
is stale and shows plateaus that do not exist.

8. Report what is still broken, in the answer and in the commit message. A
leftover written off as acceptable turned out to be the next complaint.

## Checks before a commit

```bash
dart format --set-exit-if-changed .
flutter analyze                       # must say "No issues found"
flutter test                          # all of them
flutter test --coverage && python3 tools/coverage.py 95
```

Plus, as soon as platform behaviour is involved:

```bash
flutter test integration_test -d <device>   # against the live API
flutter build apk --debug                   # does it even build
```

Coverage below 95 percent fails CI. `pre-commit` runs format, analysis and
tests before every commit. Without the hooks, CI checks the same on every pull
request.

After changing `lib/db/tables.dart`:

```bash
dart run build_runner build --delete-conflicting-outputs
```

Finish the whole task before committing.

## Before writing code

From ponytail. The best code is the one never written. Read the task and the
code it touches and trace the real flow first, then stop at the first rung that
holds:

1. Does this need to exist at all?
2. Does it already exist in this codebase? Reuse the helper or the pattern.
3. Does the standard library do it?
4. Does a platform feature cover it?
5. Does an already installed dependency solve it?
6. Can it be one line?
7. Only then write the minimum that works.

- A bug report names a symptom. Fix the shared function once and grep its other
  callers, instead of patching the one path the report happens to name.
- No abstraction that was not asked for, no avoidable dependency, no
  boilerplate nobody wanted.
- Deletion over addition, boring over clever, as few files as possible.
- The shortest working diff wins, but only after the problem is understood. The
  smallest change in the wrong place is a second bug.
- Ask back on complex requests: is X needed, or does Y cover it.
- None of this applies to understanding the problem, input validation at trust
  boundaries, error handling that prevents data loss, security, accessibility,
  or anything explicitly requested.

## Code

- Comments and documentation in English, user interface in German.
- As few comments as possible. Most lines need none.
- A comment says why, not what. The code already says what it does. The most
  useful kind explains why the obvious approach did not work.
- No comment that reads like it was generated. No cheerful asides, no restating
  the line below, no explaining the language. `// which is what makes the app
  work on a plane` is an example of what to avoid.
- No suppressed diagnostics. No `// ignore:` to silence the analyzer, no casts
  that hide an error. `analysis_options.yaml` is strict and stays green.
- Early returns instead of nesting, small functions, no abstraction on spec.
- Errors the user can see get a German sentence that says what to do. No raw
  exceptions on screen.
- When fixing a bug, fix only the bug. Refactoring goes in its own commit.

## Writing

Applies to commit messages, the README, headings, answers and any other prose.

- No em-dashes.
- No semicolons.
- No "not X, but Y" constructions.
- No bold for emphasis.
- No emoji.
- Plain headings that name the section. Not "The rules that were paid for",
  just "Rules".
- No aphorisms, no punchlines, no dramatic summaries. State the fact and stop.
- No status tables, no "measured against" scorecards in the README.
- Never report something as working that was not observed working.

## Answers

From caveman. Applies to what is said in the chat. Code, comments, commit
messages and documentation stay normal prose.

- Terse. Drop filler, pleasantries and hedging. Fragments are fine.
- German, because that is what the user writes. Compress the style, not the
  language.
- No narrating tool calls, before, between or after them. Run them and report
  the result.
- Never drop not, never, no, only, except. Numbers and units stay exact.
- No invented abbreviations. Well known ones like API or HTTP are fine.
- No causal arrows.
- Code, commands and error strings verbatim. Quote the shortest decisive line
  of an error instead of the whole log.
- Full sentences again for security warnings, irreversible actions and anything
  where terseness would blur the order or the meaning.
- Never name or announce the style.

## Design

The app should not look generated. Material out of the box is recognizable at a
glance, so buttons and rows are built from `InkWell` and `Container` instead of
`ElevatedButton` and `ListTile`. Warm neutral surfaces, one accent color, the
system font. The accent is freely chosen at runtime. `accented` in
`lib/theme.dart` raises or lowers any picked color until it clears 4.5:1 on
the current background, since the picker accepts any color.

Minimum tap target is 48 px. `test/a11y_test.dart` checks contrast in both
brightnesses, for the suggested colors and for extremes like white and yellow.

## Decisions

- Cross-platform only. A fix that exists on Android alone does not count. If a
  stack cannot do that, the stack is replaced.
- iOS ships unverified. There is no device to test on. The README says so.
- On a research request, deliver options with trade-offs and versions, no plan
  and no decision, until the choice has been made.
- FSRS weights differ between `ts-fsrs` and `dart-fsrs`. Settled, do not
  reopen. Backups from the Svelte version do not have to import.

## Tests

- Every fix ships with a test that fails without it. Revert the fix, run the
  test, watch it go red.
- Test names are lowercase English sentences: `a paused row keeps its counts`.
- `test/` runs without network and without a device. `integration_test/` runs
  on a device, needs `-d <device>`, and splits in two. `app_test.dart` goes
  against signdict.org and checks that the API still returns what the app
  expects. `learn_test.dart` drives the trainer through the real shell off
  seeded rows, no network. The reminder case needs
  `adb shell pm grant gg.prinz.gebaerden android.permission.POST_NOTIFICATIONS`
  while the run is up.
- Widget tests use the fake clock. Real file and network work needs
  `tester.runAsync`, followed by `drain(tester)` so no timers stay pending.
  The platform channels live in `test/channels.dart`, the video player in
  `test/fake_video.dart`. The downloader accepts only one listener, hence
  `resetUpdates()` in `setUp`.
- Images are never decoded in a widget test, so an `errorBuilder` fallback
  cannot be triggered there. That one goes on the device.
- A test that only proves something in a particular time zone must still pass
  under UTC. CI runs on UTC.

## Platform traps

`background_downloader`: `enqueueAll` hands the whole list over in one call and
the native side then walks it for minutes on its own. That is why tasks go over
in blocks, and between blocks the package row decides whether to continue.
`reset(group:)` only stops what is in the queue at that moment, so it is
repeated until two rounds in a row find nothing. Records are the only thing a
task can come back from: `rescheduleKilledTasks` re-enqueues everything that
looks open. Pausing and cancelling therefore delete them, and on start the open
records of every package that is not running are dropped.

`initNotifications` comes before `downloads.start()`. The queue mirrors its
package rows into the shade the moment it starts, and a plugin that has not been
initialized has no small icon, which the native side answers with a
NullPointerException rather than a notification.

Plugins need manifest entries that nothing enforces. A missing receiver costs
nothing at build time and silently swallows the feature. Check the merged
manifest under `build/app/intermediates/merged_manifest/` and pin what is
needed in `test/manifest_test.dart`.

From Android 15 the app draws under the system bars and nothing paints them for
it. Without an explicit `SystemUiOverlayStyle` the system enforces its own
contrast, and under three-button navigation that lays a dark band over the
light theme. Gesture navigation hides the whole problem, so it has to be
checked with `cmd overlay enable com.android.internal.systemui.navbar.threebutton`.

Dart does time arithmetic on instants. `subtract(Duration(days: 1))` subtracts
exactly 24 hours and lands next to midnight across a daylight saving change.
Days are built from calendar parts: `DateTime(y, m, d + n)`.

Flutter picks its own JDK, first the one from Android Studio and only then
`JAVA_HOME`. To get rid of the JVM warnings during a build, set
`flutter config --jdk-dir`.

Without a granted permission the downloader shows no notification. It checks
before every single one. Once the user has declined, the system stops showing
the dialog and the call returns immediately.

Individual files are missing upstream. A 403 on a thumbnail is normal. A whole
package must not fail over one of them, otherwise the job disappears from the
list and the download looks like it stopped.

## Git

- Commit messages are short, 250 characters at most. A subject line is often
  the whole message. A body, if needed, says what was wrong and how you can
  tell it is right now.
- English. German only where the subject is a German string or text.
- No `Co-Authored-By` trailer.
- Commits are local. No `push`, no pull request, unless asked for.
- No unrelated changes in the same commit.

## Unclear requirements

Ask instead of assuming. Two readings with very different effort are worth a
question, and so is a request that contradicts the code.
