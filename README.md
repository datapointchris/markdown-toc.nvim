<!-- panvimdoc-ignore-start -->

# markdown-toc.nvim

<!-- panvimdoc-ignore-end -->

A Neovim plugin that writes a linked table of contents into a markdown buffer.
Each save rewrites the ToC when it has fallen behind the headings. The repo is
`markdown-toc.nvim`, but the Lua module is `mtoc` and the command is `:Mtoc`.

It is a Lua alternative to the Vimscript plugin vim-markdown-toc. It reads `#`
headings only, so a setext heading underlined with `===` or `---` never reaches
the ToC.

This is a maintained fork of
[hedyhli/markdown-toc.nvim](https://github.com/hedyhli/markdown-toc.nvim). It
fixes nesting, option merging, heading exclusion and marker cycling. It adds
Forgejo-style links, bounds on the heading levels listed, wiki links listed by
their alias, an update on save that leaves a current ToC unwritten,
`:Mtoc toggle`, and loading with no `setup()` call.

<!-- panvimdoc-ignore-start -->

**Table of contents**

<!-- mtoc-start -->

- [Install](#install)
- [Starting from scratch](#starting-from-scratch)
- [`:Mtoc` updates the ToC there is, or inserts one](#mtoc-updates-the-toc-there-is-or-inserts-one)
- [The ToC lists only the headings below it](#the-toc-lists-only-the-headings-below-it)
- [Links match the anchors GitHub or Forgejo gives a heading](#links-match-the-anchors-github-or-forgejo-gives-a-heading)
- [Each entry is a format string filled in per heading](#each-entry-is-a-format-string-filled-in-per-heading)
- [Fences are how a ToC is found again](#fences-are-how-a-toc-is-found-again)
- [The update on save writes only a ToC that changed, in the edit's undo step](#the-update-on-save-writes-only-a-toc-that-changed-in-the-edits-undo-step)
- [`setup()` starts from the defaults, `update_config()` from what is set](#setup-starts-from-the-defaults-update_config-from-what-is-set)
- [Full configuration — every option, at its default](#full-configuration--every-option-at-its-default)

<!-- mtoc-end -->
<!-- panvimdoc-ignore-end -->

## Install

With lazy.nvim:

```lua
{
  'datapointchris/markdown-toc.nvim',
  ft = 'markdown', -- load on the first markdown buffer
  cmd = { 'Mtoc' }, -- or on the first :Mtoc, whichever comes first
  opts = {}, -- lazy.nvim calls setup() with this table
}
```

With no plugin manager, Neovim loads any clone under
`stdpath('data')/site/pack/*/start/` at startup. On Linux and macOS that is:

```sh
git clone https://github.com/datapointchris/markdown-toc.nvim \
  ~/.local/share/nvim/site/pack/plugins/start/markdown-toc.nvim
```

The plugin needs no `setup()` call. `:Mtoc` and the update on save exist as
soon as Neovim loads it, on the defaults under
[Full configuration](#full-configuration--every-option-at-its-default). So a
lazy.nvim spec that loads only on `cmd` has no update on save until the first
`:Mtoc`.

lazy.nvim finds the `mtoc` module on its own. `main = 'mtoc'` in the spec names
it outright.

## Starting from scratch

Open a markdown file with a title on line 1 and a few `##` headings below it:

```vim
:1             " the ToC goes below the cursor line, so start on the title
:Mtoc          " no ToC yet, so this inserts one between two fence comments
:write         " rename a heading first: the save rewrites its ToC entry
:autocmd mtoc  " the update on save, checked first when a save changes nothing
```

`:Mtoc` leaves the buffer like this:

```md
# Notes
<!-- mtoc-start -->

* [Setup](#setup)
  * [Linux](#linux)
* [Usage](#usage)

<!-- mtoc-end -->

## Setup
```

The title is left out because it sits above the ToC.
`headings.before_toc = true` lists it too.

The fences are how `:Mtoc update`, `:Mtoc remove` and the update on save find
the ToC. The update on save rewrites only a ToC between fences. It never creates
one. It passes over a file with neither fence without a message.

`:autocmd mtoc` prints the update on save under the `mtoc` group. The error
`E216: No such group or event: mtoc` means the plugin never loaded. A bare
`--- Autocommands ---` with nothing under it means `auto_update` is off.

## `:Mtoc` updates the ToC there is, or inserts one

```vim
:Mtoc          " update the fenced ToC, or insert one below the cursor
:Mtoc insert   " insert a ToC below the cursor, fenced unless fences are off
:Mtoc update   " rewrite the fenced ToC, or report why there is none to rewrite
:Mtoc remove   " delete the fenced ToC, fences included
:Mtoc toggle   " turn the update on save off, or back on
:'<,'>Mtoc     " replace the selected lines with a ToC, unfenced
:'<,'>Mtoc!    " the same, fenced
```

A subcommand runs from any prefix of its name, so `:Mtoc u` is `:Mtoc update`.
Each subcommand starts with a different letter, so one letter is enough.

A range works with `update` too, so `:'<,'>Mtoc u!` is `:'<,'>Mtoc!`. The range
form needs no fences. It is how a ToC written with fences off gets updated.

An update leaves a ToC that is already current untouched. The buffer stays
unmodified, and no undo entry is made.

`:Mtoc insert` with no headings below the cursor inserts empty fences. With
fences off it prints `No markdown headings` instead.

`:Mtoc update` and `:Mtoc remove` act only between a start fence and an end
fence below it. Otherwise each prints one of these:

- `No fences found!`
- `No start fence found!`
- `No end fence found!`
- `End fence found before start fence!`

## The ToC lists only the headings below it

The scan starts below the line the ToC goes under. For an insert that is the
cursor line. For an update it is the line above the old ToC.
`headings.before_toc = true` starts the scan at the top of the buffer. It moves
where the scan starts, never where the ToC goes.

An entry's depth is the number of headings above it still open at a shallower
level. So two `###` headings with no `##` above them are siblings at the top. A
`####` directly under a `##` sits one level in, not two.

`headings.min_level` and `headings.max_level` bound the levels listed, from 1
for `#` to 6 for `######`. This lists only the `##` and `###` headings, leaving
the title and anything deeper out of a long document's ToC:

```lua
headings = {
  min_level = 2,
  max_level = 3,
},
```

`headings.exclude` leaves out the headings it matches. It takes Lua patterns,
as a list or one string, matched anywhere in the heading text. So a pattern
needs `^` and `$` to match one whole heading:

```lua
headings = {
  exclude = { '^CHANGELOG$', '^License$' }, -- these two headings exactly
},
```

```lua
headings = {
  exclude = '^TODO', -- every heading starting with TODO
},
```

It also takes a function. The function gets the heading text and returns true
to leave the heading out. This one leaves out every heading written in
capitals:

```lua
headings = {
  exclude = function(title)
    return title:upper() == title
  end,
},
```

A heading left out opens no level, so the headings after it nest as though it
were not there. It still counts toward the `-1` suffixes on repeated links, as
it does on GitHub.

A heading is a line `headings.pattern` matches, `^(#+)%s+(.+)$` by default. The
first capture's length is the level, and the second capture is the text. A run
of more than six `#` is not a heading.

A line starting with three backticks opens or closes a code block. The headings
inside one are skipped. A `~~~` fence or an indented block is not recognized as
code, so a `#` line inside one is listed as a heading.

A link inside a heading is listed as its text. A wiki link, `[[Note]]` or
`[[Note|alias]]`, is listed as its alias where it has one.

## Links match the anchors GitHub or Forgejo gives a heading

`toc_list.link_formatter` picks how each heading's anchor is spelled. `'gfm'`,
the default, follows GitHub. It drops punctuation and turns each space into a
dash. `'forgejo'` follows Forgejo and Codeberg. It keeps letters, digits and
underscores, and turns each run of anything else into one dash. So a heading
`Version 1.2.0` links to `#version-120` under `'gfm'`, and to `#version-1-2-0`
under `'forgejo'`:

```lua
toc_list = {
  link_formatter = 'forgejo',
},
```

A `link_formatter` that names no formatter raises an error listing the ones
there are. A repeated heading takes a `-1`, `-2` suffix, as on GitHub.

Any other spelling goes through `toc_list.item_formatter`, which can rewrite an
entry's link before the entry is formatted. This one turns every space in the
heading text into an underscore:

```lua
toc_list = {
  item_formatter = function(item, fmtstr)
    local default_formatter = require('mtoc.config').defaults.toc_list.item_formatter
    item.link = item.name:gsub(' ', '_')
    return default_formatter(item, fmtstr)
  end,
},
```

## Each entry is a format string filled in per heading

`toc_list.item_format_string` is the shape of one entry. Its default is
`${indent}${marker} [${name}](#${link})`. Each `${field}` is replaced with that
field of the heading.

`toc_list.markers` is the marker, `'*'` by default. A list of markers with
`cycle_markers = true` gives each depth the next marker in turn:

```lua
toc_list = {
  markers = { '*', '+', '-' },
  cycle_markers = true,
},
```

```md
* [First heading](#first-heading)
  + [Sub heading](#sub-heading)
    - [Sub-sub heading](#sub-sub-heading)
      * [Sub-sub-sub heading](#sub-sub-sub-heading)
* [Second heading](#second-heading)
```

With `cycle_markers` off, only the first marker in a list is used. `'1.'` makes
a numbered list wherever the renderer numbers one:

```lua
toc_list = {
  markers = '1.',
},
```

`toc_list.indent_size` is the spaces per depth, 2 by default. A function in its
place is called on every regeneration, so it can read a buffer-local option:

```lua
toc_list = {
  indent_size = function()
    return vim.bo.shiftwidth
  end,
},
```

Leaving `${indent}` and the link out gives a flat list of names:

```lua
toc_list = {
  item_format_string = '${marker} ${name}',
},
```

```md
* Heading 1
* Sub heading
* Sub sub heading
* Heading 2
```

`toc_list.item_formatter` turns one entry into its line. It gets a table of the
entry's fields, then the format string. The fields are these:

- `name`, the heading text with its links reduced to their text
- `link`, the anchor the link formatter spelled
- `marker` and `indent`, both picked by depth
- `depth`, 0 at the top level
- `raw_line`, the heading line as written

Wrapping the default formatter keeps the `${field}` substitution. This one
lists every heading in Title Case:

```lua
toc_list = {
  item_formatter = function(item, fmtstr)
    local default_formatter = require('mtoc.config').defaults.toc_list.item_formatter
    -- Lua's string library works on bytes, so this changes ASCII letters only.
    -- vim.fn.toupper and vim.fn.tolower handle the rest.
    item.name = item.name:gsub("(%a)([%w_']*)", function(a, b) return a:upper() .. b:lower() end)
    return default_formatter(item, fmtstr)
  end,
},
```

Dropping `:lower()` leaves the rest of each word as written, which keeps an
acronym in capitals.

`toc_list.post_processor` gets the finished lines, without the fences, and
returns the lines to write. `toc_list.padding_lines` is the number of blank
lines between the list and each fence, 1 by default.

## Fences are how a ToC is found again

A fence is an HTML comment around the fence text, `<!-- mtoc-start -->` and
`<!-- mtoc-end -->` by default. `fences.start_text` and `fences.end_text` set
the text. `:Mtoc update`, `:Mtoc remove` and the update on save find the ToC by
the first lines containing those comments, outside code blocks.

A ToC written under one fence text is invisible under another. After the fence
text changes, select the old ToC with its fences and run `:'<,'>Mtoc!`. That
rewrites it between the current fences. Editing the old fences by hand works
too. `:Mtoc remove` searches for the current text, so removing and inserting
again works only before the text changes.

`fences = false` writes a ToC with no fences. Nothing then marks where that ToC
is, so update, remove and the update on save cannot find it. Selecting it and
running `:'<,'>Mtoc` regenerates it.

## The update on save writes only a ToC that changed, in the edit's undo step

`auto_update` runs the update on every `BufWritePre` for a file matching
`*.{md,mdown,mkd,mkdn,markdown,mdwn}`. `auto_update.events` and
`auto_update.pattern` replace those, and reach `nvim_create_autocmd` as given.

A ToC that is already current is not written. Such a save leaves the undo tree
and `changedtick` alone.

A ToC change it makes joins the undo step of the edit before it. One `u` then
takes back both. Straight after an undo, Neovim refuses that join with E790,
and the change takes an undo step of its own. A `:Mtoc update` typed by hand is
always its own undo step.

`:Mtoc toggle` flips `auto_update.enabled`, which turns the update on save off
or back on. The other subcommands work either way. `auto_update = false` starts
with it off.

## `setup()` starts from the defaults, `update_config()` from what is set

`setup()` and `update_config()` only change options. Each re-registers the
update on save, because `auto_update` decides what it listens for.

```lua
require('mtoc').setup({
  toc_list = { markers = '-' },
})
```

`setup()` merges its table onto the defaults. A second `setup()` call starts
over, dropping what the first one set. `update_config()` merges onto the
current options, so it adds to what `setup()` set.

A boolean `fences` or `auto_update` stands for the default table, turned on or
off. A string `markers`, `exclude` or `events` stands for a list of one.

`update_config()` is what a project-local config calls. Neovim 0.9 and later
load a `.nvim.lua` from the working directory when `exrc` is set, after asking
you to trust the file:

```lua
if vim.fn.has('nvim-0.9') == 1 then
  vim.o.exrc = true
end
```

A `.nvim.lua` in the project root then layers its options on top:

```lua
local ok, mtoc = pcall(require, 'mtoc')
if ok then
  mtoc.update_config({
    -- options for this project
  })
end
```

outline.nvim keeps
[one](https://github.com/hedyhli/outline.nvim/blob/main/.nvim.lua) that sets
`headings.pattern` to `^(##)%s+(.+)$`, so its README's ToC lists only the `##`
headings.

## Full configuration — every option, at its default

Pass any part of this table to `setup()` or `update_config()`, or set it as
lazy.nvim's `opts`.

```lua
{
  headings = {
    -- List the headings above the ToC too, by scanning from the top of the
    -- buffer.
    before_toc = false,
    -- Lua patterns, as a list or one string, matched anywhere in a heading's
    -- text. Or a function that takes the text and returns true to leave the
    -- heading out.
    exclude = {},
    -- The first capture is the heading level ('###') and the second is the
    -- heading text.
    pattern = '^(#+)%s+(.+)$',
    -- The shallowest and deepest heading levels listed, 1 for '#' to 6 for '######'.
    min_level = 1,
    max_level = 6,
  },

  toc_list = {
    -- A string, or a list of strings to cycle through by depth.
    -- With cycle_markers = false, only the first in a list is used.
    -- '1.' gives a numbered list where the renderer numbers one.
    markers = '*',
    cycle_markers = false,

    -- An integer, or a function returning one. A function is called every time
    -- the ToC is regenerated, so it can read a buffer-local option like
    -- shiftwidth.
    indent_size = 2,

    -- Remove ${indent}, or set indent_size = 0, for a flat list.
    item_format_string = '${indent}${marker} [${name}](#${link})',

    -- Turns one entry into its line. item_info has the fields name, link,
    -- marker, indent, depth and raw_line. Changing item_format_string changes
    -- the format and keeps the ${field} substitution.
    item_formatter = function(item_info, fmtstr)
      local s = fmtstr:gsub([[${(%w-)}]], function(key)
        return item_info[key] or ('${' .. key .. '}')
      end)
      return s
    end,

    -- Gets the ToC's lines, without the fences, and returns the lines to write.
    post_processor = function(lines)
      return lines
    end,

    -- Blank lines between the list and each fence.
    padding_lines = 1,

    -- How each heading's anchor is spelled. 'gfm' matches GitHub, which drops
    -- punctuation. 'forgejo' matches Forgejo and Codeberg, which turn each run
    -- of punctuation and spaces into one dash.
    link_formatter = 'gfm',
  },

  -- A table, true for these defaults, or false to write ToCs with no fences.
  -- Update, remove and the update on save find a ToC by its fences.
  fences = {
    enabled = true,
    -- Each text is wrapped as '<!-- text -->'.
    start_text = 'mtoc-start',
    end_text = 'mtoc-end',
  },

  -- A table, true for these defaults, or false for no update on save.
  auto_update = {
    enabled = true,
    -- The update runs on these events for files matching pattern. It never
    -- creates a ToC. A change it makes joins the undo step of the edit before
    -- it, so one `u` takes back both.
    -- events is a string or a list. Both fields reach nvim_create_autocmd as
    -- given.
    events = { 'BufWritePre' },
    pattern = '*.{md,mdown,mkd,mkdn,markdown,mdwn}',
  },
}
```
