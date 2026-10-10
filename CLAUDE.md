# markdown-toc.nvim

A Neovim plugin that generates and updates a linked table of contents in a
markdown buffer. The Lua module is `mtoc` and the command is `:Mtoc`. This repo
is a fork of hedyhli/markdown-toc.nvim. The README's install instructions and
`.github/FUNDING.yml` point at upstream.

## Nothing runs until `setup()` is called

There is no `plugin/` directory. `require("mtoc").setup()` registers `:Mtoc` and
the auto-update autocmd. Before it runs, neither exists. lazy.nvim calls it when
the spec sets `opts`. `update_config()` merges onto the current options rather
than the defaults, and it is what a project-local `.nvim.lua` calls.
`setup()` and `update_config()` each clear the `mtoc` augroup before
registering the autocmd in it, so there is at most one. With
`auto_update.enabled` false the group stays empty.

- `init.lua` parses the command and performs insert, update and remove.
- `toc.lua` finds the fences, scans the headings and builds the slugs.
- `config.lua` holds the defaults and the merge.
- `utils.lua` holds the buffer line helpers.
- `types/mtoc.lua` holds LuaLS annotations and is never required.

## Every internal require uses the slash spelling

The modules require each other as `require("mtoc/config")`. Lua caches a module
under the exact string passed to `require`. So `require("mtoc.config")` loads a
second copy, whose `opts` are the defaults rather than the user's settings. A
new module requires its siblings with the slash spelling. The README's examples
use the dot spelling, which works only because they read `defaults`.

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
is set. A heading more than one level below the previous one is clamped to one
level below it. The shallowest level found is then indented to zero. Each
entry's marker is picked from `toc_list.markers` by that indented level, which
is what `cycle_markers` cycles.

A heading `headings.exclude` matches is dropped after its slug is built. It
still counts toward the duplicate suffixes, as it does in GitHub's anchors. It
does not count as the previous level for the clamp. Setext headings are not
recognized.

Links inside a heading are reduced to their text before the name and the slug
are built. Case folding and character stripping go through `vim.fn.tolower` and
Vim's regex. Lua's string library works on bytes and mangles non-ASCII headings.
A new text transform belongs on `vim.fn` for the same reason. A repeated slug
takes a `-1`, `-2` suffix, as GitHub's anchors do.

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
So a ToC removed from line `s` is re-inserted at `s - 1`.

## A subcommand abbreviation runs the first prefix match

`handle_command` matches the typed word as a prefix against `M.commands`, in
order, and runs the first hit. Nothing detects ambiguity. A new subcommand
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

## There is no test suite, and the README is the fixture

`--clean` keeps a user config, and any installed copy of the plugin, out of the
run:

```sh
copy=$(mktemp --suffix=.md) && cp README.md "$copy"
nvim --clean --headless --cmd 'set rtp^=.' \
  -c 'lua require("mtoc").setup({ toc_list = { markers = "-" } })' \
  -c 'Mtoc update' -c 'wq' "$copy"
diff README.md "$copy"
```

An empty diff means the README's ToC regenerates unchanged.

## StyLua takes its indent from `.editorconfig`

There is no `stylua.toml`. StyLua reads `.editorconfig` only when it finds no
`stylua.toml` or `.stylua.toml`, and its own default indent is tabs. A StyLua
config added here has to state the two-space indent itself. `toc.lua` uses a
`goto` label, which is Lua 5.2 and LuaJIT syntax. A StyLua built from crates.io
with default features cannot parse it. The release binaries can.
