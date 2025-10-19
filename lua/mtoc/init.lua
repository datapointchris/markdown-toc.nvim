local toc = require('mtoc/toc')
local config = require('mtoc/config')
local utils = require('mtoc/utils')

local empty_or_nil = utils.empty_or_nil
local falsey = utils.falsey

local M = {}
M.commands = {'insert', 'remove', 'update', 'pick'}

local function fmt_fence_start(fence, label, min_b, max_b)
  if label and label ~= '' then
    local s = '<!-- ' .. fence .. ':' .. label
    if min_b ~= nil then
      s = s .. ':' .. tostring(min_b)
      if max_b ~= nil then
        s = s .. ':' .. tostring(max_b)
      end
    end
    return s .. ' -->'
  end
  return '<!-- ' .. fence .. ' -->'
end
local function fmt_fence_end(fence, label, min_b, max_b)
  if label and label ~= '' then
    local s = '<!-- ' .. fence .. ':' .. label
    if min_b ~= nil then
      s = s .. ':' .. tostring(min_b)
      if max_b ~= nil then
        s = s .. ':' .. tostring(max_b)
      end
    end
    return s .. ' -->'
  end
  return '<!-- ' .. fence .. ' -->'
end

local function get_fences()
  local fences = config.opts.fences
  if type(fences) == 'boolean' and fences then
    fences = config.defaults.fences
  end
  local function as_list(v)
    if type(v) == 'string' then return { v } end
    if type(v) == 'table' then return v end
    return {}
  end
  local start_list = as_list(fences.start_text)
  local end_list = as_list(fences.end_text)
  local start_main = start_list[1] or 'mtoc-start'
  local end_main = end_list[1] or 'mtoc-end'
  return {
    enabled = fences.enabled,
    start_main = start_main,
    end_main = end_main,
    start_list = start_list,
    end_list = end_list,
  }
end

-- Count existing fenced ToCs in buffer (best-effort)
local function count_existing_tocs()
  local fences = get_fences()
  local ok, all = pcall(toc.find_all_fences)
  if ok and all and #all > 0 then return #all end
  -- Fallback scan
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local cnt = 0
  for _, line in ipairs(lines) do
    for _, tag in ipairs(fences.start_list) do
      if line:match('^<!%-%-%s*'..tag:gsub('%-', '%%-')..'%s*:?.-%-%->%s*$') then
        cnt = cnt + 1
        break
      end
    end
  end
  return cnt
end

-- Build a stable short label based on file name and ToC index (1-based)
local function build_stable_label_for_index(idx)
  local fname = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ':t')
  if fname == '' then fname = 'untitled' end
  local base = string.format('%s#%d', fname, idx)
  local ok, dig = pcall(vim.fn.sha256, base)
  if ok and type(dig) == 'string' then
    return string.sub(dig, 1, 7)
  end
  local sum = 0
  for i = 1, #base do sum = (sum * 33 + string.byte(base, i)) % 0xFFFFFFFF end
  return string.format('%07x', sum)
end

local function insert_toc(opts)
  if not opts then
    opts = {}
  end

  -- Determine insertion point (cursor by default) independent of generation scope.
  local insert_at = opts.line or utils.current_line()

  local lines = {}
  local fences = get_fences()
  local use_fence = fences.enabled and not opts.disable_fence
  if opts.force_fence then
    use_fence = true
  end
  -- Optional heading bounds for this insertion (recorded on fences)
  local min_b = opts.min_depth
  local max_b = opts.max_depth

  local hcfg = config.opts.headings
  local label = opts.label
  if opts.force_section or (hcfg.min_depth ~= nil or hcfg.partial_under_cursor) then
    local cur = vim.api.nvim_win_get_cursor(0)[1]
    local s_range, e_range = toc.find_current_section_range(cur)
    do
      local saved_min, saved_max = hcfg.min_depth, hcfg.max_depth
      if min_b ~= nil then hcfg.min_depth = min_b end
      if max_b ~= nil then hcfg.max_depth = max_b end
      lines = toc.gen_toc_list_for_range(s_range, e_range)
      hcfg.min_depth, hcfg.max_depth = saved_min, saved_max
    end
    -- Create and freeze a stable short label derived from fileName#tocIndex
    if not label or label == '' then
      local idx = count_existing_tocs() + 1
      label = build_stable_label_for_index(idx)
    end
  else
    -- Full ToC: optionally include headings before the insertion point in generation
    local gen_start = insert_at
    -- If picker requested full-document, override to parse entire buffer
    if opts.force_all then
      gen_start = 0
    elseif hcfg.before_toc then
      gen_start = 0
    end
    do
      local saved_min, saved_max = hcfg.min_depth, hcfg.max_depth
      if min_b ~= nil then hcfg.min_depth = min_b end
      if max_b ~= nil then hcfg.max_depth = max_b end
      lines = toc.gen_toc_list(gen_start)
      hcfg.min_depth, hcfg.max_depth = saved_min, saved_max
    end
    if not label or label == '' then
      local idx = count_existing_tocs() + 1
      label = build_stable_label_for_index(idx)
    end
  end
  if empty_or_nil(lines) then
    if use_fence then
      lines = {
        fmt_fence_start(fences.start_main, label, min_b, max_b),
        '',
        fmt_fence_end(fences.end_main, label, min_b, max_b),
      }
    else
      vim.notify("No markdown headings", vim.log.levels.ERROR)
      return
    end
  else
    lines = config.opts.toc_list.post_processor(lines)

    if use_fence then
      local pad = config.opts.toc_list.padding_lines
      for _ = 1, pad do
        table.insert(lines, 1, '')
      end
      table.insert(lines, 1, fmt_fence_start(fences.start_main))
      for _ = 1, pad do
        table.insert(lines, '')
      end
      table.insert(lines, fmt_fence_end(fences.end_main))
    end
  end

  utils.insert_lines(insert_at, lines)
end

local function remove_toc(not_found_ok)
  local fences = get_fences()
  local hcfg = config.opts.headings
  local locations
  -- 1) Prefer the fenced block that encloses the cursor, if any
  do
    local ok, all = pcall(toc.find_all_fences)
    if ok and all and #all > 0 then
      local cur0 = utils.current_line() - 1
      for _, item in ipairs(all) do
        local s0 = item.start0 or (item.start and (item.start-1))
        local e0 = item.end0 or item.end_ -- end0 is exclusive if provided
        if s0 and e0 and s0 <= cur0 and cur0 < e0 then
          -- Convert to 1-based inclusive [start, end]
          locations = { start = s0 + 1, end_ = e0, label = item.label }
          break
        end
      end
    end
  end
  -- 2) If none under cursor, try labeled for current section (partial updates)
  if not locations and (hcfg.min_depth ~= nil or hcfg.partial_under_cursor) then
    local label = toc.current_section_slug()
    if label and label ~= '' then
      -- Try all configured start/end tags
      for _, st in ipairs(fences.start_list) do
        for _, en in ipairs(fences.end_list) do
          local loc = toc.find_fences_labeled(st, en, label)
          if loc and (loc.start or loc.end_) then locations = loc; break end
        end
        if locations then break end
      end
    end
  end
  -- 3) Fallback to the first matching pair
  if not locations then
    local fstart, fend = fmt_fence_start(fences.start_main), fmt_fence_end(fences.end_main)
    locations = toc.find_fences(fstart, fend)
  end
  if locations and locations.start then
    local line = vim.api.nvim_buf_get_lines(0, locations.start-1, locations.start, false)[1] or ''
    local tags = vim.deepcopy(fences.start_list)
    local has_default = false
    for _, t in ipairs(tags) do if t == 'mtoc-start' then has_default = true; break end end
    if not has_default then table.insert(tags, 'mtoc-start') end
    for _, tag in ipairs(tags) do
      local after = line:match('^%s*<!%-%-%s*'..tag:gsub('%-', '%%-')..'%s*:(.-)%-%->%s*$')
      if after then
        local first = after:match('^[^:]+')
        if first and first ~= '' then locations.label = first end
        break
      end
    end
  end
  if empty_or_nil(locations) or (falsey(locations.start) and falsey(locations.end_)) then
    if not not_found_ok then
      vim.notify("No fences found!", vim.log.levels.ERROR)
    end
    return
  end
  if locations.start and falsey(locations.end_) then
    vim.notify("No end fence found!", vim.log.levels.ERROR)
    return
  end
  if falsey(locations.start) and locations.end_ then
    vim.notify("No start fence found!", vim.log.levels.ERROR)
    return
  end
  if locations.start > locations.end_ then
    vim.notify("End fence found before start fence!", vim.log.levels.ERROR)
    return
  end

  utils.delete_lines(locations.start, locations.end_)

  return locations
end

local function _debug_show_headings()
  local line = utils.current_line()
  local hcfg = config.opts.headings
  local lines
  if hcfg.min_depth ~= nil or hcfg.partial_under_cursor then
    lines = toc.gen_toc_list_scoped()
  else
    lines = toc.gen_toc_list(line)
  end
  utils.insert_lines(line, lines)
end

local function dbg(msg)
  if config.opts and config.opts.debug then
    vim.notify('[mtoc] '..msg, vim.log.levels.INFO)
  end
end

-- Select fenced ToC as a text object (inner = true excludes the fence lines)
function M._select_toc_textobj(inner)
  local ok, all = pcall(toc.find_all_fences)
  if not ok or not all or #all == 0 then return '' end
  local cur0 = utils.current_line() - 1
  local target
  for _, it in ipairs(all) do
    local s0 = it.start0 or (it.start and (it.start-1))
    local e0 = it.end0 or it.end_
    if s0 and e0 and s0 <= cur0 and cur0 < e0 then target = it; break end
  end
  if not target then return '' end
  local s = (target.start0 or (target.start and (target.start-1)) or 0) + 1
  local e = target.end0 or target.end_ or s
  if inner then
    s = math.min(e, s + 1)
    e = math.max(s, e - 1)
  end
  local buf = vim.api.nvim_get_current_buf()
  local maxcol_s = 1
  local maxcol_e = #((vim.api.nvim_buf_get_lines(buf, e-1, e, false)[1] or '')) + 1
  vim.fn.setpos("'<", {buf, s, maxcol_s, 0})
  vim.fn.setpos("'>", {buf, e, maxcol_e, 0})
  return 'gv'
end

-- Build picker presets dynamically from source buffer context
local function build_picker_presets(src_buf, src_cur_line)
  local presets = {}

  -- Always include a Global preset (full document)
  table.insert(presets, { name = 'Global ToC (all headings)', scope = 'global', min = nil, max = nil })

  -- Compute maximum heading depth available across the entire buffer
  local max_depth_global = 1
  vim.api.nvim_buf_call(src_buf, function()
    local is_inside_code_block = false
    for _, l in ipairs(vim.api.nvim_buf_get_lines(src_buf, 0, -1, false)) do
      if l:find('^```') then
        is_inside_code_block = not is_inside_code_block
      elseif not is_inside_code_block then
        local hpfx = l:match(config.opts.headings.pattern)
        if hpfx and #hpfx <= 6 then
          if #hpfx > max_depth_global then max_depth_global = #hpfx end
        end
      end
    end
  end)

  -- Add incremental global presets starting from H1
  local g_min = 1
  local g_end = math.min(max_depth_global, 6)
  for lvl = g_min, g_end do
    local label = (lvl == g_min) and string.format('Global: H%d only', lvl) or string.format('Global: H%d..H%d', g_min, lvl)
    table.insert(presets, { name = label, scope = 'global', min = g_min, max = lvl })
  end

  -- Determine section base depth for incremental presets using captured cursor
  local base_depth = 1
  local max_depth_found = 1
  local s_range, e_range
  vim.api.nvim_buf_call(src_buf, function()
    s_range, e_range = toc.find_current_section_range(src_cur_line)
    local line = vim.api.nvim_buf_get_lines(src_buf, s_range, s_range+1, false)[1] or ''
    local pfx = line:match(config.opts.headings.pattern)
    if pfx then base_depth = #pfx end
    local is_inside_code_block = false
    for _, l in ipairs(vim.api.nvim_buf_get_lines(src_buf, s_range, e_range, false)) do
      if l:find('^```') then
        is_inside_code_block = not is_inside_code_block
      elseif not is_inside_code_block then
        local hpfx = l:match(config.opts.headings.pattern)
        if hpfx and #hpfx <= 6 then
          if #hpfx > max_depth_found then max_depth_found = #hpfx end
        end
      end
    end
  end)

  -- Section (all headings within section)
  table.insert(presets, { name = 'Section ToC (all headings)', scope = 'section', min = nil, max = nil, base = base_depth })

  -- Section with incremental max levels: offer only levels that actually exist in the section
  local min_lvl = math.min(base_depth + 1, 6)
  local end_lvl = math.min(max_depth_found, 6)
  for lvl = min_lvl, end_lvl do
    local label = (lvl == min_lvl) and string.format('Section: H%d only', lvl) or string.format('Section: H%d..H%d', min_lvl, lvl)
    table.insert(presets, { name = label, scope = 'section', min = min_lvl, max = lvl, base = base_depth })
  end

  return presets
end

-- Generate preview lines for a given preset
local function generate_preview_lines(src_buf, src_cur_line, min_b, max_b, scope)
  local lines = {}
  vim.api.nvim_buf_call(src_buf, function()
    local hcfg = config.opts.headings
    local saved_min, saved_max = hcfg.min_depth, hcfg.max_depth
    if min_b ~= nil then hcfg.min_depth = min_b end
    if max_b ~= nil then hcfg.max_depth = max_b end
    if scope == 'section' then
      local s_range, e_range = toc.find_current_section_range(src_cur_line)
      lines = toc.gen_toc_list_for_range(s_range, e_range)
    else
      lines = toc.gen_toc_list(0)
    end
    hcfg.min_depth, hcfg.max_depth = saved_min, saved_max
  end)
  if lines and #lines > 0 then
    lines = config.opts.toc_list.post_processor(lines)
  else
    lines = { '(empty)' }
  end
  return lines
end

-- Snacks picker implementation
local function pick_insert_snacks()
  local ok, snacks = pcall(require, 'snacks')
  if not ok or not snacks.picker then return false end

  if config.opts.debug then
    vim.notify('Using Snacks.picker', vim.log.levels.INFO)
  end

  local src_buf = vim.api.nvim_get_current_buf()
  local src_cur_line = vim.api.nvim_win_get_cursor(0)[1]
  local presets = build_picker_presets(src_buf, src_cur_line)

  -- Convert presets to items
  local items = {}
  for _, preset in ipairs(presets) do
    local preview_lines = generate_preview_lines(src_buf, src_cur_line, preset.min, preset.max, preset.scope)
    table.insert(items, {
      text = preset.name,
      preset = preset,
      preview = {
        text = table.concat(preview_lines, '\n'),
        ft = 'markdown',
      },
    })
  end

  snacks.picker.pick({
    title = 'Insert ToC (choose heading levels)',
    items = items,
    format = function(item)
      return { { item.text } }
    end,
    preview = snacks.picker.preview.preview,
    actions = {
      confirm = function(picker, item)
        if item and item.preset then
          picker:close()
          insert_toc({
            min_depth = item.preset.min,
            max_depth = item.preset.max,
            force_fence = true,
            force_section = (item.preset.scope == 'section'),
            force_all = (item.preset.scope == 'global'),
          })
        end
      end,
    },
  })

  return true
end

-- Telescope picker implementation
local function pick_insert_telescope()
  local ok, _ = pcall(require, 'telescope')
  if not ok then return false end

  if config.opts.debug then
    vim.notify('Using Telescope', vim.log.levels.INFO)
  end

  local pickers = require('telescope.pickers')
  local finders = require('telescope.finders')
  local conf = require('telescope.config').values
  local actions = require('telescope.actions')
  local action_state = require('telescope.actions.state')
  local previewers = require('telescope.previewers')

  local src_buf = vim.api.nvim_get_current_buf()
  local src_cur_line = vim.api.nvim_win_get_cursor(0)[1]
  local presets = build_picker_presets(src_buf, src_cur_line)

  local function render_preview(bufnr, min_b, max_b, scope)
    local lines = generate_preview_lines(src_buf, src_cur_line, min_b, max_b, scope)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    pcall(vim.api.nvim_buf_set_option, bufnr, 'filetype', 'markdown')
  end

  pickers.new({}, {
    prompt_title = 'Insert ToC (choose heading levels)',
    finder = finders.new_table({
      results = presets,
      entry_maker = function(item)
        return {
          value = item,
          display = item.name,
          ordinal = item.name,
        }
      end,
    }),
    sorter = conf.generic_sorter({}),
    previewer = previewers.new_buffer_previewer({
      define_preview = function(self, entry)
        if not entry or not entry.value then return end
        local v = entry.value
        render_preview(self.state.bufnr, v.min, v.max, v.scope)
      end,
    }),
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        local entry = action_state.get_selected_entry()
        if not entry then return end
        local selection = entry.value
        actions.close(prompt_bufnr)
        insert_toc({
          min_depth = selection.min,
          max_depth = selection.max,
          force_fence = true,
          force_section = (selection.scope == 'section'),
          force_all = (selection.scope == 'global'),
        })
      end)
      return true
    end,
  }):find()

  return true
end

-- Main picker entry point: respects user preference from config
local function pick_insert()
  local preferred = (config.opts.picker and config.opts.picker.preferred) or 'auto'

  if config.opts.debug then
    vim.notify('Picker preference: ' .. preferred, vim.log.levels.INFO)
  end

  if preferred == 'telescope' then
    -- Try Telescope first
    if pick_insert_telescope() then
      return
    end
    -- Fall back to Snacks
    if pick_insert_snacks() then
      return
    end
  elseif preferred == 'snacks' then
    -- Try Snacks first
    if pick_insert_snacks() then
      return
    end
    -- Fall back to Telescope
    if pick_insert_telescope() then
      return
    end
  else
    -- 'auto' or any other value: Try Snacks first (default), then Telescope
    if pick_insert_snacks() then
      return
    end
    if pick_insert_telescope() then
      return
    end
  end

  -- No picker available
  vim.notify('ToC picker requires either Snacks.picker or Telescope to be installed', vim.log.levels.WARN)
end

-- Update all fenced ToCs in the current buffer. Preserves labels for partial ToCs.
local function update_all_tocs()
  local fences = get_fences()
  -- Even if fences are currently disabled in config, still attempt to update
  -- any existing fenced ToCs in the buffer.
  local all = {}
  local ok, tocmod = pcall(require, 'mtoc/toc')
  if ok and tocmod.find_all_fences then
    all = tocmod.find_all_fences()
  end
  if empty_or_nil(all) then
    -- Fallback internal scanner
    local start_list = fences.start_list
    local end_list = fences.end_list
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local in_code = false
    local i = 1
    while i <= #lines do
      local line = lines[i]
      if line:find('^```') then
        in_code = not in_code
      elseif not in_code then
        local label = nil
        local matched_start = false
        for _, st in ipairs(start_list) do
          local start_pat = '^<!%-%-%s*'..st:gsub('%-', '%%-')..'(?::([%w%-%._]+))?%s*%-%->%s*$'
          local s_label = line:match(start_pat)
          if s_label ~= nil or line:match('^<!%-%-%s*'..st:gsub('%-', '%%-')..'%s*%-%->%s*$') then
            label = s_label
            matched_start = st
            break
          end
        end
        if matched_start then
          local j = i + 1
          while j <= #lines do
            local l2 = lines[j]
            if l2:find('^```') then
              in_code = not in_code
            elseif not in_code then
              local matched_end = false
              for _, en in ipairs(end_list) do
                local end_pat = '^<!%-%-%s*'..en:gsub('%-', '%%-')..(label and (':'..label) or '')..'%s*%-%->%s*$'
                if l2:match(end_pat) then matched_end = true; break end
              end
              if matched_end then
                table.insert(all, { start0 = i-1, end0 = j, label = label })
                i = j
                break
              end
            end
            j = j + 1
          end
        end
      end
      i = i + 1
    end
  end
  dbg('auto_update: found '..tostring(#all)..' fenced ToCs')
  -- Pre-compute ordinals in source order for stable relabeling
  do
    local idx_map = {}
    local arr = {}
    for _, it in ipairs(all) do
      table.insert(arr, it)
    end
    table.sort(arr, function(a, b)
      local as = a.start0 or (a.start and (a.start-1)) or 0
      local bs = b.start0 or (b.start and (b.start-1)) or 0
      return as < bs
    end)
    for i, it in ipairs(arr) do
      local key = (it.start0 or (it.start and (it.start-1)) or 0)
      idx_map[key] = i
    end
    for _, it in ipairs(all) do
      local key = (it.start0 or (it.start and (it.start-1)) or 0)
      it._ordinal = idx_map[key]
    end
  end
  if empty_or_nil(all) then return end
  -- Process from bottom to top to keep indices stable while replacing lines
  for i = #all, 1, -1 do
    local item = all[i]
    -- Re-read the start fence line to preserve the exact existing bounds (min/max).
    do
      local s0 = item.start0 or (item.start and (item.start-1)) or 0
      local line = vim.api.nvim_buf_get_lines(0, s0, s0+1, false)[1] or ''
      local fences = get_fences()
      local candidates = vim.deepcopy(fences.start_list)
      local seen_default = false
      for _, t in ipairs(candidates) do if t == 'mtoc-start' then seen_default = true; break end end
      if not seen_default then table.insert(candidates, 'mtoc-start') end
      local found = nil
      local used_tag = nil
      local min_b, max_b
      for _, tag in ipairs(candidates) do
        local after = line:match('^%s*<!%-%-%s*'..tag:gsub('%-', '%%-')..'%s*:(.-)%-%->%s*$')
        if after then
          used_tag = tag
          local i = 1
          for part in after:gmatch('[^:]+') do
            part = part:gsub('^%s+', ''):gsub('%s+$', '')
            if i == 1 then found = part ~= '' and part or nil
            elseif i == 2 then min_b = tonumber(part)
            elseif i == 3 then max_b = tonumber(part) end
            i = i + 1
          end
          break
        end
      end
      dbg(string.format('update_all: start line [%d]: "%s"', s0, line))
      dbg(string.format('update_all: label re-extract found=%s (tag=%s)', tostring(found), tostring(used_tag)))
      -- Preserve any legacy label read above in item.label, but we will compute
      -- the canonical label from file+index below to keep it stable like insert.
      if found and found ~= '' then item.label = found end
      item.min_b = min_b
      item.max_b = max_b
    end
    -- Always regenerate by section range based on fence location, independent of label.
    local toc_lines
    do
      local s0 = item.start0 or (item.start and (item.start-1)) or 0
      local cur_line = s0 + 1 -- 1-based for range finder
      local s_range, e_range = toc.find_current_section_range(cur_line)
      dbg(string.format('auto_update: regenerating by range [%d,%d)', s_range, e_range))
      local saved_min, saved_max = config.opts.headings.min_depth, config.opts.headings.max_depth
      if item.min_b ~= nil then config.opts.headings.min_depth = item.min_b end
      if item.max_b ~= nil then config.opts.headings.max_depth = item.max_b end
      toc_lines = toc.gen_toc_list_for_range(s_range, e_range)
      config.opts.headings.min_depth, config.opts.headings.max_depth = saved_min, saved_max
      if utils.empty_or_nil(toc_lines) then
        dbg('auto_update: range produced empty; falling back to full ToC')
        local saved_min2, saved_max2 = config.opts.headings.min_depth, config.opts.headings.max_depth
        if item.min_b ~= nil then config.opts.headings.min_depth = item.min_b end
        if item.max_b ~= nil then config.opts.headings.max_depth = item.max_b end
        toc_lines = toc.gen_toc_list(0)
        config.opts.headings.min_depth, config.opts.headings.max_depth = saved_min2, saved_max2
      end
    end
    -- Preserve existing label if present; otherwise compute file+index label
    local label_to_use = (item.label and item.label ~= '') and item.label or build_stable_label_for_index(item._ordinal or 1)
    toc_lines = config.opts.toc_list.post_processor(toc_lines)
    local new_block = {}
    table.insert(new_block, fmt_fence_start(fences.start_main, label_to_use, item.min_b, item.max_b))
    if not (toc_lines[1] == '' or #toc_lines == 0) then table.insert(new_block, '') end
    for _, l in ipairs(toc_lines) do table.insert(new_block, l) end
    if new_block[#new_block] ~= '' then table.insert(new_block, '') end
    table.insert(new_block, fmt_fence_end(fences.end_main, label_to_use, item.min_b, item.max_b))
    local s0 = item.start0 or (item.start and (item.start-1)) or 0
    local e0 = item.end0 or item.end_ or s0
    dbg(string.format('auto_update: replacing lines [%d,%d) with %d lines', s0, e0, #new_block))
    vim.api.nvim_buf_set_lines(0, s0, e0, true, new_block)
  end
end

-- Perform an auto-update with state preservation. Exposed for autocmd to call with command modifiers.
function M._auto_update()
  local aup = config.opts.auto_update or {}
  utils.with_preserved_state({
    suppress_pollution = aup.suppress_pollution,
  }, function()
    dbg('auto_update: fired')
    update_all_tocs()
  end)
end

local function handle_command(opts)
  local fnopts = { bang = opts.bang }
  if opts.range == 2 then
    fnopts.range_start = opts.line1
    fnopts.range_end = opts.line2
  end

  if empty_or_nil(opts.fargs) then
    -- Default to update all fenced ToCs if no subcommand is provided
    return update_all_tocs()
  end

  local cmd = opts.fargs[1]
  if cmd == 'debug' then
    return _debug_show_headings()
  end
  if cmd:sub(#cmd, #cmd) == '!' then
    fnopts.bang = true
    cmd = cmd:sub(1, #cmd-1)
  end


  local found = false
  for _, v in ipairs(M.commands) do
    if string.match(v, "^"..cmd) then
      cmd = v
      found = true
      break
    end
  end

  if not found then
    vim.notify("Unknown command "..cmd, vim.log.levels.ERROR)
    return
  end

  if cmd == "insert" then
    return insert_toc(fnopts)
  elseif cmd == "remove" then
    return remove_toc()
  elseif cmd == "update" then
    return update_all_tocs()
  elseif cmd == "pick" then
    return pick_insert()
  else
    vim.notify("INTERNAL ERROR: Unhandled command "..cmd, vim.log.levels.ERROR)
  end
end


local function setup_commands()
  vim.api.nvim_create_user_command("Mtoc", handle_command, {
    nargs = '?',
    range = true,
    bang = true,
    complete = function()
      return M.commands
    end,
  })
end

local function setup_autocmds()
  M.autocmds = {}
  local aup = config.opts.auto_update
  if not aup then
    return
  end
  if type(aup) == 'boolean' then
    aup = config.defaults.auto_update
  end
  if not aup.enabled then
    return
  end
  local id = vim.api.nvim_create_autocmd(aup.events, {
    pattern = aup.pattern,
    callback = function()
      -- Use command modifiers to avoid changing jumplist and last-change mark
      local mods = { silent = true }
      if aup.suppress_pollution then
        mods.keepjumps = true
        mods.lockmarks = true
      end
      vim.api.nvim_cmd({
        cmd = 'lua',
        args = { 'require("mtoc")._auto_update()' },
        mods = mods,
      }, {})
     end,
   })
  table.insert(M.autocmds, id)
end

---Remove autocmds that were set up by this plugin
function M.remove_autocmds()
  if empty_or_nil(M.autocmds) then
    return
  end
  for _, id in ipairs(M.autocmds) do
    vim.api.nvim_del_autocmd(id)
  end
end

---Merge user opts with default opts and set up autocmds and commands
---@param opts mtoc.UserConfig
function M.setup(opts)
  vim.g.mtoc_loaded = 1
  config.merge_opts(opts)
  setup_autocmds()
  setup_commands()
end

---Merge user opts with default opts and reset autocmds based on new options
---@param opts mtoc.UserConfig
function M.update_config(opts)
  config.update_opts(opts)
  M.remove_autocmds()
  setup_autocmds()
end

return M
