# Configuration

| option | default | |
|---|---|---|
| `current_operator` | required | `->(controller) { operator }` |
| `authenticate` | required | `->(controller) { }`, redirect or render to stop |
| `authorize` | denies | `->(operator, permission, context) { true/false }` |
| `sign_out_path` | nil | `-> { path }` evaluated in the view |
| `sign_out_method` | `:get` | `:get` renders a link; `:delete` (and others) render a button that submits that method, as Devise needs |
| `current_actor` | `current_operator` | actor recorded outside the panel |
| `tenancy` | `:none` | `:none`, `:lucid_tenancy` or an adapter |
| `classification_path` | nil | YAML of categories |
| `categories` | `public contact documents minors financial free_text unclassified` | must include `public` and `unclassified` |
| `hidden_tables` | `[]` | never listed |
| `secret_columns` | `/password\|token\|secret\|digest\|otp\|encrypted/i` | never shown, even revealed |
| `page_size` | 25 | |
| `reveal_duration` | 15 minutes | |
| `reveal_reason_min` | 10 | characters |
| `activity_retention` | 6 months | |
| `activity_purge_batch` | 1000 | |
| `title`, `layout`, `terms` | | appearance |
| `brand_color` | nil (lime `#c6ff00`) | `#rgb` or `#rrggbb`; text over it is chosen for contrast |
| `theme` | `{}` | token overrides, see [customization](customization.md) |
| `stylesheet` | `:default` | `:default`, a path/URL (or list) that replaces the gem's CSS, or `nil` for none |
| `extra_stylesheets` | `[]` | loaded after the default (or replacement) CSS |

A missing required option or a bad classification raises `Lucid::Backoffice::Error::ConfigurationConflict` at boot, naming the key.

Permissions asked of `authorize`: `:view_dashboard`, `:view_tenant`, `:browse`, `:reveal`, `:view_activity` and those declared by plugins. The gem defines no roles.
