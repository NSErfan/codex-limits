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

Light and dark synthetic previews at menu-bar size:

![Codex menu-bar label](images/menu-bar-codex.png)

![Claude Code menu-bar label](images/menu-bar-claude.png)

The icon library's [MIT license](https://github.com/lobehub/lobe-icons/blob/82e641b4fece9d1028a127149af9ded00df5ac0c/LICENSE)
is included in the source and installed resource bundle as `LobeIcons-LICENSE.txt`.

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
