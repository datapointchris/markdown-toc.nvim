<!-- panvimdoc-ignore-start -->

# markdown-toc.nvim
<!-- panvimdoc-ignore-end -->


Generate and update table of contents list (with links) for markdown.

Almost fully replaces vim-markdown-toc, written in 100% lua.

- Supports setext style headings (`======` and `------`), and Github-style headings (only when the parser is set to `treesitter`)
- Supports GitHub Flavoured Markdown links by default. If you want to use
  another link format a better configuration structure for this is
  [planned](#todo), but for now you can set your own [formatter
  function](#advanced-examples).

<!-- panvimdoc-ignore-start -->

**Table of contents**

Dog-fooding ;)

<!-- mtoc-start -->

* [Install](#install)
* [Setup](#setup)
  * [Common configuration options](#common-configuration-options)
  * [Fences](#fences)
    * [Recording heading-level bounds in fences](#recording-heading-level-bounds-in-fences)
    * [Multiple fence tags](#multiple-fence-tags)
  * [Text Objects](#text-objects)
  * [Examples](#examples)
* [Full Configuration](#full-configuration)
  * [Advanced Examples](#advanced-examples)
  * [Project-local configuration](#project-local-configuration)
* [TODO](#todo)

<!-- mtoc-end -->
<!-- panvimdoc-ignore-end -->

## Install

Example for Lazy.nvim:

- Using GitHub repo: `hedyhli/markdown-toc.nvim`
- Using sourcehut repo: `url = "https://git.sr.ht/~hedy/markdown-toc.nvim"`

```lua
{
  "hedyhli/markdown-toc.nvim",
  ft = "markdown",  -- Lazy load on markdown filetype
  cmd = { "Mtoc" }, -- Or, lazy load on "Mtoc" command
  dependencies = {
    "nvim-treesitter/nvim-treesitter", -- optional, for efficient parsing
    "nvim-telescope/telescope.nvim",   -- optional, for picker UI
  },
  build = ":TSInstall markdown", -- if you want the markdown TreeSitter parser
  opts = {
    -- Your configuration here (optional)
  },
},
```

Making use of lazy-loading with `ft` means that `Mtoc` commands won't be
available until a markdown file is opened.

Note that the repo is called `markdown-toc.nvim`, but the lua module and
commands are prefixed with `mtoc` rather than `markdown-toc`.

To be explicit or if you run into problems, you can set `main = "mtoc"` in the
plugin spec for Lazy.nvim.

The dependencies are optional but offer interesting features:
- [Neovim's Tree-Sitter](https://github.com/nvim-treesitter/nvim-treesitter)
  abstraction layer is used to efficiently parse Markdown files and find headings.
  It supports CommonMark and Github flavoured markdown with a few extensions.
- [Telescope]() as a UI helpder for picker/preview tasks

## Setup

```lua
require('mtoc').setup({})
```

A call to the setup function is not required for the plugin to work. Default
configuration will be used.

However, the setup call is **required** if you want to enable the auto-update
feature (because autocmds have to be set up).


### Common configuration options

Pass this table with your config options to the setup function, or put this
table in the `opts` key if you're using Lazy.nvim.

```lua
{
  headings = {
    -- Include heading before the ToC into the ToC
    before_toc = false,
    -- Parser to use for heading detection: 'auto' | 'treesitter' | 'regex'
    parser = 'auto',
    -- Generate a partial ToC for the section under the cursor
    partial_under_cursor = false,
    -- Start including headings from this depth (1=H1). Allows partial ToCs.
    min_depth = nil,
    -- Stop including headings up to this depth (inclusive)
    max_depth = nil,
    -- Either list of lua patterns to exclude, or a function(title)->boolean
    exclude = {},
    -- Pattern to detect headings for the regex parser
    -- 1st capture = hashes (###), 2nd capture = title
    pattern = "^(#+)%s+(.+)$",
  },

  -- Table or boolean. Set to true to use these defaults, set to false to disable completely.
  -- Fences are needed for the update/remove commands; otherwise you must update manually
  fences = {
    enabled = true,
    -- These texts are wrapped within "<!-- % -->", and often affixed with a label
    -- identifying the ToC if it's a partial one
    -- Both options can be a list of strings supporting older tags
    -- Then, the first one is considered the main active tag
    start_text = "mtoc-start",
    -- or, to support an old one too set:
    -- start_text = {"mtoc-start", "old-mtoc-start"}
    end_text   = "mtoc-end",
  },

  -- Auto-update of the ToC on save (only if fences found).
  -- You can set auto_update=true (shortcut) or customize the table below.
  auto_update = {
    enabled = true,
    events = { "BufWritePre" },
    -- Use a list of patterns; brace expansion is not supported by nvim autocmds.
    pattern = { "*.md", "*.mdown", "*.mkd", "*.mkdn", "*.markdown", "*.mdwn" },
    -- When true, updates run with keepjumps/lockmarks to avoid polluting nvim state
    suppress_pollution = true,
  },

  toc_list = {
    -- string or list of strings (for cycling)
    -- If cycle_markers=false and markers is a list, only the first is used.
    -- You can set to '1.' to use an automatically numbered list for ToC (if supported).
    markers = { '*' },
    cycle_markers = false,
    numbered = false,
    -- Integer or function returning integer (e.g. from shiftwidth)
    indent_size = 2,
    -- Format string for each item (fields: name, link, marker, indent, depth)
    item_format_string = "${indent}${marker} [${name}](#${link})",
    -- Formatter for a single item. Defaults to simple template replacement.
    item_formatter = function(item, fmtstr)
      local s = fmtstr:gsub([[${(%w-)}]], function(key)
        return item[key] or ('${'..key..'}')
      end)
      return s
    end,
    -- Post-process the array of lines before insertion
    post_processor = function(lines) return lines end,
  },
}
```

### Fences

Fences are used to detect existing ToCs for auto-updates and text-object manipulation.

#### Recording heading-level bounds in fences

Fences can optionally include the heading-level bounds used to generate that ToC. This makes future updates honor the same levels automatically.

Format:

```
<!-- mtoc-start:<label>[:<min>[:<max>]] -->
...
<!-- mtoc-end:<label>[:<min>[:<max>]] -->
```

- `label` is a short, stable label used to associate the fence with the section (auto-derived for partial ToCs if not provided).
- `min`/`max` are optional integers indicating the minimum and maximum heading levels included (H1=1..H6=6). When present, updates will regenerate the ToC with these bounds.

Notes:
- `:Mtoc pick` always inserts fenced ToCs and records the selected bounds.
- Updates preserve the label and any `min`/`max` metadata even if you later change headings.

#### Multiple fence tags

You can configure more than one fence tag for compatibility with other tools and/or previous configuration. The first tag is used as a "main avtive tag" when writing; all tags are supported when detecting/updating ToCs.

Example:

```lua
require('mtoc').setup({
  fences = {
    enabled = true,
    start_text = { 'mtoc-start', 'toc-start' },
    end_text   = { 'mtoc-end',   'toc-end'   },
  },
})
```

- Writes will use `mtoc-start`/`mtoc-end` (first entries).
- Updates/removes will recognize any of `mtoc-start|toc-start` and `mtoc-end|toc-end`.

### Text Objects

To make operating on a ToC more convenient, add these expr-mappings to your Neovim configuration:

```lua
-- Outer ToC (includes fences)
vim.keymap.set({'x','o'}, 'aT',
    function() return require('mtoc')._select_toc_textobj(false) end,
    { expr = true, desc = 'ToC text object' })

-- Inner ToC (excludes fences)
vim.keymap.set({'x','o'}, 'iT',
    function() return require('mtoc')._select_toc_textobj(true) end,
    { expr = true, desc = 'ToC text object' })
```

The preferred option to remove a single ToC if text objects are set up is:
`daT` keystrokes from normal mode.

`:Mtoc remove` can also do this, and will remove the first matched ToC if there is no enclosing one.


### Examples

Most subcommands do not have to be typed in full so long as they are not ambiguous.
These shortcuts are shown in `[square brackets]` below.

- `:Mtoc`

  Update all fenced ToCs in the current buffer. If no fenced ToCs are present,
  this is a no-op. Use `:Mtoc insert` to insert a ToC.

- `:Mtoc i[nsert]`

  Insert ToC at cursor position.

  If there are no headings found and fences are enabled, fences are inserted without any content inside

- `:Mtoc u[pdate]`

  Update all fenced ToCs in the current buffer (same as `:Mtoc`).

- `:Mtoc r[emove]`

  Removes the ToC fenced block that encloses the cursor.
  If no fenced block encloses the cursor, it falls back to removing the first
  matching pair of fences.

  It may print errors when no fences are found, start-end fences are not
  matched, or end found before start.

- `:Mtoc p[ick]`

  Opens a Telescope picker to preview and insert a ToC with chosen heading-level bounds.

  Presets:
  - Global ToC (all headings): full-document ToC honoring `headings.before_toc` option.
  - Global incremental presets derived from the file:
    - Global: H1 only
    - Global: H1..Hn (up to the deepest heading present, capped at H6)
  - Section ToC (all headings): ToC scoped to the section containing the cursor.
  - Section ToC with incremental max levels: offers a small set of options starting from
    the level right under the section heading up to the deepest level actually present
    in that section.

  Behavior:
  - Preview mirrors exactly what will be inserted at the current cursor position (partial vs full).
  - Insertion always wraps the ToC in fences and records any selected `min`/`max` bounds in the fences.
  - If Telescope is not available, this command is a no-op.

- `Mtoc debug`
  Inserts a debug listing of detected headings at cursor position using current configuration,
  equivalent of non-fenced ToC

## Full Configuration

```lua
{
  headings = {
    before_toc = false,
    parser = 'auto',
    partial_under_cursor = false,
    min_depth = nil,
    max_depth = nil,
    exclude = {},
    pattern = "^(#+)%s+(.+)$",
  },

  toc_list = {
    numbered = false,
    markers = { '*' },
    cycle_markers = false,
    indent_size = 2,
    item_format_string = "${indent}${marker} [${name}](#${link})",
    item_formatter = function(item, fmtstr)
      local s = fmtstr:gsub([[${(%w-)}]], function(key)
        return item[key] or ('${'..key..'}')
      end)
      return s
    end,

    -- Called after an array of lines for the ToC is computed. This does not
    -- include the fences even if it's enabled.
    post_processor = function(lines) return lines end,

    -- Add padding (blank lines) before and after the TOC
    padding_lines = 1,
  },

  fences = {
    enabled = true,
    start_text = "mtoc-start", -- or a list of strings, first one is the main tag
    end_text   = "mtoc-end", -- or a list of strings, first one is the main tag
  },

  auto_update = {
    enabled = true,
    events = { "BufWritePre" },
    pattern = { "*.md", "*.mdown", "*.mkd", "*.mkdn", "*.markdown", "*.mdwn" },
    suppress_pollution = true,
  },
}
```

### Advanced Examples

Custom link formatter:
```lua
toc_list = {
  item_formatter = function(item, fmtstr)
    local default_formatter = require('mtoc.config').defaults.toc_list.item_formatter
    item.link = item.name:gsub(" ", "_")
    return default_formatter(item, fmtstr)
  end,
},
```
In the above example a link for a heading is generated simply by converting all
spaces to underscores.

You can also wrap the existing formatter like so:
```lua
toc_list = {
  item_formatter = function(item, fmtstr)
    local default_formatter = require('mtoc.config').defaults.toc_list.item_formatter
    item.link = item.link..'-custom-link-ending'
    return default_formatter(item, fmtstr)
  end,
},
```

Exclude headings named "CHANGELOG" or "License":
```lua
headings = {
  exclude = {"CHANGELOG", "License"},
},
```

Exclude headings that begin with "TODO":
```lua
headings = {
  exclude = "^TODO",
},
```

Exclude all capitalized headings:
```lua
headings = {
  exclude = function(title)
    -- Return true means, to exclude it from the ToC
    return title:upper() == title
  end,
},
```

Set indent size for ToC list based on shiftwidth opt:
```lua
toc_list = {
  indent_size = function()
    return vim.bo.shiftwidth
  end,
},
```

Flattened ToC list without links:
```lua
toc_list = {
  item_format_string = "${marker} ${name}",
},
```
This produces something like this:
```md
* Heading 1
* Sub heading
* Sub sub heading
* Heading 2
```

Ensure all heading names are in Title Case when listed in ToC:
```lua
toc_list = {
  item_formatter = function(item, fmtstr)
    local default_formatter = require('mtoc.config').defaults.toc_list.item_formatter
    -- NOTE: Consider using `vim.fn.tolower/toupper` to support letters other than ASCII.
    item.name = item.name:gsub("(%a)([%w_']*)", function(a,b) return a:upper()..b:lower() end)
    return default_formatter(item, fmtstr)
  end,
},
```
Remove `:lower()` to avoid decapitalizing already capitalized rest of words
(like the case for acronyms).

Include only 2nd-level headings
```lua
headings = {
  pattern = "^(##)%s+(.+)$",
}
```

### Project-local configuration

From nvim-0.9, secure loading of per-directory nvim configs are now supported.

You can include this in your neovim config:

```lua
if vim.fn.has("nvim-0.9") == 1 then
  vim.o.exrc = true
end
```

Then in your project root, create a file named `.nvim.lua`, with the following contents:
```lua
local ok, mtoc = pcall(require, 'mtoc')
if ok then
  mtoc.update_config({
    -- new opts to override
    headings = { parser = 'regex', partial_under_cursor = true, min_depth = 3 },
  })
end
```

Here's an example `.nvim.lua` in the wild that makes use of
`mtoc.update_config`: <https://github.com/hedyhli/outline.nvim/blob/main/.nvim.lua>


<!-- panvimdoc-ignore-start -->
## TODO

- Types
- More tests
- Lua API surface for programmatic usage
- Multiple link style chooser

<!-- panvimdoc-ignore-end -->
