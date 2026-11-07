local M = {}

---Every option at its default. The README's "Full configuration" section describes each one, and
---the spec fails when that section's values differ from these.
---@type mtoc.Config
M.defaults = {
  headings = {
    before_toc = false,
    exclude = {},
    pattern = '^(#+)%s+(.+)$',
    min_level = 1,
    max_level = 6,
  },

  toc_list = {
    markers = { '*' },
    cycle_markers = false,
    indent_size = 2,
    item_format_string = '${indent}${marker} [${name}](#${link})',
    item_formatter = function(item_info, fmtstr)
      local s = fmtstr:gsub([[${(%w-)}]], function(key)
        return item_info[key] or ('${' .. key .. '}')
      end)
      return s
    end,
    post_processor = function(lines)
      return lines
    end,
    padding_lines = 1,
    link_formatter = 'gfm',
  },

  fences = {
    enabled = true,
    start_text = 'mtoc-start',
    end_text = 'mtoc-end',
  },

  auto_update = {
    enabled = true,
    events = { 'BufWritePre' },
    pattern = '*.{md,mdown,mkd,mkdn,markdown,mdwn}',
  },
}

---@type mtoc.Config
M.opts = vim.deepcopy(M.defaults)

---Should be called after merge_opts (ensure config.opts is non-empty)
function M.resolve_shortcut_opts()
  ---@type any
  local value = M.opts.fences
  if type(value) == 'boolean' then
    M.opts.fences = vim.deepcopy(M.defaults.fences)
    if not value then
      M.opts.fences.enabled = false
    end
  end

  value = M.opts.auto_update
  if type(value) == 'boolean' then
    M.opts.auto_update = vim.deepcopy(M.defaults.auto_update)
    if not value then
      M.opts.auto_update.enabled = false
    end
  end

  if type(M.opts.auto_update.events) == 'string' then
    ---@diagnostic disable-next-line
    M.opts.auto_update.events = { M.opts.auto_update.events }
  end
  if type(M.opts.toc_list.markers) == 'string' then
    ---@diagnostic disable-next-line
    M.opts.toc_list.markers = { M.opts.toc_list.markers }
  end
  if type(M.opts.headings.exclude) == 'string' then
    ---@diagnostic disable-next-line
    M.opts.headings.exclude = { M.opts.headings.exclude }
  end
end

---@param opts mtoc.UserConfig
function M.merge_opts(opts)
  M.opts = vim.tbl_deep_extend('force', vim.deepcopy(M.defaults), opts or {})
  M.resolve_shortcut_opts()
end

---@param opts mtoc.UserConfig
function M.update_opts(opts)
  M.opts = vim.tbl_deep_extend('force', {}, M.opts, opts or {})
  M.resolve_shortcut_opts()
end

return M
