# MeetingHop brand

Small app, small brand: one mark, one accent, one type stack. Everything here
is rendered from code or drawn with system primitives — there is no asset
pipeline and no Xcode asset catalogue.

## The mark

A video camera with a straight arrow driving into it.

```
 ┌────────────┐
 │    ──▶     │◣
 └────────────┘
```

The body is the call, the arrow is you, and there is no metaphor to decode:
the icon says get in. MeetingHop's whole job is putting you in the next
meeting on time, and the mark states that literally rather than illustrating
it.

The cost is deliberate and worth naming: a video camera is the most crowded
glyph in this category — Zoom, Meet and Teams each own a version — so the
icon buys instant recognition and pays for it in distinctiveness.

### What it replaced

The first mark was a hop: two filled dots on a baseline with a dashed arc
springing from one to the other. It never worked. The arc faded out above and
to the left of the second dot instead of landing on it, so it read as a broken
path rather than a leap, and two dots joined by a curve is the pen tool's own
icon — a path and its anchors, not motion.

Four other directions were drawn and rejected before the camera, each for a
reason worth keeping: the countdown dial as a solid sector read as Pac-Man;
as a thick annulus it read as a letter C; an alarm clock's bell ears looked
pasted on and turned to noise at template size; and a clock whose minute hand
ran out of the hour and continued as an arrow drew well at 1024 but said
nothing about a meeting, and lost its arrow entirely at 18 pt, where the head
and the rim pile up into a blob whichever way they are spaced.

### Construction

- `packaging/icon/make-icons.swift` is the **source of truth** and renders
  both: `make icons` writes `dist/icon/MeetingHop.icns` plus the menu-bar
  template at 1x/2x/3x. SVG rasterisers available without extra tooling
  silently drop gradients and strokes, so the shapes are drawn in
  CoreGraphics instead.
- **One drawing at two sizes.** The mark is authored on the 18 pt menu-bar
  grid and scaled UP onto the icon's 1024 grid (700 units wide, centred at
  512, 508), rather than drawn large and reduced. `drawCamera` is called by
  both renderers, which is the only thing stopping the two from drifting
  apart — they had already drifted once, and the small one had the better
  proportions.
- **The arrow is knocked OUT of the body**, not drawn on top of the gradient.
  The body carries the mass and the arrow only has to carry contrast, which is
  what lets it stay fine enough to look right at 1024 and still register at
  16 px. Drawn as a stroke on the gradient at that weight it would vanish.
- **The gap between body and lens is load-bearing** — 56 units at 1024. Closed
  up, the two shapes fuse into a single hexagon and the camera is gone.
- **The arrow is half the body's height, not four fifths.** The first version
  filled 80% of it and swamped the camera it was supposed to be entering. The
  head is wider than the shaft is thick, so it still reads as an arrow rather
  than a bar.
- **The arrow is centred by measurement, not by eye.** Rendering the body and
  the arrow separately and comparing bounding boxes caught it sitting 21 units
  left of centre; it now sits 113/112 px horizontally and 98/98 px vertically
  at 1024.
- The app icon body is a **superellipse**, not a circular-cornered rectangle —
  at 1024px the difference between the two is visible against every other
  icon in the Dock. Same construction as AgentMenu's.
- The menu-bar image is a **template**: alpha only. macOS tints it for the
  light menu bar, the dark menu bar and the highlighted state, so any colour
  baked in would be discarded.

## Colour

| Role | Light | Dark |
|---|---|---|
| Accent (Join, the countdown dial, the mark) | `#D6336C` | `#FF6B9D` |
| Icon gradient | `#FF7EB6` → `#D6336C` → `#5E102E` | same |
| Urgent state | `#E61D53` | `#FF4C7A` |

Rose, shared with AgentMenu on purpose — the two apps live in the same menu
bar and are meant to read as one family, the way a product line shares a
mark language across its apps rather than each app inventing its own.

The urgent state — the countdown closing in on zero — pushes the same rose
hotter rather than switching to AgentMenu's amber. That amber marks a
specific, different kind of moment over there: a click that starts an agent
which never asks for confirmation, an irreversible action. Borrowing it here
for "your meeting is about to start" would put one colour on two unrelated
meanings across the pair, and the one place that distinction actually
matters — the sibling's bypass warning — would stop being unambiguous. A
meeting starting is urgent, not irreversible, so it gets the app's own accent
turned up, not the neighbour's warning colour.

**Standard controls keep the user's system accent.** Only MeetingHop's own
chrome — the mark, the dial, the Join button, the service badge — uses the
brand accent. A checkbox or a system control that ignores the accent colour a
user chose in System Settings looks broken, not branded.

Everything else is system colour: `NSColor.labelColor`, `secondaryLabelColor`,
`separatorColor`, the panel's own material. That is what makes the app look
native in both appearances without maintaining two palettes.

## Type

The system stack, at system sizes: SF Pro Text via `.system(size:weight:)`.
15pt semibold for the meeting title, 11.5pt regular for the context line
underneath it, 13pt semibold on the Join button. No webfont, no custom face —
a HUD card the size of a notification is the wrong place to introduce one,
and SF is what every other menu-bar item and every other notification on the
machine is set in.

## Where the personality lives

The HUD card is MeetingHop's own surface: the mark, the accent, the
countdown dial. Everything around it — the menu-bar item's idle state, the
settings window — stays plain, laid out the way macOS lays out its own
chrome. A settings window that expresses a brand is a settings window people
have to learn.
