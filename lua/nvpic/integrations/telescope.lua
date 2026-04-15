local cache = require('nvpic.cache')
local marker = require('nvpic.marker')
local renderer = require('nvpic.renderer')
local config = require('nvpic.config')

local M = {}

---@param entry { filename: string, path: string, meta: table|nil }
---@return string
local function format_display(entry)
  local m = entry.meta
  if m and type(m.width) == 'number' and type(m.height) == 'number' then
    return string.format('%s (%dx%d)', entry.filename, m.width, m.height)
  end
  return entry.filename
end

---@param entry { filename: string, path: string, meta: table|nil }
---@return string[]
local function format_preview_lines(entry)
  local meta = entry.meta or {}
  local size_str
  if type(meta.width) == 'number' and type(meta.height) == 'number' then
    size_str = string.format('%dx%d', meta.width, meta.height)
  else
    size_str = '(unknown)'
  end
  local source = meta.source ~= nil and tostring(meta.source) or '-'
  local created = meta.created ~= nil and tostring(meta.created) or '-'
  return {
    'File:    ' .. entry.filename,
    'Path:    ' .. entry.path,
    'Size:    ' .. size_str,
    'Source:  ' .. source,
    'Created: ' .. created,
  }
end

---@param opts? table
function M.pick(opts)
  opts = opts or {}

  local ok = pcall(require, 'telescope')
  if not ok then
    vim.notify('nvpic: telescope.nvim is not installed', vim.log.levels.WARN)
    return
  end

  local entries = cache.list()
  if #entries == 0 then
    vim.notify('nvpic: no images in ' .. config.get().pics_dir, vim.log.levels.INFO)
    return
  end

  local target_buf = vim.api.nvim_get_current_buf()
  local target_win = vim.api.nvim_get_current_win()
  local target_row = vim.api.nvim_win_get_cursor(target_win)[1]

  local pickers = require('telescope.pickers')
  local finders = require('telescope.finders')
  local conf = require('telescope.config').values
  local previewers = require('telescope.previewers')
  local actions = require('telescope.actions')
  local action_state = require('telescope.actions.state')

  pickers.new(opts, {
    prompt_title = 'nvpic',
    finder = finders.new_table({
      results = entries,
      entry_maker = function(entry)
        return {
          value = entry,
          display = format_display(entry),
          ordinal = entry.filename .. ' ' .. entry.path,
        }
      end,
    }),
    sorter = conf.generic_sorter(opts),
    previewer = previewers.new_buffer_previewer({
      title = 'nvpic',
      define_preview = function(self, e, _)
        local lines = format_preview_lines(e.value)
        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
      end,
    }),
    attach_mappings = function(prompt_bufnr, _)
      actions.select_default:replace(function()
        local selection = action_state.get_selected_entry()
        actions.close(prompt_bufnr)
        if not selection or not selection.value then
          return
        end
        local selected = selection.value
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
        renderer.render_block(target_buf, {
          start_line = row0,
          end_line = row0 + #block_lines - 1,
          path = selected.path,
          scale = scale,
          alt = '',
        })
      end)
      return true
    end,
  }):find()
end

function M.setup()
  return require('telescope').register_extension({
    exports = {
      pick = M.pick,
    },
  })
end

return M
