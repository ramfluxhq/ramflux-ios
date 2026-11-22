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

The expected file was recorded from Xcode 27.2 and the iOS 27.2 simulator.
Text rendering can differ between Xcode versions; CI is pinned to Xcode 26.2,
so the first CI run on that toolchain may report new regions caused only by the
toolchain. Those are fixed by recording on the CI toolchain, not by widening
rectangles.
