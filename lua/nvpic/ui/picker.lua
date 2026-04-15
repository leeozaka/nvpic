local cache = require('nvpic.cache')
local marker = require('nvpic.marker')
local renderer = require('nvpic.renderer')
local config = require('nvpic.config')

local M = {}

---@param entry { filename: string, path: string, meta: table|nil }
---@return string
local function format_label(entry)
  local m = entry.meta
  if m and type(m.width) == 'number' and type(m.height) == 'number' then
    return string.format('%s (%dx%d)', entry.filename, m.width, m.height)
  end
  return entry.filename
end

function M.open()
  local entries = cache.list()
  if #entries == 0 then
    vim.notify('nvpic: no images in ' .. config.get().pics_dir, vim.log.levels.INFO)
    return
  end

  local target_buf = vim.api.nvim_get_current_buf()
  local target_win = vim.api.nvim_get_current_win()
  local target_row = vim.api.nvim_win_get_cursor(target_win)[1]

  local labels = {}
  local label_to_entry = {}
  for _, entry in ipairs(entries) do
    local label = format_label(entry)
    table.insert(labels, label)
    label_to_entry[label] = entry
  end

  vim.ui.select(labels, {
    prompt = 'nvpic pick> ',
    format_item = function(item)
      return item
    end,
  }, function(choice)
    if not choice then
      return
    end

    local selected = label_to_entry[choice]
    if not selected then
      return
    end

    if not vim.api.nvim_buf_is_valid(target_buf) then
      vim.notify('nvpic: target buffer is no longer valid', vim.log.levels.WARN)
      return
    end

    if vim.api.nvim_win_is_valid(target_win) then
      vim.api.nvim_set_current_win(target_win)
    end

    local cs = config.commentstring(target_buf)

    local scale = config.get().default_scale
    local block_lines = marker.build({
      path = selected.path,
      scale = scale,
      alt = '',
    }, cs)

    local row0 = target_row - 1
    vim.api.nvim_buf_set_lines(target_buf, row0, row0, false, block_lines)

    local block = {
      start_line = row0,
      end_line = row0 + #block_lines - 1,
      path = selected.path,
      scale = scale,
      alt = '',
    }
    renderer.render_block(target_buf, block)
  end)
end

return M
