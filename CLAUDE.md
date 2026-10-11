# markdown-toc.nvim

A Neovim plugin that generates and updates a linked table of contents in a
markdown buffer. The Lua module is `mtoc` and the command is `:Mtoc`. This repo
is a fork of hedyhli/markdown-toc.nvim and carries upstream's main in full. The
README installs from this fork. `.github/FUNDING.yml` credits the upstream
author.

## `:Mtoc` and the auto-update autocmd exist once the plugin loads

`plugin/mtoc.lua` creates `:Mtoc` and registers the autocmd from the current
options, so the plugin works with no `setup()` call. `setup()` and
`update_config()` only change options. Each re-registers the autocmd, because
`enabled`, `events` and `pattern` decide what it listens on. `:Mtoc toggle`
flips `auto_update.enabled` and re-registers it the same way. `enabled` gates
only the autocmd, so `insert`, `update` and `remove` work with it off. Registration
clears the `mtoc` augroup first, so there is at most one autocmd. With
`auto_update.enabled` false the group stays empty.

`setup()` merges onto the defaults. `update_config()` merges onto the current
options, and it is what a project-local `.nvim.lua` calls. A plugin manager
sources `plugin/` before it calls `setup()`. A `setup()` made before the plugin
loads leaves its options in place for `plugin/mtoc.lua` to register from.

- `plugin/mtoc.lua` creates the command and registers the autocmd.
- `init.lua` parses the command and performs insert, update and remove.
- `toc.lua` finds the fences, scans the headings and builds the slugs.
- `config.lua` holds the defaults and the merge.
- `utils.lua` holds the buffer line helpers.
- `types/mtoc.lua` holds LuaLS annotations and is never required.

## Every module is required by its dotted name

The modules require each other as `require('mtoc.config')`, the spelling the
README's examples use. Lua caches a module under the exact string passed to
`require`. So `require('mtoc/config')` would load a second copy, whose `opts`
are the defaults rather than the user's settings. The spec fails when any
`mtoc/` name reaches `package.loaded`.

## Options take one shape after every merge

`resolve_shortcut_opts` runs after `setup()` and after `update_config()`. It
turns a boolean `fences` or `auto_update` into its table form. It turns a string
`markers`, `events` or `exclude` into a one-item list. An option with a
shortcut form is normalized there.

`defaults` is never written. `setup()` merges onto a deep copy of it, and a
boolean shortcut expands to a deep copy of its table. `vim.tbl_deep_extend`
returns a new top-level table but keeps references to every subtable it did
not merge. So a write through `opts` without the copy lands in `defaults`, and
the next `setup()` starts from it.

A new option needs its default in `config.lua` and a field in both
`mtoc.Config` and `mtoc.UserConfig`. It also needs an entry in the README's
Full Configuration block, which is also the vimdoc.

## Headings are collected in one pass, in document order

ToC order is declaration order, so `gen_toc_list` builds no tree. The scan
starts below the cursor line, or below the old ToC's position on update. A
title above the ToC is therefore left out of it, unless `headings.before_toc`
is set. An entry's depth is the number of headings above it still open at a
lower level, kept as a stack of levels. So two h3s with no h2 above them are
siblings at the top, and an h4 directly under an h2 sits one level in. Each
entry's marker is picked from `toc_list.markers` by that depth, which is what
`cycle_markers` cycles.

A heading `headings.exclude` matches, or one outside `headings.min_level` and
`headings.max_level`, is dropped after its slug is built. It still counts
toward the duplicate suffixes, as it does in GitHub's anchors. It opens no level
for later headings to nest under. Setext headings are not recognized.

Links inside a heading are reduced to their text before the name and the slug
are built. A wiki link, `[[Note]]` or `[[Note|alias]]`, is reduced to its alias
where it has one. Case folding and character stripping go through `vim.fn.tolower` and
Vim's regex. Lua's string library works on bytes and mangles non-ASCII headings.
A new text transform belongs on `vim.fn` for the same reason. A repeated slug
takes a `-1`, `-2` suffix, as GitHub's anchors do.

`toc_list.link_formatter` names one of `toc.link_formatters`. `gfm` follows
GitHub, which drops punctuation and turns each space into a dash. `forgejo`
follows Forgejo's `CleanValue`, which keeps letters, digits and underscores and
turns each run of anything else into one dash, so `1.29.0` becomes `1-29-0`.
Both treat the same Unicode ranges as letters. A name with no formatter raises
an error listing the ones there are.

## Fences and code blocks are matched as plain text

A fence is the configured text wrapped in `<!-- -->`, found by plain substring
search. Equal start and end texts take their own scan in `_find_fences_same`,
because one line would otherwise match both. A code block opens on a line
starting with three backticks, and lines inside one are skipped. That check is
repeated in `_find_fences`, `_find_fences_same` and `gen_toc_list`. A change to
what counts as a code block lands in each. `~~~` fences and indented code are
not recognized, so a `#` line inside one reads as a heading.

## Insertion goes below the line it is given

`utils.delete_lines(s, e)` takes 1-based inclusive line numbers.
`utils.insert_lines(n, lines)` and `gen_toc_list(n)` both act below line `n`.
So a ToC at lines `s` to `e` is regenerated below `s - 1`. `headings.before_toc`
moves where the scan starts to the top of the buffer, never where the ToC goes.

## An update writes only a ToC that differs

`replace_toc` renders the new ToC from the buffer's lines with the old ToC cut
out, then compares it with the old one. An equal ToC is never written, so a
save with the ToC current leaves `changedtick` and the undo tree alone. Every
update and every range `:Mtoc` goes through it. Only `insert` and `remove`
write unconditionally.

The save-time update passes `join`, which runs `undojoin` before it writes. So
the ToC change lands in the undo block of the edit that caused it, and one `u`
takes back both. Neovim refuses `undojoin` straight after an undo with E790.
The `pcall` around it lets that change take its own undo entry instead. A
manual `:Mtoc update` never joins, so it is its own undo step.

## A subcommand abbreviation runs the first prefix match

`M.run` matches the typed word as a prefix against `M.commands`, in order, and
runs the first hit. Nothing detects ambiguity. A new subcommand
sharing a leading letter with an existing one changes what the short form runs.
`M.commands` is also the completion list. `:Mtoc debug` is handled before the
match and is not in that list. It inserts the bare generated list below the
cursor, without fences or the post-processor.

## The README is the source of the vimdoc

The panvimdoc workflow converts `README.md` into `doc/mtoc.txt` on every push.
When the output differs from the committed file, the workflow commits it back
to the pushed branch as "Auto generate vim doc". It sets panvimdoc's `nodate`,
so the title carries no date and an unchanged README commits nothing. Its
`version` names the oldest Neovim the plugin runs on, which is the release that
added the newest API the code calls. A call to a newer API raises it. Edit the
README, never `doc/mtoc.txt`. After such a run the local branch is one commit
behind origin. Sections between `<!-- panvimdoc-ignore-start -->` and
`<!-- panvimdoc-ignore-end -->` stay out of the vimdoc. Those are the title, the
ToC and the TODO list.

## The README's own ToC is generated with `-` markers

The README carries its own ToC between `<!-- mtoc-start -->` and
`<!-- mtoc-end -->`. Saving the README with the plugin at its defaults rewrites
that ToC with `*` markers. The markdownlint hook's `--fix` then rewrites them to
`-`, to match the README's other lists. With `toc_list.markers = "-"`, the
regenerated ToC matches the committed one byte for byte.

## The commit hook runs a headless spec, and the README is a second fixture

`tests/mtoc_spec.lua` loads the plugin in a headless Neovim with no user
config. The commit hook runs it whenever a Lua file changes. CI runs a fixed
list of lint hooks that excludes it. It checks:

- `:Mtoc` and the autocmd exist with no `setup()`, and saving a markdown file
  updates its ToC;
- insert, update and remove of a fenced ToC;
- an update of a current ToC changing nothing, a save-time change undone with
  its edit, and a save straight after an undo;
- nesting by the headings still open above an entry, including skipped levels;
- the `gfm` and `forgejo` slugs, and wiki links reduced to their text or alias;
- `headings.min_level` and `max_level`, and `headings.before_toc` on insert and
  update;
- `headings.exclude` as patterns and as a function, and `cycle_markers`;
- `update_config()` merging onto the current options;
- `setup()` leaving `defaults` unwritten, and re-registering the autocmd;
- `:Mtoc toggle` removing and restoring the autocmd, with `insert` still
  working while it is off;
- every module loaded once, by its dotted name.

```sh
nvim --headless -u NONE -l tests/mtoc_spec.lua
```

The README's own ToC is the second fixture. `--clean` keeps a user config, and
any installed copy of the plugin, out of the run:

```sh
copy=$(mktemp --suffix=.md) && cp README.md "$copy"
nvim --clean --headless --cmd 'set rtp^=.' \
  -c 'lua require("mtoc").setup({ toc_list = { markers = "-" } })' \
  -c 'Mtoc update' -c 'wq' "$copy"
diff README.md "$copy"
```

An empty diff means the README's ToC regenerates unchanged.

## StyLua takes its indent, width and quotes from `.editorconfig`

There is no `stylua.toml`. StyLua reads `.editorconfig` only when it finds no
`stylua.toml` or `.stylua.toml`. Its own defaults are tabs, 120 columns and
double quotes, where `.editorconfig` gives two spaces, 140 columns and single
quotes. A StyLua config added here has to state all three itself. `toc.lua` uses a
`goto` label, which is Lua 5.2 and LuaJIT syntax. A StyLua built from crates.io
with default features cannot parse it. The release binaries can.
