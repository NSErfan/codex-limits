# Provider icons

The menu bar and menu header identify the selected provider using monochrome
product icons from [LobeHub Icons](https://github.com/lobehub/lobe-icons), pinned
to revision `82e641b4fece9d1028a127149af9ded00df5ac0c`:

- [Codex SVG](https://github.com/lobehub/lobe-icons/blob/82e641b4fece9d1028a127149af9ded00df5ac0c/packages/static-svg/icons/codex.svg): terminal mark in a filled rosette.
- [Claude Code SVG](https://github.com/lobehub/lobe-icons/blob/82e641b4fece9d1028a127149af9ded00df5ac0c/packages/static-svg/icons/claudecode.svg): pixel mascot.

These are community-maintained product marks. Codex belongs to OpenAI; Claude Code
belongs to Anthropic. The icons identify the services whose usage is displayed;
they do not imply affiliation or endorsement.

The original, unmodified SVGs are in `Resources/ProviderIcons`. The corresponding
vector PDFs in `Sources/CodexLimits/Resources` avoid macOS CoreSVG misreading the
compact arc syntax in the original Codex path. The conversion preserves the
24-by-24 viewbox, monochrome fill, and transparent interior details. `NSImage`
template rendering lets macOS choose the menu-bar foreground color.

The default menu-bar style is **Icon only**. **Settings → Appearance → Menu bar**
also offers **Text only** and **Icon and text**. Every style shows the usage
percentage alongside the provider icon, name, or both. The menu header continues
to show its icon and name.

Light and dark synthetic previews of all three modes at menu-bar size:

![Codex menu-bar label](images/menu-bar-codex.png)

![Claude Code menu-bar label](images/menu-bar-claude.png)

The icon library's [MIT license](https://github.com/lobehub/lobe-icons/blob/82e641b4fece9d1028a127149af9ded00df5ac0c/LICENSE)
is included in the source and installed resource bundle as `LobeIcons-LICENSE.txt`.

## Native menu-bar rendering

The status label uses one title containing the percentage and optional provider
name. Its template image includes seven transparent trailing points. On macOS
27.0.1, the native status control ignores SwiftUI padding and uses only the first
text view; standalone SwiftUI previews therefore cannot validate these behaviors.
The image margin adds to the system's own spacing (two points on that version).

Run `Scripts/check-menu-bar-labels.sh` on a Mac with an active desktop to inspect
the actual `MenuBarExtra` status buttons for both providers in every display mode.
The check uses synthetic usage and saves native button captures alongside its
title and image-size assertions.

## Regenerating the PDFs

With librsvg's `rsvg-convert` available, run from the repository root:

```sh
for provider in codex claude; do
  SOURCE_DATE_EPOCH=0 rsvg-convert --format=pdf --width=24 --height=24 \
    --dpi-x=72 --dpi-y=72 "Resources/ProviderIcons/ProviderIcon-$provider.svg" \
    --output "Sources/CodexLimits/Resources/ProviderIcon-$provider.pdf"
done
```

The PDFs are committed; normal app builds do not require librsvg or network access.
