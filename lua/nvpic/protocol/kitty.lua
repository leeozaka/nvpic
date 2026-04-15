local M = {}

M.name = 'kitty'

local ESC = '\027'
local APC_START = ESC .. '_G'
local APC_END = ESC .. '\\'

local id_counter = 0

local function next_id()
  id_counter = id_counter + 1
  return id_counter
end

local function b64(data)
  return vim.base64.encode(data)
end

---@param opts { image_path: string, id: number, cols: number, rows: number }
---@return string
function M.build_render_escape(opts)
  local payload = b64(opts.image_path)
  local control = string.format(
    'a=T,f=100,t=f,i=%d,c=%d,r=%d,z=-1',
    opts.id,
    opts.cols,
    opts.rows
  )
  return APC_START .. control .. ';' .. payload .. APC_END
end

---@param id number
---@return string
function M.build_clear_escape(id)
  return APC_START .. string.format('a=d,d=i,i=%d', id) .. APC_END
end

---@return string
function M.build_clear_all_escape()
  return APC_START .. 'a=d,d=a' .. APC_END
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

function M.detect()
  local term = vim.env.TERM_PROGRAM or ''
  local term_lower = term:lower()
  return term_lower == 'ghostty'
    or term_lower == 'kitty'
    or term_lower == 'wezterm'
end

---@param opts NvpicRenderOpts
---@return string|nil
function M.render(opts)
  local id = next_id()
  local esc = M.build_render_escape({
    image_path = opts.image_path,
    id = id,
    cols = opts.max_cols,
    rows = opts.max_rows,
  })
  local ok = pcall(send, wrap_at_position(opts.row or 0, opts.col or 0, esc))
  if not ok then
    return nil
  end
  return tostring(id)
end

function M.clear(placement_id)
  local id = tonumber(placement_id)
  if id then
    send(M.build_clear_escape(id))
  end
end

function M.clear_all()
  send(M.build_clear_all_escape())
end

return M
