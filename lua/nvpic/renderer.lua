local marker = require('nvpic.marker')
local cache = require('nvpic.cache')
local protocol = require('nvpic.protocol')
local treesitter = require('nvpic.treesitter')
local config = require('nvpic.config')

local M = {}

local ns = vim.api.nvim_create_namespace('nvpic')

---@class WindowPlacement
---@field winid number
---@field placement_id string
---@field block PicBlock
---@field image_path string
---@field image_id number|nil
---@field placement_ref number|nil
---@field geometry { row: number, col: number, max_cols: number, max_rows: number }

---@class AnchorPlacement
---@field key string
---@field block PicBlock
---@field anchor_extmark_id number|nil
---@field spacer_extmark_id number|nil
---@field hidden_extmark_ids number[]
---@field windows table<number, WindowPlacement>

---@type table<number, table<string, AnchorPlacement>>
local buf_anchors = {}

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
---@return table<string, AnchorPlacement>
local function ensure_anchor_table(bufnr)
  if not buf_anchors[bufnr] then
    buf_anchors[bufnr] = {}
  end
  return buf_anchors[bufnr]
end

---@param bufnr number
---@return table[]
function M.get_placements(bufnr)
  local flattened = {}
  for _, anchor in pairs(buf_anchors[bufnr] or {}) do
    for winid, placement in pairs(anchor.windows) do
      table.insert(flattened, {
        winid = winid,
        extmark_id = anchor.spacer_extmark_id,
        hidden_extmark_ids = anchor.hidden_extmark_ids,
        placement_id = placement.placement_id,
        block = anchor.block,
      })
    end
  end
  table.sort(flattened, function(a, b)
    if a.block.start_line == b.block.start_line then
      return (a.winid or 0) < (b.winid or 0)
    end
    return a.block.start_line < b.block.start_line
  end)
  return flattened
end

---@param bufnr number
---@return boolean
function M.is_active(bufnr)
  return buf_active[bufnr] or false
end

---@param bufnr number
---@return boolean
function M.has_blocks(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  return #marker.parse(lines, config.commentstring(bufnr)) > 0
end

---@param block PicBlock
---@return string
local function anchor_key(block)
  return table.concat({
    tostring(block.start_line),
    tostring(block.end_line),
    block.path,
    tostring(block.scale),
    block.alt,
  }, '\031')
end

---@param block PicBlock
---@return string
local function anchor_fingerprint(block)
  return table.concat({
    block.path,
    tostring(block.scale),
    block.alt,
  }, '\031')
end

---@param bufnr number
---@param preferred_winid? number
---@return integer[]
local function get_target_windows(bufnr, preferred_winid)
  local wins = {}
  local seen = {}

  local function add(winid)
    if not winid or seen[winid] then
      return
    end
    if not vim.api.nvim_win_is_valid(winid) then
      return
    end
    if vim.api.nvim_win_get_buf(winid) ~= bufnr then
      return
    end
    seen[winid] = true
    table.insert(wins, winid)
  end

  add(preferred_winid)
  for _, winid in ipairs(vim.api.nvim_list_wins()) do
    add(winid)
  end

  if #wins == 0 then
    local fallback = vim.fn.bufwinid(bufnr)
    if fallback ~= -1 then
      add(fallback)
    end
  end

  return wins
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
---@param extmark_id number|nil
local function clear_extmark(bufnr, extmark_id)
  if not extmark_id then
    return
  end
  pcall(vim.api.nvim_buf_del_extmark, bufnr, ns, extmark_id)
end

---@param bufnr number
---@param ids number[]
local function clear_extmarks(bufnr, ids)
  for _, extmark_id in ipairs(ids or {}) do
    clear_extmark(bufnr, extmark_id)
  end
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
---@param anchor AnchorPlacement
local function update_anchor_extmark(bufnr, anchor)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  if line_count < 1 then
    clear_extmark(bufnr, anchor.anchor_extmark_id)
    anchor.anchor_extmark_id = nil
    return
  end

  local start_row = math.max(math.min(anchor.block.start_line, line_count - 1), 0)
  local end_row = math.max(math.min(anchor.block.end_line, line_count - 1), start_row)
  local end_line = vim.api.nvim_buf_get_lines(bufnr, end_row, end_row + 1, false)[1] or ''
  anchor.anchor_extmark_id = vim.api.nvim_buf_set_extmark(bufnr, ns, start_row, 0, {
    id = anchor.anchor_extmark_id,
    end_row = end_row,
    end_col = #end_line,
    invalidate = true,
    right_gravity = false,
    end_right_gravity = true,
  })
end

---@param bufnr number
---@param anchor AnchorPlacement
local function clear_anchor_visuals(bufnr, anchor)
  clear_extmarks(bufnr, anchor.hidden_extmark_ids)
  clear_extmark(bufnr, anchor.spacer_extmark_id)
  anchor.hidden_extmark_ids = {}
  anchor.spacer_extmark_id = nil
end

---@param bufnr number
---@param anchor AnchorPlacement
---@param rows number
local function update_anchor_visuals(bufnr, anchor, rows)
  clear_extmarks(bufnr, anchor.hidden_extmark_ids)
  anchor.hidden_extmark_ids = hide_block_lines(bufnr, anchor.block)

  clear_extmark(bufnr, anchor.spacer_extmark_id)
  local block_rows = (anchor.block.end_line - anchor.block.start_line) + 1
  local spacer_rows = math.max(rows - block_rows, 0)
  local opts = {
    invalidate = true,
    virt_lines_above = false,
    virt_lines_overflow = 'scroll',
  }
  if spacer_rows > 0 then
    opts.virt_lines = M.make_spacer_lines(spacer_rows)
  end
  anchor.spacer_extmark_id = vim.api.nvim_buf_set_extmark(bufnr, ns, anchor.block.end_line, 0, opts)
end

---@param anchor AnchorPlacement
---@param winid number
---@param proto NvpicProtocol|nil
local function clear_window_placement(anchor, winid, proto)
  local placement = anchor.windows[winid]
  if not placement then
    return
  end
  if proto then
    proto.clear(placement.placement_id)
  end
  anchor.windows[winid] = nil
end

---@param anchor AnchorPlacement
---@param proto NvpicProtocol|nil
local function clear_anchor_placements(anchor, proto)
  for winid, _ in pairs(anchor.windows) do
    clear_window_placement(anchor, winid, proto)
  end
end

---@param bufnr number
---@param anchors table<string, AnchorPlacement>
---@param key string
---@param proto NvpicProtocol|nil
local function clear_anchor(bufnr, anchors, key, proto)
  local anchor = anchors[key]
  if not anchor then
    return
  end
  clear_anchor_placements(anchor, proto)
  clear_anchor_visuals(bufnr, anchor)
  clear_extmark(bufnr, anchor.anchor_extmark_id)
  anchors[key] = nil
end

---@param bufnr number
---@param anchor AnchorPlacement
---@return boolean
local function anchor_is_invalid(bufnr, anchor)
  if not anchor.anchor_extmark_id then
    return true
  end
  local extmark = vim.api.nvim_buf_get_extmark_by_id(bufnr, ns, anchor.anchor_extmark_id, { details = true })
  if not extmark or #extmark == 0 then
    return true
  end
  local details = extmark[3] or {}
  return details.invalid == true
end

---@param bufnr number
local function clear_invalidated_anchors(bufnr)
  local anchors = buf_anchors[bufnr] or {}
  local proto = protocol.get_active()
  local removed = false
  for key, anchor in pairs(anchors) do
    if anchor_is_invalid(bufnr, anchor) then
      clear_anchor(bufnr, anchors, key, proto)
      removed = true
    end
  end
  if removed and next(anchors) == nil then
    buf_active[bufnr] = false
  end
end

---@param bufnr number
local function clear_missing_anchors(bufnr)
  local anchors = buf_anchors[bufnr] or {}
  if next(anchors) == nil then
    return
  end

  local remaining = {}
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for _, block in ipairs(marker.parse(lines, config.commentstring(bufnr))) do
    local fingerprint = anchor_fingerprint(block)
    remaining[fingerprint] = (remaining[fingerprint] or 0) + 1
  end

  local proto = protocol.get_active()
  local removed = false
  for key, anchor in pairs(anchors) do
    local fingerprint = anchor_fingerprint(anchor.block)
    if (remaining[fingerprint] or 0) > 0 then
      remaining[fingerprint] = remaining[fingerprint] - 1
    else
      clear_anchor(bufnr, anchors, key, proto)
      removed = true
    end
  end

  if removed and next(anchors) == nil then
    buf_active[bufnr] = false
  end
end

---@param bufnr number
---@param anchor AnchorPlacement
---@return string|nil
local function resolve_anchor_path(bufnr, anchor)
  local abs_path = cache.resolve(anchor.block.path)
  if not abs_path then
    append_diagnostic(bufnr, {
      lnum = anchor.block.start_line,
      col = 0,
      severity = vim.diagnostic.severity.WARN,
      message = 'Invalid image path: ' .. anchor.block.path,
      source = 'nvpic',
    })
    return nil
  end

  if vim.fn.filereadable(abs_path) == 0 then
    append_diagnostic(bufnr, {
      lnum = anchor.block.start_line,
      col = 0,
      severity = vim.diagnostic.severity.WARN,
      message = 'Image not found: ' .. anchor.block.path,
      source = 'nvpic',
    })
    return nil
  end

  return abs_path
end

---@param placement WindowPlacement
---@param image_path string
---@param row number
---@param col number
---@param cols number
---@param rows number
---@return boolean
local function placement_matches(placement, image_path, row, col, cols, rows)
  if placement.image_path ~= image_path then
    return false
  end
  return placement.geometry.row == row
    and placement.geometry.col == col
    and placement.geometry.max_cols == cols
    and placement.geometry.max_rows == rows
end

---@param proto NvpicProtocol|nil
---@return NvpicProtocolCapabilities
local function protocol_capabilities(proto)
  if proto and type(proto.capabilities) == 'function' then
    return proto.capabilities()
  end
  return {
    supports_reposition = false,
    supports_virtual_anchor = false,
  }
end

---@param handle string|nil
---@return number|nil, number|nil
local function parse_protocol_handle(handle)
  if type(handle) ~= 'string' then
    return nil, nil
  end
  local image_id, placement_id = handle:match('^(%d+):(%d+)$')
  if image_id and placement_id then
    return tonumber(image_id), tonumber(placement_id)
  end
  local raw = tonumber(handle)
  if raw then
    return raw, nil
  end
  return nil, nil
end

---@param bufnr number
---@param anchor AnchorPlacement
---@param winid number
---@param image_path string
---@return number|nil, table|nil
local function render_anchor_window(bufnr, anchor, winid, image_path)
  local proto = protocol.get_active()
  if not proto then
    return nil, nil
  end

  local geometry = get_window_geometry(bufnr, anchor.block, winid)
  if not geometry then
    clear_window_placement(anchor, winid, proto)
    return nil, nil
  end

  local cols, rows = get_render_size(anchor.block, geometry)
  local current = anchor.windows[winid]
  if current and placement_matches(current, image_path, geometry.row, geometry.col, cols, rows) then
    return rows, {
      winid = winid,
      extmark_id = anchor.spacer_extmark_id,
      hidden_extmark_ids = anchor.hidden_extmark_ids,
      placement_id = current.placement_id,
      block = anchor.block,
    }
  end

  local capabilities = protocol_capabilities(proto)
  local handle = nil
  local image_id = nil
  local placement_ref = nil

  if current
    and current.image_path == image_path
    and current.image_id
    and current.placement_ref
    and capabilities.supports_reposition
    and type(proto.place) == 'function'
  then
    handle = proto.place({
      image_id = current.image_id,
      placement_id = current.placement_ref,
      row = geometry.row,
      col = geometry.col,
      max_cols = cols,
      max_rows = rows,
    })
    if handle then
      image_id = current.image_id
      placement_ref = current.placement_ref
    end
  end

  if not handle then
    clear_window_placement(anchor, winid, proto)
    if not capabilities.supports_reposition and type(proto.render) == 'function' then
      handle = proto.render({
        image_path = image_path,
        row = geometry.row,
        col = geometry.col,
        scale = anchor.block.scale,
        max_cols = cols,
        max_rows = rows,
      })
      if not handle then
        return nil, nil
      end
      image_id, placement_ref = parse_protocol_handle(handle)
    elseif type(proto.upload) == 'function' and type(proto.place) == 'function' then
      image_id = proto.upload({
        image_path = image_path,
      })
      if not image_id then
        return nil, nil
      end
      handle = proto.place({
        image_id = image_id,
        row = geometry.row,
        col = geometry.col,
        max_cols = cols,
        max_rows = rows,
      })
      if not handle then
        return nil, nil
      end
      local _, parsed_placement = parse_protocol_handle(handle)
      placement_ref = parsed_placement
    elseif type(proto.render) == 'function' then
      handle = proto.render({
        image_path = image_path,
        row = geometry.row,
        col = geometry.col,
        scale = anchor.block.scale,
        max_cols = cols,
        max_rows = rows,
      })
      if not handle then
        return nil, nil
      end
      image_id, placement_ref = parse_protocol_handle(handle)
    else
      return nil, nil
    end
  end

  if not image_id or not placement_ref then
    local parsed_image, parsed_placement = parse_protocol_handle(handle)
    image_id = image_id or parsed_image
    placement_ref = placement_ref or parsed_placement
  end

  anchor.windows[winid] = {
    winid = winid,
    placement_id = handle,
    block = anchor.block,
    image_path = image_path,
    image_id = image_id,
    placement_ref = placement_ref,
    geometry = {
      row = geometry.row,
      col = geometry.col,
      max_cols = cols,
      max_rows = rows,
    },
  }

  return rows, {
    winid = winid,
    extmark_id = anchor.spacer_extmark_id,
    hidden_extmark_ids = anchor.hidden_extmark_ids,
      placement_id = handle,
    block = anchor.block,
  }
end

---@param anchor AnchorPlacement
---@param target_set table<number, boolean>
---@param bufnr number
local function clear_non_target_windows(anchor, target_set, bufnr)
  local proto = protocol.get_active()
  for winid, _ in pairs(anchor.windows) do
    if not target_set[winid]
      or not vim.api.nvim_win_is_valid(winid)
      or vim.api.nvim_win_get_buf(winid) ~= bufnr
    then
      clear_window_placement(anchor, winid, proto)
    end
  end
end

---@param bufnr number
---@param block PicBlock
---@param winid? number
---@return table|nil
function M.render_block(bufnr, block, winid)
  stop_debounce(bufnr)
  clear_invalidated_anchors(bufnr)

  local anchors = ensure_anchor_table(bufnr)
  local key = anchor_key(block)
  local anchor = anchors[key]
  if not anchor then
    anchor = {
      key = key,
      block = block,
      anchor_extmark_id = nil,
      spacer_extmark_id = nil,
      hidden_extmark_ids = {},
      windows = {},
    }
    anchors[key] = anchor
  end

  anchor.block = block
  update_anchor_extmark(bufnr, anchor)

  local target_windows = winid and { winid } or get_target_windows(bufnr, nil)
  local target_set = {}
  for _, target_win in ipairs(target_windows) do
    target_set[target_win] = true
  end
  clear_non_target_windows(anchor, target_set, bufnr)

  local abs_path = resolve_anchor_path(bufnr, anchor)
  if not abs_path then
    clear_anchor_placements(anchor, protocol.get_active())
    clear_anchor_visuals(bufnr, anchor)
    return nil
  end

  local max_rows = nil
  local chosen = nil
  for _, target_win in ipairs(target_windows) do
    local rows, placement = render_anchor_window(bufnr, anchor, target_win, abs_path)
    if rows then
      max_rows = math.max(max_rows or 0, rows)
    end
    if placement and target_win == winid then
      chosen = placement
    elseif placement and not chosen then
      chosen = placement
    end
  end

  if max_rows then
    update_anchor_visuals(bufnr, anchor, max_rows)
    if chosen then
      chosen.extmark_id = anchor.spacer_extmark_id
      chosen.hidden_extmark_ids = anchor.hidden_extmark_ids
    end
  else
    clear_anchor_visuals(bufnr, anchor)
  end

  buf_active[bufnr] = true

  return chosen
end

---@param bufnr number
---@param winid? number
function M.render_all(bufnr, winid)
  stop_debounce(bufnr)
  clear_invalidated_anchors(bufnr)

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local cs = config.commentstring(bufnr)

  local blocks = marker.parse(lines, cs)
  if #blocks == 0 then
    M.clear(bufnr)
    return
  end

  local anchors = ensure_anchor_table(bufnr)
  local desired = {}
  for _, block in ipairs(blocks) do
    desired[anchor_key(block)] = block
  end

  local proto = protocol.get_active()
  local stale = {}
  for key, _ in pairs(anchors) do
    if not desired[key] then
      table.insert(stale, key)
    end
  end
  for _, key in ipairs(stale) do
    clear_anchor(bufnr, anchors, key, proto)
  end

  buf_active[bufnr] = true
  vim.diagnostic.reset(ns, bufnr)

  local ts_diags = treesitter.validate(bufnr, blocks)
  if #ts_diags > 0 then
    vim.diagnostic.set(ns, bufnr, ts_diags)
  end

  local target_windows = get_target_windows(bufnr, winid)
  local target_set = {}
  for _, target_win in ipairs(target_windows) do
    target_set[target_win] = true
  end

  for _, block in ipairs(blocks) do
    local key = anchor_key(block)
    local anchor = anchors[key]
    if not anchor then
      anchor = {
        key = key,
        block = block,
        anchor_extmark_id = nil,
        spacer_extmark_id = nil,
        hidden_extmark_ids = {},
        windows = {},
      }
      anchors[key] = anchor
    end

    anchor.block = block
    update_anchor_extmark(bufnr, anchor)
    clear_non_target_windows(anchor, target_set, bufnr)

    local abs_path = resolve_anchor_path(bufnr, anchor)
    if not abs_path then
      clear_anchor_placements(anchor, proto)
      clear_anchor_visuals(bufnr, anchor)
    else
      local max_rows = nil
      for _, target_win in ipairs(target_windows) do
        local rows = render_anchor_window(bufnr, anchor, target_win, abs_path)
        if rows then
          max_rows = math.max(max_rows or 0, rows)
        end
      end

      if max_rows then
        update_anchor_visuals(bufnr, anchor, max_rows)
      else
        clear_anchor_visuals(bufnr, anchor)
      end
    end
  end
end

---@param bufnr number
function M.clear(bufnr)
  stop_debounce(bufnr)

  local anchors = buf_anchors[bufnr] or {}
  local proto = protocol.get_active()

  for key, _ in pairs(anchors) do
    clear_anchor(bufnr, anchors, key, proto)
  end

  buf_anchors[bufnr] = {}
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
---@param winid? number
function M.schedule_rescan(bufnr, winid)
  stop_debounce(bufnr)
  clear_invalidated_anchors(bufnr)
  clear_missing_anchors(bufnr)
  local delay = config.get().debounce_ms

  debounce_timers[bufnr] = vim.defer_fn(function()
    debounce_timers[bufnr] = nil
    if vim.api.nvim_buf_is_valid(bufnr) and (buf_active[bufnr] or M.has_blocks(bufnr)) then
      M.render_all(bufnr, winid)
    end
  end, delay)
end

return M
