# Shared demo bitmap resources

`SwiftWindowsDemo` owns two small PNG test patterns under
`Sources/SwiftWindowsDemo/Resources`. Both its Windows and macOS target
declarations process this directory. The shared view uses ordinary
`Image(name, bundle:)`, `.resizable(capInsets:resizingMode:)`, and
`.scaledToFit()` calls through the target's generated `Bundle.module`.
The demo, offscreen snapshotter, visual gallery, and Windows CoreLogic tests
all consume that one target; they do not carry duplicate image copies.

The assets were authored for this repository, not downloaded artwork or
accepted rendering baselines. They are opaque, noninterlaced, eight-bit RGBA
PNGs with only IHDR, IDAT, and IEND chunks: no display-density, orientation,
animation, or external profile metadata is being exercised.

| Asset | Source size | Purpose | File SHA256 |
| --- | --- | --- | --- |
| `demo-bitmap-caps.png` | 24 by 16 pixels; 184 bytes | Four distinct four-pixel corners, striped edges, and a four-pixel checker center | `ecf285824681960b96d4440e04dbfe5bbef3a847386568976ba81f3435dcd7db` |
| `demo-bitmap-tile.png` | 7 by 5 pixels; 101 bytes | Small alternating tiles with a teal corner and gold opposite marker | `a896c8dd1f3759f9632e08c5106a780deba95973a2f7fdeabd9a4d091741a8d2` |

The live Gallery's Bitmap images card and three 128 by 128 offscreen gallery
entries share `DemoBitmapResizingSample`. Each gallery entry adds 16 points of
padding around the same 96 by 96 sample:

| Entry | Authored behavior |
| --- | --- |
| `bitmap-cap-insets` | Stretch the 24 by 16 source into the square with four-point caps. |
| `bitmap-tile` | Repeat the 7 by 5 source in the square, cropping the incomplete last column and row. |
| `bitmap-aspect-fit` | Fit the capped, tiled 24 by 16 source into the finite square: a 96 by 64 image centered at sample y = 16, with four-point caps. Its center repeats 5.5 times horizontally and 7 times vertically. |

The aspect-fit example depends on the finite-proposal bitmap layout join.
At `138d49b`, all eight `DemoBitmapResourceTests` cases passed within a fresh
64-method focused run. The three retained CPU gallery renders were inspected:
the stretch keeps its colored caps, the tile crops partial repeats, and the
fit has equal 16-point bands around a 96-by-64 image. Native macOS rendering,
live presentation and a joined Full run remain separate requirements. The
three entries increase the catalog from 144 to 147 (104 base, 16 interaction,
27 light); the reviewed 85-entry baseline set and its thresholds are unchanged.

## Resource staging

There is not yet an end-to-end demo packager or installer in this repository.
Adding resources does not change that limitation. A distribution must keep
the **whole generated demo bundle**, including its generated basename and
internal layout, at the location used by the just-built product's generated
`resource_bundle_accessor.swift`. Inspect that accessor after the build;
do not assume the executable name determines the bundle name or that copying
a library DLL also copies its resources.

After the build owner has identified that bundle and created a staging
directory, the resource-only helper copies it without invoking Swift:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/copy-demo-resources.ps1 `
    -BundlePath $reviewedDemoBundle -DestinationDirectory $stagingDirectory
```

The two variables must be explicit reviewed paths. The helper preserves the
supplied bundle's basename, all files, nested metadata, and empty directories;
it checks source and copied file sizes and SHA256 values. It refuses missing
or ambiguous fixture files, reparse points, destinations inside the source,
and an already existing destination bundle. An interrupted/failed copy leaves
its partial directory for inspection; the helper does not overwrite, merge,
delete, or retry it. These are cooperative local filesystem checks, not an
atomic snapshot or protection against concurrent hostile path replacement.
Resolve any build-output junction to its real path before supplying it.

`scripts/test-copy-demo-resources.ps1` exercises this helper against owned
synthetic directories, not a real SwiftPM output. `DemoBitmapResourceTests`
also authors a copy-and-load check using an explicitly supplied `Bundle`.
Neither check qualifies the generated accessor in a relocated executable.

The actual generated Windows bundle was also copied at `138d49b` using this
helper. Its basename was `swift-windowsui_SwiftWindowsDemo.resources`; both
files (285 bytes total) matched the source and copied SHA256 values. The
generated accessor was inspected: it prefers the main bundle location and
then falls back to the original build directory. The retained render and
resource-copy receipts are linked from `goal.md`. This verifies this build's
resource staging, not a relocated executable or an absent-build-tree case.

The release smoke must run the staged executable from an unrelated working
directory on a machine without the build tree, record that the resolved demo
bundle URL is inside the package, and confirm the named images load. Repeat
with a package that lacks the bundle and require a qualification failure;
an accessor's fallback to the original build directory must not hide missing
resources. Unique extensionless image names keep the fixture distinct from
ordinary files, but the Windows loader still checks an existing filesystem
path before an explicit bundle, so record the working directory as well.
Executable, Swift runtime DLL, signing/installer, and native macOS deployment
validation remain separate release requirements.
