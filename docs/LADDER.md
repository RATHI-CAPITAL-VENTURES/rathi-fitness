# The ladder

`Tally.milestones` — the things your lifetime tonnage is measured against, and
the rules for changing them.

A number like "184,800 lb" is not a feeling. Nobody has an intuition for it, so
it reads as a serial number and gets ignored. Giving it something to be the size
of costs one table row per tier, and that is the whole feature.

## Three rules

**1. Every mass is real.**

330,000 lb is a blue whale because a blue whale weighs about that, not because
it made a nice curve. This matters more here than in most apps: every other
figure on the Trends screen is measured — your tonnage, your records, your
weigh-ins — and one invented scale sitting beside them would undermine all of
them.

Where the real figure is a range, take a representative adult and say so. Where
it is contested, take the common published number and name which one.

**2. It never ends.**

The first version stopped at a Space Shuttle. At four sessions a week that is
about **eighteen months**, after which the screen said "you have lifted
everything on the list" and had nothing further to say — for the rest of your
training life.

The heavy end is now deliberately absurd and still real. At ~2.7M lb a year the
Great Pyramid is roughly four thousand years away. Nobody reaches it, and that
is the point.

The rejected alternative was a generated tail — once the named tiers run out,
count in multiples: "two Great Pyramids", "three Great Pyramids". It is
provably infinite and it is filler. A made-up rung is exactly what this ladder
refuses to be, and nobody gets there to see it either way.

**3. It only ever climbs, and the order is tested.**

`testTheLadderOnlyEverClimbs` asserts ascending order, no duplicate weights and
no duplicate names. It exists because it caught a real one: the Eiffel Tower was
entered at 2,000,000 lb and sat *below* the Space Shuttle. The tower's puddle
iron is about 7,300 tonnes — roughly **16 million lb** — so the figure was eight
times too light and in the wrong place. It shipped, and was found by asking what
happens after the last tier rather than by anything automatic.

## Adding a tier

1. Add a row to `Tally.milestones`, in weight order.
2. Put the mass in pounds, rounded, with the real-world figure in a comment if
   it needs one.
3. Generate a badge in the locked style (below) and add it under
   `Assets.xcassets/Milestones/<art>.imageset`.
4. `testEveryMilestoneHasItsArtwork` will fail if the `art` name does not
   resolve. Nothing else checks the picture, deliberately — see below.

## The badges

One prompt, reused verbatim, so twenty badges read as one set:

> Flat vector icon inside a thin hexagonal badge outline. Background is solid
> pure black #000000, completely flat and even, edge to edge, with NO glow, NO
> bloom, NO halo, NO ambient light, NO vignette, NO gradient in the background.
> Subject and hexagon drawn in crisp mint-green and pale teal with hard clean
> edges. Minimal, modern, high contrast, no text, no numbers, no lettering,
> centred, generous margin, symmetrical.

Then **post-processed to transparency** — this part is not optional. The model
returns an opaque black field even when asked not to, and this app's background
is a tinted `RoomBackground` rather than `#000`, so an opaque badge draws its own
black square on top of it. Clamp anything below a luminance threshold to alpha
zero and feather the rim by brightness so the hexagon keeps a clean edge.

That defect shipped once. Every test passed through it: `UIImage(named:)`
resolved, the asset catalog was valid, the layout was right, and the screen was
wrong. **The only way to catch it is to render the screen and look at it**,
which is why the artwork test claims no more than that the file exists.

## The tiers

| Tier | Pounds | What it is |
| --- | ---: | --- |
| A grand piano's lid | 250 | a concert grand's lid alone |
| A grand piano | 1,000 | concert grand |
| A horse | 2,000 | draft horse |
| A Honda Civic | 2,900 | kerb weight |
| A rhinoceros | 5,000 | white rhino, adult |
| A hippopotamus | 8,000 | adult |
| An African elephant | 13,000 | adult bull |
| A school bus | 25,000 | full-size, empty |
| A humpback whale | 66,000 | ~30 tonnes |
| An M1 Abrams tank | 140,000 | ~70 short tons |
| A blue whale | 330,000 | ~150 tonnes |
| The Statue of Liberty | 450,000 | copper and steel, 225 short tons |
| A Boeing 747 | 875,000 | maximum take-off weight |
| A Space Shuttle at launch | 4,500,000 | full stack, ~2,030 tonnes |
| The Eiffel Tower's iron | 16,000,000 | puddle iron, ~7,300 tonnes |
| The Titanic | 117,000,000 | displacement, ~52,310 long tons |
| A Nimitz-class carrier | 224,000,000 | ~100,000 long tons, full load |
| The Empire State Building | 730,000,000 | ~365,000 short tons |
| The Golden Gate Bridge | 1,770,000,000 | ~887,000 short tons |
| The Great Pyramid of Giza | 13,000,000,000 | ~5.9 million tonnes |

At four sessions a week the first fourteen are about eighteen months. The
fifteenth is roughly six years, and the last is not reachable by anyone.
