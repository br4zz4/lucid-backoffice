# Customization

From least to most: nothing declared; a Resource; partials per resource; overriding `app/views/lucid/backoffice/ui/*` in your app; your own screens. The look has its own layers, below. `config.layout` replaces the layout.

The default layout is made of partials you can override in your app: `lucid/backoffice/shared/_sidebar`, `shared/_context`, `shared/_topbar` (breadcrumb, reveal eye and Sign out), `ui/_page_header` (breadcrumb, title and Actions), `ui/_reveal_eye`, `ui/_empty` and `ui/_pager`. A screen of your own sets its breadcrumb with `content_for :lb_crumbs` or by rendering `ui/_page_header` with `crumbs:`.

## Look

The default is black with a lime accent (inspired by brazza.tech), using system font stacks and no external requests.

1. **Accent**: `config.brand_color = "#ff0066"` (`#rgb`/`#rrggbb`). The text over it switches between black and white for contrast.
2. **Tokens**: `config.theme = { bg: "#0b0b0f", radius: "6px" }`. Tokens: `bg surface raised border text muted accent on_accent ok warn danger font_sans font_mono radius`, each the CSS variable `--lb-<token>` (underscores become dashes). Values are plain CSS (no `url(`, `;`, `{}`, `<>`), checked at boot.
3. **Extra CSS**: `config.extra_stylesheets = ["/backoffice.css"]`, loaded last, to adjust anything with the `lb-*` classes.
4. **Replace the CSS**: `config.stylesheet = ["/my-backoffice.css"]` serves only yours (`nil` serves none). The tokens are still emitted, so your CSS may use `var(--lb-accent)`.
5. **Replace the layout**: `config.layout = "backoffice"`. Render `lucid/backoffice/shared/head` inside `<head>` to keep the assets, or write your own tags.

Stylesheet references are paths starting with `/` or `http(s)` URLs; anything else raises `ConfigurationConflict`.
