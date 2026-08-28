# RGB color-space conversion

The canonical `Color.init(_:red:green:blue:opacity:)` converts its three RGB
components into encoded extended sRGB before storing them in the existing
renderer-neutral `SwiftWindowsCore.Color`. The representation remains four
unpremultiplied `Float` components, without a color-space tag. This corrects
constructor component semantics; it does not change rendering surfaces,
blending, output gamut, or baseline qualification.

Apple documents extended-range sRGB inputs for this initializer and explicitly
describes `.sRGBLinear` as using the same colorimetry with a linear transfer
function. Negative components and components above one must therefore survive
the conversion when they fit the retained representation.
[RGB initializer](https://developer.apple.com/documentation/swiftui/color/init(_:red:green:blue:opacity:)),
[linear sRGB](https://developer.apple.com/documentation/swiftui/color/rgbcolorspace/srgblinear).

## Transfer and primaries

`RetainedColorSpaceConversion` is an internal, stateless WinSwiftUI helper.
The canonical initializer transforms the complete RGB triple once:

| Input space | Conversion to retained encoded extended sRGB |
| --- | --- |
| `.sRGB` | Identity, apart from the explicit invalid-input and Float-storage policies below. |
| `.sRGBLinear` | Apply the signed sRGB encoding curve independently to each linear component. |
| `.displayP3` | Decode the signed transfer curve, transform the linear primaries, then encode the result. |

Display P3 uses DCI-P3 primaries, D65 white, and the sRGB transfer function.
The two spaces share D65, so the conversion needs no chromatic adaptation.
[Apple Display P3](https://developer.apple.com/documentation/swiftui/color/rgbcolorspace/displayp3).

For an encoded component `c`, decode with `c / 12.92` when
`abs(c) <= 0.04045`; otherwise use
`sign(c) * ((abs(c) + 0.055) / 1.055)^2.4`.
For a linear component `l`, encode with `12.92 * l` when
`abs(l) <= 0.0031308`; otherwise use
`sign(l) * (1.055 * abs(l)^(1 / 2.4) - 0.055)`.
Apple also describes the signed reflection for extended sRGB.
[Extended sRGB](https://developer.apple.com/documentation/appkit/nscolorspace/extendedsrgb).

The linear matrix is the exact rational product
`XYZ-D65-to-linear-sRGB * linear-P3-to-XYZ-D65` from the dated
[W3C CSS Color 4 conversion sample](https://www.w3.org/TR/2026/CRD-css-color-4-20260825/#color-conversion-code).
Rows multiply the RGB column vector:

```text
[ 3685649/3008840       -676809/3008840                 0 ]
[-5617931/133579120   139197051/133579120               0 ]
[-1323971/67420360     -1514763/19262960   148092003/134840720]
```

Each row sums to one exactly before binary rounding. The implementation
evaluates these ratios and transfer operations as `Double`, and narrows only
the final encoded components. It does not apply the matrix to encoded input,
premultiply RGB, or clip to the unit interval. The W3C sample is informative;
these equations and tests are not observations of Apple's implementation.

Examples derived from that math, before Float narrowing:

| Input | Retained encoded extended sRGB |
| --- | --- |
| P3 `(1, 0, 0)` | `(1.0930663624, -0.2267419736, -0.1501345809)` |
| P3 `(0.1, 0.2, 0.3)` | `(0.0593560814, 0.2030894066, 0.3087304098)` |
| Linear sRGB `(-0.25, 0.5, 2)` | `(-0.5370987305, 0.7353569831, 1.3532560461)` |

The published transfer thresholds have a tiny rounding discontinuity. Tests
check the stated branches and use appropriate precision; they do not require
an exact inverse at that boundary.

## Numeric policy and compatibility limits

The supported storage domain is finite RGB whose converted encoded sRGB
components fit `Float`, at Float precision. It is not every finite `Double`.
Final conversion rounds to Float; very small components can underflow.
`Float.greatestFiniteMagnitude` is approximately
`3.4028234663852886e38`, and the smallest positive Float subnormal is
approximately `1.401298464324817e-45`.

The canonical RGB initializer uses these deterministic Windows rules:

1. Replace each NaN or positive/negative infinite input RGB component with zero
   before conversion. Other input components are unchanged.
2. Perform transfer and matrix arithmetic in Double. If any decoded P3,
   transformed linear, or encoded result is nonfinite, return an all-zero RGB
   triple. This handles extreme finite inputs that overflow the intermediate
   representation; it is not gamut clipping.
3. After conversion, saturate finite RGB components beyond the representable
   Float range to the corresponding positive or negative finite Float limit.
   A defensive nonfinite value at this final storage boundary becomes zero.

There is no input or intermediate clamp to `[0, 1]`. All finite,
Float-representable encoded P3 inputs have Double intermediates well inside
Double's range, although a transformed output can exceed the Float limit.
The runtime checks define the overflow boundary; the implementation does not
silently assume every finite source value can be represented.

Apple's referenced documentation does not establish NaN, infinity, or
unrepresentable-range behavior for this initializer. These rules are an
explicit Windows policy, not a claim of native parity for invalid input.

Alpha still follows the previous direct `Float(opacity)` conversion, including
existing behavior outside the documented opacity interval. RGB conversion does
not multiply by alpha, including when alpha is zero. This slice does not change
the legacy Float/`alpha:` initializer, the separate Double/`opacity:` overload
without a color-space parameter, HSB construction, or opacity modifiers.

Both white initializers keep their existing early unit-interval clamp and
opacity handling. Their extended-range behavior remains an explicit gap;
passing the RGB tests does not qualify the white API.

## Retention is separate from output

`Color` can retain extended components, but current scene and raster paths
cannot display all of them. `GPUIScene.add*` sanitizes quad, glyph, shadow, and
gradient colors to the unit interval. Solid path colors are clamped when
rasterized. The CPU path emits BGRA8. The D3D11 shaders saturate RGB and its
current render targets are `B8G8R8A8_UNORM`.

Those boundaries, current component-space blending/interpolation, and the
existing premultiplication rules are unchanged. No wider render target,
ColorSync integration, output-profile selection, HDR support, or native
SwiftUI drawing-group color-space behavior is implied. Constant-color
appearance resolution and `Color.Resolved` compatibility are separate from
this constructor conversion.

The tests distinguish these layers: stored P3 red keeps its negative channels,
while an explicit quad reaches the existing scene clamp and produces ordinary
red BGRA8 bytes. An in-gamut P3 color and its explicit sRGB equivalent produce
the same CPU bytes. Those assertions test this renderer's contract, not native
reference pixels.

## Tests and a separate native observation plan

`WinSwiftUIColorSpaceConversionTests` covers the pure conversion with literal
standards-derived values, signed transfer branches, neutral colors, extended
values, invalid inputs, intermediate overflow, and final Float bounds.
`WinSwiftUIColorInitializerTests` covers public overloads, alpha independence,
unchanged legacy/white behavior, and the storage/output distinction.
`WinSwiftUITests` replaces the earlier P3 passthrough and linear-clamping
expectations. No existing image baseline or comparison threshold changes.

Native validation is a separate follow-up, not evidence supplied by these tests:

- Put fixed RGB constructor cases in a small shared source file with only
  conditional SwiftUI/WinSwiftUI imports. Use public Double/`opacity:`
  construction and fixed identifiers; keep Windows-only `alpha:` extras out
  of that file.
- Use a Windows observation adapter that reads the retained `Color` fields.
  A separate macOS adapter should read the explicit encoded-sRGB getters from
  native `Color.resolve(in:)`. Do not mistake the resolved type's linear
  storage or `linearRed` family of accessors for encoded components.
  [Resolved color properties](https://developer.apple.com/documentation/swiftui/color/resolved).
- Record a second macOS observation using
  `NSColor(color).usingColorSpace(.extendedSRGB)`, if conversion succeeds.
  This remains a separately labeled bridge observation; conversion failure
  stays unavailable instead of falling back to untagged RGB.
  [NSColor conversion](https://developer.apple.com/documentation/appkit/nscolor).
- Include sRGB identity, nontrivial linear transfer, an in-gamut P3 triple,
  P3 primaries, extended sRGB, neutrals, and ordinary alpha controls. Repeat
  observations. An observer that clamps extended controls or returns empty,
  nonfinite, or constant output for every case is inconclusive.
- Keep finite extended-P3 input behavior and invalid-input behavior labeled
  separately until observed on the pinned native toolchain. Do not make the
  Windows invalid-input policy the expected Apple result.
- Bind output to the exact shared-case and adapter digests, source revision,
  executable, compiler/SDK capture identity, native architecture, and actual
  OS version/build. Pinned SDK provenance alone does not qualify runtime
  behavior. Keep the report candidate/unqualified until review.
- Any later swatch captures must record their capture/output color space and
  encoding. Standard sRGB PNG bytes cannot prove retention of negative values,
  wide-gamut output, or HDR. No native expected pixels are supplied by this
  conversion's numerical oracle.

A prospective layout is `scripts/fixtures/swiftui-color-rgb/` with separate
shared cases, observation DTOs, and Windows/macOS adapters. No such probe,
native execution, CI workflow, or new baseline is included in this slice.
