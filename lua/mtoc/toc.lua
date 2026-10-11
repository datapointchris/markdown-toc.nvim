local config = require('mtoc.config')

local M = {}
M.link_formatters = {}

---Link formatter based on GitHub Flavoured Markdown
---@param existing_headings { [string]: number }
---@param heading string
function M.link_formatters.gfm(existing_headings, heading)
  heading = vim.fn.tolower(heading)

  -- Strip leading and trailing underscores
  heading = heading:gsub('^_+', ''):gsub('_+$', '')

  -- Strip non-alphanumric non-latin-extended, and non-CJK characters.
  -- Lua doesn't handle unicode very well.
  heading = vim.fn.substitute(
    heading,
    [[[^[:alnum:]\u00C0-\u00FF\u0400-\u04ff\u4e00-\u9fbf\u3040-\u309F\u30A0-\u30FF\uAC00-\uD7AF _-]] .. ']',
    '',
    'g'
  )

  -- Convert all spaces to dashes
  heading = heading:gsub(' ', '-')

  local key = heading
  local heading_str = heading

  if heading_str == '' then
    key = '<NULL>'
  end

  if existing_headings[key] ~= nil then
    existing_headings[key] = existing_headings[key] + 1
    heading_str = heading_str .. '-' .. existing_headings[key]
  else
    existing_headings[key] = 0
  end

  return heading_str
end

---Link formatter matching Forgejo's heading anchors, which Codeberg serves.
---Letters, digits and underscores are kept, and each run of anything else between them becomes one dash.
---@param existing_headings { [string]: boolean }
---@param heading string
function M.link_formatters.forgejo(existing_headings, heading)
  heading = vim.fn.tolower(heading)
  heading = vim.fn.substitute(heading, [=[[^[:alnum:]À-ÿЀ-ӿ一-龿぀-ゟ゠-ヿ가-힯_]\+]=], '-', 'g')
  heading = vim.fn.substitute(heading, [[^-\+\|-\+$]], '', 'g')
  if heading == '' then
    heading = 'heading'
  end

  local slug = heading
  local suffix = 0
  while existing_headings[slug] do
    suffix = suffix + 1
    slug = heading .. '-' .. suffix
  end
  existing_headings[slug] = true
  return slug
end

---@see find_fences
local function _find_fences(fstart, fend, lines)
  local locations = {}
  local in_code = false
  for i, line in ipairs(lines) do
    if locations.start and locations.end_ then
      break
    end

    if string.find(line, '^```') then
      in_code = not in_code
    else
      if not in_code then
        if string.find(line, fstart, 1, true) then
          locations.start = i
        end
        if string.find(line, fend, 1, true) then
          locations.end_ = i
        end
      end
    end
  end
  return locations
end

---Find fences function for start and end fences being the same string
---@see find_fences
local function _find_fences_same(fence, lines)
  local in_code = false
  local locations = {}
  for i, line in ipairs(lines) do
    if string.find(line, '^```') then
      in_code = not in_code
    else
      if not in_code then
        if string.find(line, fence, 1, true) then
          if locations.start then
            locations.end_ = i
            break
          else
            locations.start = i
          end
        end
      end
    end
  end
  return locations
end

---Return a table containing line numbers of start and end fences
---@param fstart string   String of fence start
---@param fend string     String of fence end
---@return table locations `{ start = start_lineno, end_ = end_lineno }`
function M.find_fences(fstart, fend)
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  if fstart ~= fend then
    return _find_fences(fstart, fend, lines)
  end
  return _find_fences_same(fstart, lines)
end

---Returns a list of strings representing the lines of the ToC list.
---Calls both link formatter and item formatter based on config.
---@param start_from integer|nil The line number before which, headings will be ignored
---@return string[] lines List of lines to be inserted as ToC
function M.gen_toc_list(start_from)
  start_from = start_from or 0
  local toc_config = config.opts.toc_list

  ---@type string|string[]
  local markers = toc_config.markers
  if not toc_config.cycle_markers then
    markers = { markers[1] }
  end

  ---@type fun(heading: string): boolean
  local is_excluded
  local headings_config = config.opts.headings
  local exclude = headings_config.exclude
  if type(exclude) == 'function' then
    is_excluded = exclude
  else
    is_excluded = function(heading)
      for _, pattern in ipairs(exclude) do
        if string.match(heading, pattern) then
          return true
        end
      end
      return false
    end
  end

  local indent_size = toc_config.indent_size
  if type(indent_size) == 'function' then
    indent_size = indent_size()
  end

  local item_formatter = toc_config.item_formatter

  local format_link = M.link_formatters[toc_config.link_formatter]
  if not format_link then
    local names = vim.tbl_keys(M.link_formatters)
    table.sort(names)
    error(('mtoc: toc_list.link_formatter %q is none of: %s'):format(toc_config.link_formatter, table.concat(names, ', ')))
  end

  local is_inside_code_block = false
  local lines = {}
  local all_heading_links = {}
  -- Levels of the headings still open above the next entry, outermost first.
  local open_levels = {}

  for _, line in ipairs(vim.api.nvim_buf_get_lines(0, start_from, -1, false)) do
    if string.find(line, '^```') then
      is_inside_code_block = not is_inside_code_block
    end
    if is_inside_code_block then
      goto nextline
    end

    local prefix, name = string.match(line, config.opts.headings.pattern)
    if not prefix or not name or #prefix > 6 then
      goto nextline
    end

    -- Strip embedded links in TOC: both in name and link.
    name = name:gsub('%[(.-)%]%(.-%)', '%1')

    -- An excluded heading, or one outside the level bounds, still counts toward
    -- duplicate slugs, as it does in GitHub's anchors.
    local link = format_link(all_heading_links, name)
    local level = #prefix
    if is_excluded(name) or level < headings_config.min_level or level > headings_config.max_level then
      goto nextline
    end

    while #open_levels > 0 and open_levels[#open_levels] >= level do
      table.remove(open_levels)
    end
    local depth = #open_levels
    table.insert(open_levels, level)

    local fmt_info = {
      name = name,
      link = link,
      depth = depth,
      raw_line = line,
      indent = (' '):rep(depth * indent_size),
      marker = markers[depth % #markers + 1],
    }
    table.insert(lines, item_formatter(fmt_info, toc_config.item_format_string))
    ::nextline::
  end

  return lines
end

return M
