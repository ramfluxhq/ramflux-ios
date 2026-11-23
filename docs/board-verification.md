# Board verification

Screens are judged against the current design at pixel level. Four pieces work
together; all of them live in this repository.

| Piece | File | Role |
|---|---|---|
| References | `shell-previews/*.png`, `shell-previews/manifest.json` | 1x images of the design boards with their provenance |
| Captures | `AppTests/ShellBoardCaptureTests.swift`, `AppTests/CaptureMatrix.swift`, `AppTests/Fixtures/BoardFixtures.swift` | Board renders over the capture matrix |
| Comparison | `scripts/compare-boards.py` | Pixel difference, regions, checklist, pairs and diffs |
| Known deviations | `shell-previews/expected-deviations.json` | Reviewed list of differences still to align |

## References

The design exports are 2x PNGs of 393x852 pt boards. `scripts/design-references.py`
derives 1x references (one pixel per point) with a 2x2 box average in
premultiplied RGBA and records, per reference, the design board key, the node
id, the export's SHA-256, the reference's SHA-256 and the design file's SHA-256.
Comparison happens at 1x because captures are taken at one pixel per point and
deviations are reported in points; the transparent board corners are not
compared.

- `design-references.py --check` (CI) verifies every reference against the
  manifest and rejects unlisted images.
- `design-references.py --check --boards <exports> --design-file <file>` reports
  STALE when an export or the design file changed since the references were
  derived. `--update` re-derives them. References are never edited by hand.

`board` in the manifest is the capture a reference is compared with; `key` is
the design board. Dark proofs are the dark references of their screens
(MOB-DK01 for MOB-B02, MOB-DK03 for MOB-B01).

## Captures

`CaptureMatrix` is the single parameter list for every capture test:

| Dimension | Values |
|---|---|
| Locale | `en`, `zh-CN`, `en-XA` (expanded pseudo-locale), `ar` (right to left; no catalog yet, so copy falls back to English) |
| Canvas | 320x568, 393x852, 744x1133 pt |
| Text size | `default` (large), `ax3` (accessibility3) |
| Theme | `light`, `dark` |

`ShellBoardCaptureTests` renders every board with a fixture over the full
matrix into `SHELL_CAPTURE_DIR` (set `TEST_RUNNER_SHELL_CAPTURE_DIR` for
`xcodebuild`) as `<board>-<locale>-<width>-<textSize>-<theme>.png`, in 8-bit sRGB
at one pixel per point. Feature snapshot tests attach the same locales and
canvases. Adding a value to a list extends every capture; no test is duplicated
per locale.

Board fixtures carry the content of the design boards (names, previews, counts,
times) per fixture language. Chinese reproduces the zh boards, English the en
boards where they exist, Arabic is a right-to-left sample with mixed Latin
names, digits and an @mention. Fixture text is data, never catalog copy.

```sh
xcodegen generate
TEST_RUNNER_SHELL_CAPTURE_DIR=/tmp/shell-ios-captures xcodebuild -project Ramflux.xcodeproj \
  -scheme Ramflux -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:RamfluxTests/ShellBoardCaptureTests CODE_SIGNING_ALLOWED=NO
```

## Comparison

```sh
python3 scripts/compare-boards.py /tmp/shell-ios-captures shell-evidence --review
```

Only the 393-wide, default-size captures are compared with references:
`<board>-<locale>-393-default-<theme>.png` for each manifest entry.

1. A pixel differs when its largest channel difference exceeds 32/255 and the
   other image has no pixel within that tolerance in its 3x3 neighbourhood, in
   both directions. One-pixel anti-aliasing and edge shifts therefore pass;
   larger shifts do not.
2. Differing pixels are grouped into regions (8-connected 4 px cells). A region
   larger than 2 pt in either direction is a deviation.
3. Each region is reported with its box (x, y, w, h in points) and the ink box
   change between reference and capture inside it, `ink dx dy dw dh`. The ink
   measure is approximate when a region touches neighbouring elements.

Output in the output directory:

- `checklist.md` and `checklist.tsv`: per board the status (pass, known
  deviation, NEW deviation, known or NEW missing capture), the share of
  differing pixels, the region count and the largest regions;
- `pairs/<reference>--pair.png`: capture, reference and diff side by side;
- `diffs/<reference>--diff.png`: the capture faded, differing pixels red,
  expected rectangles amber, new deviations magenta;
- `review.tsv` with `--review`: findings for the rest of the matrix (blank
  capture, ink cut at a side edge, content in the home-indicator band of a
  board without a tab bar, an `ar` header on the same side as its left-to-right
  capture, a larger text size that changes almost nothing). Review findings
  are artefacts for reviewers; they do not fail the run.

The run exits 1 when any NEW deviation exists. `scripts/tests/test_compare_boards.py`
proves that an identical capture passes, a one-pixel edge shift passes, a moved
element or a colour change fails with its offset measured, and expected entries
behave as described below.

## Kit comparison

Kit components are compared separately with the Kit design previews:

```sh
cd Packages/RFDesign
TEST_RUNNER_KIT_CAPTURE_DIR=/tmp/kit-ios-captures xcodebuild -scheme RFDesign \
  -destination 'platform=iOS Simulator,name=iPhone 17' test \
  -only-testing:RFDesignTests/KitCaptureTests -only-testing:RFDesignTests/KitCoverageTests CODE_SIGNING_ALLOWED=NO
cd ../..
python3 scripts/compare-kit-previews.py kit-previews /tmp/kit-ios-captures kit-evidence-out
```

`Packages/RFDesign/kit-masters.json` records the master frame where a preview
export is a board instance rather than the component frame. A capture edge more
than 2 pt from the master is OVER.

`row--tag` has no master entry: its 361x92 export canvas is the row frame. In
the design file the M/Row master is 58 pt with an 8 pt vertical inset and
centred content, and every M/Row instance with this two-line value
("Chrome · macOS row") overrides the height to 92 pt. The export agrees: the
icon tile and the chevron are centred on y = 46 pt and the text spans 22.5 pt
to 73 pt of the 92 pt canvas. `KitRow` therefore keeps the 8 pt inset while its
label and value each fit on one line and uses a 16 pt inset when either wraps,
which puts the two-line row at 92 pt. A row with three or more lines follows
the same rule; the design has no instance of one. What remains is inside the
frame and does not change it: the design's M/Row label and value line heights
are 1.4 and 1.3 of the font size, the Kit's are 1.3 and 1.4, and the design
sets the title in the Latin face. In the iOS 26.5 capture the title ink spans
19-33 pt against 22.5-34.5 pt in the export and the value lines start 1 pt
further apart. Changing the row's line heights is a design-alignment decision
for wave 2, not part of the frame check.

## Expected deviations

`shell-previews/expected-deviations.json` records, per reference, a reviewed
reason and the rectangles (points) where differences are known, or
`"status": "no-capture"` for references without a capture yet. It is the
wave-2 work list.

- A region is known when nearly all of its differing pixels lie inside the
  expected rectangles grown by 4 pt. Anything else is NEW and fails.
- An expected rectangle with no differing pixel left is reported as resolved:
  shrink or remove the entry in the same change that aligned the screen.
- An entry whose reason is `UNREVIEWED` fails the run.
- `--write-expected <file>` writes a draft from the current captures, keeping
  existing reasons. A draft is only committed after every reason is reviewed
  against the pairs; an entry is never widened to hide a new difference.

Entries were re-reviewed after the chat foundations (scalable Kit text,
system-text message bubbles, per-script faces) were stacked on the board
verification work: each changed reference was compared pair by pair and its
reason extended with what moved and why; no rectangle was accepted in bulk.

Wave 2 pass 4 redrew the onboarding and unlock screens (MOB-S01, S02, S18, N01, A01, A02) and added
the MOB-A07 capture; each of those entries was re-recorded from its own pair and its reason rewritten
with the remaining residuals; no other entry changed.

## Capture toolchain

CI runs on the hosted `macos-26` image with Xcode 26.6, the newest Xcode any
hosted macOS image offers (`macos-15` ends at 26.3; no image has 27.x). Board
and Kit captures are taken on iPhone 17 Pro with the iOS 26.5 simulator runtime:

```sh
python3 scripts/select-simulator.py --device "iPhone 17 Pro" --ios 26.5
```

prints that simulator's UDID and fails, listing what is installed, when it is
missing; it never falls back to another device or runtime. Glyphs are
rasterised by the simulator runtime, so the runtime belongs to the capture
toolchain as much as Xcode does; CI used to take the first listed iPhone, which
on `macos-15` was the iOS 18.5 runtime. Change `DEVELOPER_DIR`, `CAPTURE_DEVICE`
and `CAPTURE_IOS` in `.github/workflows/ios.yml` together, and re-review the
baselines as described below whenever they change.

The comparison is not made independent of the toolchain. The references are
rasterised by the design tool and the captures by Core Text in the simulator
runtime; no rasteriser is shared by both sides, and the tolerance already
absorbs one-pixel anti-aliasing and edge shifts. Whatever text rasterisation
leaves beyond that is recorded per toolchain instead of being tolerated
globally.

## Re-reviewing the baselines on the CI toolchain

The expected file was recorded locally with Xcode 27.2 and the iOS 27.2
simulator. On the CI toolchain the comparison can therefore report NEW regions
caused only by text rasterisation. They are not hidden by widening rectangles
or loosening thresholds; the baselines are re-reviewed from CI captures:

1. Every `kit-evidence` run whose board capture succeeded uploads the
   `shell-evidence` artefact, also when the comparison fails. It holds
   `checklist.md`, `checklist.tsv`, `review.tsv`, `pairs/`, `diffs/` and
   `expected-deviations.ci-draft.json`, a draft written with
   `--write-expected` from that run's captures. The comparison and its exit
   status always use the committed file; the draft is evidence only.
   `kit-evidence` (Kit comparison) and `kit-capture-result` (the Kit test
   result bundle) are uploaded alongside.
2. Download the artefact of the run to review:

   ```sh
   gh run download <run-id> -n shell-evidence -D /tmp/shell-evidence-ci
   git diff --no-index shell-previews/expected-deviations.json \
     /tmp/shell-evidence-ci/expected-deviations.ci-draft.json
   ```

3. The draft carries the existing reasons over unchanged and derives every
   rectangle from the regions of that run, so it is not reviewed until each
   changed entry is checked. For every entry whose rectangles changed, open
   `pairs/<reference>--pair.png` and `diffs/<reference>--diff.png`. Keep a
   changed or added rectangle only when the pair shows the same layout and the
   difference is glyph rasterisation (stem weight, anti-aliasing, a sub-point
   baseline or advance). A moved, resized, missing or recoloured element is a
   regression to fix in code, not a deviation to record. A reference that
   compares with a size mismatch has no draft entry and must be fixed.
4. Copy the reviewed draft over `shell-previews/expected-deviations.json`,
   extend each changed reason with what changed and the toolchain it was
   recorded on, update the toolchain sentence at the top of this section, and
   commit. The next CI run must report `NEW 0`.

The same procedure applies locally with the CI runtime: capture on the pinned
simulator as in [Captures](#captures) and run

```sh
python3 scripts/compare-boards.py /tmp/shell-ios-captures shell-evidence --review \
  --write-expected shell-evidence/expected-deviations.draft.json
```

A local recording uses the local Xcode's SDK with the CI runtime, which is
close to CI but not the same toolchain; the committed file is reviewed from a
CI draft.
