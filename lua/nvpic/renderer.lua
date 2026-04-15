local marker = require('nvpic.marker')
local cache = require('nvpic.cache')
local protocol = require('nvpic.protocol')
local treesitter = require('nvpic.treesitter')
local config = require('nvpic.config')

local M = {}

local ns = vim.api.nvim_create_namespace('nvpic')

---@class Placement
---@field extmark_id number
---@field hidden_extmark_ids number[]
---@field placement_id string
---@field block PicBlock

---@type table<number, Placement[]>
local buf_placements = {}

---@type table<number, boolean>
local buf_active = {}

---@type table<number, userdata>
local debounce_timers = {}

---@param bufnr number
local function stop_debounce(bufnr)
  local t = debounce_timers[bufnr]
  if not t then
    return
  end
  debounce_timers[bufnr] = nil
  t:stop()
  if not t:is_closing() then
    t:close()
  end
end

---@param bufnr number
---@param diag vim.Diagnostic
local function append_diagnostic(bufnr, diag)
  local cur = vim.diagnostic.get(bufnr, { namespace = ns })
  local combined = {}
  for _, d in ipairs(cur) do
    table.insert(combined, {
      lnum = d.lnum,
      col = d.col or 0,
      end_lnum = d.end_lnum,
      end_col = d.end_col,
      severity = d.severity,
      message = d.message,
      source = d.source,
    })
  end
  table.insert(combined, diag)
  vim.diagnostic.set(ns, bufnr, combined)
end

---@param rows number
---@return table[]
function M.make_spacer_lines(rows)
  local lines = {}
  for _ = 1, rows do
    table.insert(lines, { { '', 'Normal' } })
  end
  return lines
end

---@param bufnr number
---@return Placement[]
function M.get_placements(bufnr)
  return buf_placements[bufnr] or {}
end

---@param bufnr number
---@return boolean
function M.is_active(bufnr)
  return buf_active[bufnr] or false
end

---@param bufnr number
---@param block PicBlock
---@param winid? number
---@return { row: number, col: number, available_cols: number, available_rows: number }|nil
local function get_window_geometry(bufnr, block, winid)
  winid = winid or vim.fn.bufwinid(bufnr)
  if winid == -1 then
    return nil
  end

  local screen = vim.fn.screenpos(winid, block.start_line + 1, 1)
  local row = tonumber(screen.row) or 0
  local col = tonumber(screen.col) or 0
  if row < 1 or col < 1 then
    return nil
  end

  local info = vim.fn.getwininfo(winid)[1]
  if not info then
    return nil
  end

  local win_row = tonumber(info.winrow) or row
  local win_col = tonumber(info.wincol) or col
  local win_width = vim.api.nvim_win_get_width(winid)
  local win_height = vim.api.nvim_win_get_height(winid)
  if win_width < 1 or win_height < 1 then
    return nil
  end

  local max_row = win_row + win_height - 1
  local max_col = win_col + win_width - 1
  if row > max_row or col > max_col then
    return nil
  end

  return {
    row = row - 1,
    col = col - 1,
    available_cols = math.max(max_col - col + 1, 1),
    available_rows = math.max(max_row - row + 1, 1),
  }
end

---@param block PicBlock
---@param geometry { available_cols: number, available_rows: number }
---@return number, number
local function get_render_size(block, geometry)
  local block_rows = (block.end_line - block.start_line) + 1
  local max_cols = math.floor(geometry.available_cols * 0.6)
  local max_rows = math.floor(max_cols / 2)
  local cols = math.floor(max_cols * block.scale)
  local rows = math.floor(max_rows * block.scale)
  cols = math.max(math.min(cols, geometry.available_cols), 1)
  rows = math.max(rows, block_rows)
  rows = math.max(math.min(rows, geometry.available_rows), 1)
  return cols, rows
end

---@param bufnr number
---@param block PicBlock
---@return number[]
local function hide_block_lines(bufnr, block)
  local hidden_extmark_ids = {}
  local lines = vim.api.nvim_buf_get_lines(bufnr, block.start_line, block.end_line + 1, false)

  for offset, line in ipairs(lines) do
    local lnum = block.start_line + offset - 1
    local hidden_extmark_id = vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, 0, {
      end_row = lnum,
      end_col = #line,
      hl_group = 'Ignore',
      hl_eol = true,
      invalidate = true,
    })
    table.insert(hidden_extmark_ids, hidden_extmark_id)
  end

  return hidden_extmark_ids
end

---@param bufnr number
---@param block PicBlock
---@param winid? number
---@return Placement|nil
function M.render_block(bufnr, block, winid)
  local proto = protocol.get_active()
  if not proto then
    return nil
  end

  local abs_path = cache.resolve(block.path)
  if not abs_path then
    append_diagnostic(bufnr, {
      lnum = block.start_line,
      col = 0,
      severity = vim.diagnostic.severity.WARN,
      message = 'Invalid image path: ' .. block.path,
      source = 'nvpic',
    })
    return nil
  end

  if vim.fn.filereadable(abs_path) == 0 then
    append_diagnostic(bufnr, {
      lnum = block.start_line,
      col = 0,
      severity = vim.diagnostic.severity.WARN,
      message = 'Image not found: ' .. block.path,
      source = 'nvpic',
    })
    return nil
  end

  local geometry = get_window_geometry(bufnr, block, winid)
  if not geometry then
    return nil
  end

  local cols, rows = get_render_size(block, geometry)

  local placement_id = proto.render({
    image_path = abs_path,
    row = geometry.row,
    col = geometry.col,
    scale = block.scale,
    max_cols = cols,
    max_rows = rows,
  })

  if not placement_id then
    return nil
  end

  local hidden_extmark_ids = hide_block_lines(bufnr, block)
  local block_rows = (block.end_line - block.start_line) + 1
  local spacers = M.make_spacer_lines(math.max(rows - block_rows, 0))
  local extmark_id = vim.api.nvim_buf_set_extmark(bufnr, ns, block.end_line, 0, {
    virt_lines = spacers,
    virt_lines_above = false,
    invalidate = true,
  })

  local placement = {
    extmark_id = extmark_id,
    hidden_extmark_ids = hidden_extmark_ids,
    placement_id = placement_id,
    block = block,
  }

  if not buf_placements[bufnr] then
    buf_placements[bufnr] = {}
  end
  table.insert(buf_placements[bufnr], placement)
  buf_active[bufnr] = true

  return placement
end

---@param bufnr number
---@param winid? number
function M.render_all(bufnr, winid)
  M.clear(bufnr)

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local cs = config.commentstring(bufnr)

  local blocks = marker.parse(lines, cs)
  if #blocks == 0 then
    return
  end

  buf_active[bufnr] = true

  local ts_diags = treesitter.validate(bufnr, blocks)
  if #ts_diags > 0 then
    vim.diagnostic.set(ns, bufnr, ts_diags)
  end

  for _, block in ipairs(blocks) do
    M.render_block(bufnr, block, winid)
  end
end

---@param bufnr number
function M.clear(bufnr)
  stop_debounce(bufnr)

  local placements = buf_placements[bufnr] or {}
  local proto = protocol.get_active()

  for _, p in ipairs(placements) do
    if proto then
      proto.clear(p.placement_id)
    end
    pcall(vim.api.nvim_buf_del_extmark, bufnr, ns, p.extmark_id)
    for _, extmark_id in ipairs(p.hidden_extmark_ids or {}) do
      pcall(vim.api.nvim_buf_del_extmark, bufnr, ns, extmark_id)
    end
  end

  buf_placements[bufnr] = {}
  buf_active[bufnr] = false
  vim.diagnostic.reset(ns, bufnr)
end

---@param bufnr number
function M.toggle(bufnr)
  if M.is_active(bufnr) then
    M.clear(bufnr)
  else
    M.render_all(bufnr)
  end
end

---@param bufnr number
function M.schedule_rescan(bufnr)
  stop_debounce(bufnr)
  local delay = config.get().debounce_ms

  debounce_timers[bufnr] = vim.defer_fn(function()
    debounce_timers[bufnr] = nil
    if vim.api.nvim_buf_is_valid(bufnr) and buf_active[bufnr] then
      M.render_all(bufnr)
    end
  end, delay)
end

return M
