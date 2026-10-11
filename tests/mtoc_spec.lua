-- Run: nvim --headless -u NONE -l tests/mtoc_spec.lua

local repo_root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
vim.opt.runtimepath:prepend(repo_root)
vim.cmd.runtime('plugin/mtoc.lua')
local mtoc = require('mtoc')
local config = require('mtoc.config')

local failures = {}
local function check(name, ok)
  if not ok then
    table.insert(failures, name)
  end
  print((ok and 'ok   ' or 'FAIL ') .. name)
end

local function buffer_lines()
  return vim.api.nvim_buf_get_lines(0, 0, -1, false)
end

local function scratch(lines, cursor)
  vim.cmd('enew!')
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  vim.api.nvim_win_set_cursor(0, { cursor, 0 })
end

local function events()
  local found = {}
  for _, autocmd in ipairs(vim.api.nvim_get_autocmds({ group = 'mtoc' })) do
    table.insert(found, autocmd.event)
  end
  return found
end

local document = { '# Title', '', '## One', 'text', '### Sub', '#### Deep', '## Two' }

local function fenced(items)
  local lines = { '<!-- mtoc-start -->', '' }
  vim.list_extend(lines, items)
  vim.list_extend(lines, { '', '<!-- mtoc-end -->' })
  return lines
end

local function with_toc(items)
  local lines = { '# Title', '' }
  vim.list_extend(lines, fenced(items))
  vim.list_extend(lines, vim.list_slice(document, 3))
  return lines
end

check(':Mtoc exists without setup()', vim.fn.exists(':Mtoc') == 2)
check('the auto-update autocmd exists without setup()', vim.deep_equal(events(), { 'BufWritePre' }))

local default_toc = { '* [One](#one)', '  * [Sub](#sub)', '    * [Deep](#deep)', '* [Two](#two)' }

scratch(document, 2)
vim.cmd('Mtoc insert')
check('insert writes a fenced ToC of the headings below the cursor', vim.deep_equal(buffer_lines(), with_toc(default_toc)))

vim.api.nvim_buf_set_lines(0, -1, -1, false, { '## Three' })
vim.cmd('Mtoc update')
check('update regenerates the ToC in place', vim.tbl_contains(buffer_lines(), '* [Three](#three)'))

vim.cmd('Mtoc remove')
local removed = vim.list_extend(vim.deepcopy(document), { '## Three' })
check('remove deletes the ToC and its fences', vim.deep_equal(buffer_lines(), removed))

local saved = vim.fn.tempname() .. '.md'
vim.cmd.edit(saved)
vim.api.nvim_buf_set_lines(0, 0, -1, false, document)
vim.api.nvim_win_set_cursor(0, { 2, 0 })
vim.cmd('Mtoc insert')
vim.api.nvim_buf_set_lines(0, -1, -1, false, { '## Later' })
vim.cmd('silent write')
check('saving a markdown file updates its ToC without setup()', vim.tbl_contains(buffer_lines(), '* [Later](#later)'))
vim.cmd('bwipeout!')
vim.fn.delete(saved)

mtoc.setup({ headings = { exclude = { '^Sub$' } } })
scratch(document, 2)
vim.cmd('Mtoc insert')
local excluded = { '* [One](#one)', '  * [Deep](#deep)', '* [Two](#two)' }
check('headings.exclude drops a match, which leaves no level for the clamp', vim.deep_equal(buffer_lines(), with_toc(excluded)))

mtoc.setup({
  headings = {
    exclude = function(heading)
      return heading == 'Deep'
    end,
  },
})
scratch(document, 2)
vim.cmd('Mtoc insert')
local by_function = { '* [One](#one)', '  * [Sub](#sub)', '* [Two](#two)' }
check('headings.exclude takes a function', vim.deep_equal(buffer_lines(), with_toc(by_function)))

mtoc.setup({ toc_list = { markers = { '*', '+', '-' }, cycle_markers = true } })
scratch(document, 2)
vim.cmd('Mtoc insert')
local cycled = { '* [One](#one)', '  + [Sub](#sub)', '    - [Deep](#deep)', '* [Two](#two)' }
check('cycle_markers picks each marker by level', vim.deep_equal(buffer_lines(), with_toc(cycled)))

mtoc.setup({ toc_list = { markers = '-' } })
mtoc.update_config({ toc_list = { indent_size = 4 } })
scratch(document, 2)
vim.cmd('Mtoc insert')
check('update_config merges onto the current options', vim.tbl_contains(buffer_lines(), '    - [Sub](#sub)'))

local defaults = vim.deepcopy(config.defaults)
mtoc.setup({ fences = true, auto_update = true })
config.opts.fences.start_text = 'changed'
table.insert(config.opts.headings.exclude, 'changed')
table.insert(config.opts.auto_update.events, 'changed')
check('setup() leaves defaults unwritten', vim.deep_equal(config.defaults, defaults))

mtoc.setup({ auto_update = { events = { 'BufWritePost' } } })
check('setup() re-registers the autocmd on its events', vim.deep_equal(events(), { 'BufWritePost' }))
mtoc.setup({ auto_update = false })
check('auto_update = false leaves no autocmd', #events() == 0)

local slash_copies = {}
for name in pairs(package.loaded) do
  if name:match('^mtoc/') then
    table.insert(slash_copies, name)
  end
end
check('every module is loaded once, by its dotted name', #slash_copies == 0)

if #failures > 0 then
  print('FAILED: ' .. table.concat(failures, ', '))
  vim.cmd('cquit')
end
print('all mtoc tests passed')
vim.cmd('qall!')
