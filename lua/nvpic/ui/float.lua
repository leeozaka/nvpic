local config = require('nvpic.config')

local M = {}

local float_win
local float_buf
local target_buf
local target_win
local target_row

local function close_float()
  if float_win and vim.api.nvim_win_is_valid(float_win) then
    pcall(vim.api.nvim_win_close, float_win, true)
  end
  float_win = nil
  float_buf = nil
end

function M.open()
  local clipboard = require('nvpic.clipboard')
  if not clipboard.has_image() then
    vim.notify('nvpic: no image in clipboard', vim.log.levels.INFO)
    return
  end

  local cache = require('nvpic.cache')
  local marker = require('nvpic.marker')
  local renderer = require('nvpic.renderer')

  target_buf = vim.api.nvim_get_current_buf()
  target_win = vim.api.nvim_get_current_win()
  target_row = vim.api.nvim_win_get_cursor(target_win)[1]

  float_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value('buftype', 'nofile', { buf = float_buf })
  local default_scale = config.get().default_scale
  vim.api.nvim_buf_set_lines(float_buf, 0, -1, false, {
    'Scale: ' .. tostring(default_scale),
    'Alt:   ',
    '',
    'Enter: paste · q / Esc: cancel',
  })

  local width = 36
  local height = 6
  local row = math.max(0, math.floor(((vim.o.lines - vim.o.cmdheight) - height) / 2))
  local col = math.max(0, math.floor((vim.o.columns - width) / 2))

  float_win = vim.api.nvim_open_win(float_buf, true, {
    relative = 'editor',
    row = row,
    col = col,
    width = width,
    height = height,
    style = 'minimal',
    border = 'single',
    title = ' nvpic paste ',
    title_pos = 'center',
  })

  local function on_cancel()
    close_float()
    if vim.api.nvim_win_is_valid(target_win) then
      vim.api.nvim_set_current_win(target_win)
    end
  end

  local function on_confirm()
    local fb = float_buf
    if not fb or not vim.api.nvim_buf_is_valid(fb) then
      return
    end
    local lines = vim.api.nvim_buf_get_lines(fb, 0, 2, false)
    local scale_str = (lines[1] or ''):match('Scale:%s*(.*)$') or ''
    local scale = tonumber(vim.trim(scale_str)) or config.get().default_scale
    local alt = vim.trim((lines[2] or ''):match('Alt:%s*(.*)$') or '')
    close_float()

    if vim.api.nvim_win_is_valid(target_win) then
      vim.api.nvim_set_current_win(target_win)
    end

    local data, err = clipboard.read_image()
    if not data then
      vim.notify(err or 'nvpic: failed to read clipboard', vim.log.levels.WARN)
      return
    end

    local rel = cache.store(data, 'clipboard')
    local cs = config.commentstring(target_buf)
    local pic = { path = rel, scale = scale, alt = alt }
    local marker_lines = marker.build(pic, cs)
    local row0 = target_row - 1
    vim.api.nvim_buf_set_lines(target_buf, row0, row0, false, marker_lines)

    local block = {
      start_line = row0,
      end_line = row0 + #marker_lines - 1,
      path = rel,
      scale = scale,
      alt = alt,
    }
    renderer.render_block(target_buf, block)
  end

  vim.keymap.set('n', '<CR>', on_confirm, { buffer = float_buf })
  vim.keymap.set('n', 'q', on_cancel, { buffer = float_buf })
  vim.keymap.set('n', '<Esc>', on_cancel, { buffer = float_buf })
end

return M
