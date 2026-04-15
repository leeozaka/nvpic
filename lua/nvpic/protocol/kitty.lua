local M = {}

M.name = 'kitty'

local ESC = '\027'
local APC_START = ESC .. '_G'
local APC_END = ESC .. '\\'

local image_id_counter = 0
local placement_id_counter = 0

local function next_image_id()
  image_id_counter = image_id_counter + 1
  return image_id_counter
end

local function next_placement_id()
  placement_id_counter = placement_id_counter + 1
  return placement_id_counter
end

local function b64(data)
  return vim.base64.encode(data)
end

function M.capabilities()
  local term = (vim.env.TERM_PROGRAM or ''):lower()
  return {
    supports_reposition = term == 'kitty',
    supports_virtual_anchor = false,
  }
end

---@param opts { image_path: string, image_id: number }
---@return string
function M.build_upload_escape(opts)
  local payload = b64(opts.image_path)
  local control = string.format('a=t,q=1,f=100,t=f,i=%d', opts.image_id)
  return APC_START .. control .. ';' .. payload .. APC_END
end

---@param opts { image_id: number, placement_id: number, cols: number, rows: number }
---@return string
function M.build_place_escape(opts)
  local control = string.format(
    'a=p,q=1,i=%d,p=%d,c=%d,r=%d,C=1,z=-1',
    opts.image_id,
    opts.placement_id,
    opts.cols,
    opts.rows
  )
  return APC_START .. control .. APC_END
end

---@param opts { image_path: string, id: number, placement_id?: number, cols: number, rows: number }
---@return string
function M.build_render_escape(opts)
  local payload = b64(opts.image_path)
  local placement_id = opts.placement_id or next_placement_id()
  local control = string.format(
    'a=T,q=1,f=100,t=f,i=%d,p=%d,c=%d,r=%d,C=1,z=-1',
    opts.id,
    placement_id,
    opts.cols,
    opts.rows
  )
  return APC_START .. control .. ';' .. payload .. APC_END
end

---@param image_id number
---@param placement_id? number
---@return string
function M.build_clear_escape(image_id, placement_id)
  local control = string.format('a=d,q=1,d=i,i=%d', image_id)
  if placement_id then
    control = control .. string.format(',p=%d', placement_id)
  end
  return APC_START .. control .. APC_END
end

---@return string
function M.build_clear_all_escape()
  return APC_START .. 'a=d,q=1,d=a' .. APC_END
end

---@return string
function M.build_detect_escape()
  return APC_START .. 'i=31,s=1,v=1,a=q,t=d,f=24;AAAA' .. APC_END
end

local function send(esc)
  vim.api.nvim_chan_send(2, esc)
end

---@param row number
---@param col number
---@param esc string
---@return string
local function wrap_at_position(row, col, esc)
  return string.format('%s[s%s[%d;%dH%s%s[u', ESC, ESC, row + 1, col + 1, esc, ESC)
end

---@param opts { image_id: number, placement_id?: number, row: number, col: number, max_cols: number, max_rows: number }
---@return string, number
local function build_wrapped_place(opts)
  local placement_id = opts.placement_id or next_placement_id()
  local esc = M.build_place_escape({
    image_id = opts.image_id,
    placement_id = placement_id,
    cols = opts.max_cols,
    rows = opts.max_rows,
  })
  return wrap_at_position(opts.row or 0, opts.col or 0, esc), placement_id
end

function M.detect()
  local term = vim.env.TERM_PROGRAM or ''
  local term_lower = term:lower()
  return term_lower == 'ghostty'
    or term_lower == 'kitty'
    or term_lower == 'wezterm'
end

---@param opts NvpicUploadOpts
---@return number|nil
function M.upload(opts)
  local image_id = opts.image_id or next_image_id()
  local ok = pcall(send, M.build_upload_escape({
    image_path = opts.image_path,
    image_id = image_id,
  }))
  if not ok then
    return nil
  end
  return image_id
end

---@param opts NvpicPlaceOpts
---@return string|nil
function M.place(opts)
  local wrapped, placement_id = build_wrapped_place(opts)
  local ok = pcall(send, wrapped)
  if not ok then
    return nil
  end
  return string.format('%d:%d', opts.image_id, placement_id)
end

---@param opts NvpicRenderOpts
---@return string|nil
function M.render(opts)
  local image_id = opts.image_id or next_image_id()
  local placement_id = opts.placement_id or next_placement_id()
  local esc = M.build_render_escape({
    image_path = opts.image_path,
    id = image_id,
    placement_id = placement_id,
    cols = opts.max_cols,
    rows = opts.max_rows,
  })
  local ok = pcall(send, wrap_at_position(opts.row or 0, opts.col or 0, esc))
  if not ok then
    return nil
  end
  return string.format('%d:%d', image_id, placement_id)
end

---@param handle string
---@return number|nil, number|nil
local function parse_handle(handle)
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

function M.clear(placement_id)
  local image_id, handle_placement_id = parse_handle(placement_id)
  if image_id then
    send(M.build_clear_escape(image_id, handle_placement_id))
  end
end

function M.clear_all()
  send(M.build_clear_all_escape())
end

return M
