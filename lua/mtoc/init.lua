local toc = require('mtoc.toc')
local config = require('mtoc.config')
local utils = require('mtoc.utils')

local empty_or_nil = utils.empty_or_nil
local falsey = utils.falsey

local M = {}
M.commands = { 'insert', 'update', 'remove' }

local function fmt_fence_start(fence)
  return '<!-- ' .. fence .. ' -->'
end
local function fmt_fence_end(fence)
  return '<!-- ' .. fence .. ' -->'
end

local function get_fences()
  local fences = config.opts.fences
  if type(fences) == 'boolean' and fences then
    fences = config.defaults.fences
  end
  return fences
end

local function insert_toc(opts)
  if not opts then
    opts = {}
  end

  local insert_at = opts.line or utils.current_line()
  local scan_from = insert_at
  if config.opts.headings.before_toc then
    scan_from = 0
  end

  local lines = {}
  local fences = get_fences()
  local use_fence = fences.enabled and not opts.disable_fence

  lines = toc.gen_toc_list(scan_from)
  if empty_or_nil(lines) then
    if use_fence then
      lines = {
        fmt_fence_start(fences.start_text),
        '',
        fmt_fence_end(fences.end_text),
      }
    else
      vim.notify('No markdown headings', vim.log.levels.ERROR)
      return
    end
  else
    lines = config.opts.toc_list.post_processor(lines)

    if use_fence then
      local pad = config.opts.toc_list.padding_lines
      for _ = 1, pad do
        table.insert(lines, 1, '')
      end
      table.insert(lines, 1, fmt_fence_start(fences.start_text))
      for _ = 1, pad do
        table.insert(lines, '')
      end
      table.insert(lines, fmt_fence_end(fences.end_text))
    end
  end

  utils.insert_lines(insert_at, lines)
end

local function remove_toc(not_found_ok)
  local fences = get_fences()
  local fstart, fend = fmt_fence_start(fences.start_text), fmt_fence_end(fences.end_text)

  local locations = toc.find_fences(fstart, fend)
  if empty_or_nil(locations) or (falsey(locations.start) and falsey(locations.end_)) then
    if not not_found_ok then
      vim.notify('No fences found!', vim.log.levels.ERROR)
    end
    return
  end
  if locations.start and falsey(locations.end_) then
    vim.notify('No end fence found!', vim.log.levels.ERROR)
    return
  end
  if falsey(locations.start) and locations.end_ then
    vim.notify('No start fence found!', vim.log.levels.ERROR)
    return
  end
  if locations.start > locations.end_ then
    vim.notify('End fence found before start fence!', vim.log.levels.ERROR)
    return
  end

  utils.delete_lines(locations.start, locations.end_)

  return locations
end

local function update_toc(opts, fail_ok)
  if opts.range_start and opts.range_end then
    utils.delete_lines(opts.range_start, opts.range_end)
    local use_fence = opts.bang
    return insert_toc({ line = opts.range_start - 1, disable_fence = not use_fence })
  end

  local locations = remove_toc(fail_ok)
  if empty_or_nil(locations) then
    return
  end
  opts.line = locations.start - 1
  return insert_toc(opts)
end

local function update_or_remove_toc(opts)
  if opts.range_start and opts.range_end then
    return update_toc(opts)
  end

  local locations = remove_toc(true)
  opts = opts or {}
  if empty_or_nil(locations) then
    opts.line = nil
    return insert_toc(opts)
  end
  opts.line = locations.start - 1
  return insert_toc(opts)
end

local function _debug_show_headings()
  local line = utils.current_line()
  local lines = toc.gen_toc_list(line)
  utils.insert_lines(line, lines)
end

---Run `:Mtoc` with the arguments Neovim passes a user command's callback
---@param opts table
function M.run(opts)
  local fnopts = { bang = opts.bang }
  if opts.range == 2 then
    fnopts.range_start = opts.line1
    fnopts.range_end = opts.line2
  end

  if empty_or_nil(opts.fargs) then
    return update_or_remove_toc(fnopts)
  end

  local cmd = opts.fargs[1]
  if cmd == 'debug' then
    return _debug_show_headings()
  end
  if cmd:sub(#cmd, #cmd) == '!' then
    fnopts.bang = true
    cmd = cmd:sub(1, #cmd - 1)
  end

  local found = false
  for _, v in ipairs(M.commands) do
    if string.match(v, '^' .. cmd) then
      cmd = v
      found = true
      break
    end
  end

  if not found then
    vim.notify('Unknown command ' .. cmd, vim.log.levels.ERROR)
    return
  end

  if cmd == 'insert' then
    return insert_toc(fnopts)
  elseif cmd == 'update' then
    return update_toc(fnopts, false)
  elseif cmd == 'remove' then
    return remove_toc()
  else
    vim.notify('INTERNAL ERROR: Unhandled command ' .. cmd, vim.log.levels.ERROR)
  end
end

local augroup = 'mtoc'

---Register the auto-update autocmd from the current options, replacing any earlier one
function M.register_autocmds()
  local group = vim.api.nvim_create_augroup(augroup, { clear = true })
  local aup = config.opts.auto_update
  if not aup.enabled then
    return
  end
  vim.api.nvim_create_autocmd(aup.events, {
    group = group,
    pattern = aup.pattern,
    callback = function()
      update_toc({}, true)
    end,
  })
end

---Remove autocmds that were set up by this plugin
function M.remove_autocmds()
  vim.api.nvim_create_augroup(augroup, { clear = true })
end

---Merge user opts with default opts, and re-register the autocmd on them
---@param opts mtoc.UserConfig
function M.setup(opts)
  config.merge_opts(opts)
  M.register_autocmds()
end

---Merge user opts onto the current opts, and re-register the autocmd on them
---@param opts mtoc.UserConfig
function M.update_config(opts)
  config.update_opts(opts)
  M.register_autocmds()
end

return M
