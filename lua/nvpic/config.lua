local M = {}

---@class NvpicKeymaps
---@field paste string|false
---@field pick string|false
---@field toggle string|false
---@field refresh string|false

---@class NvpicConfig
---@field pics_dir string
---@field default_scale number
---@field auto_render boolean
---@field debounce_ms number
---@field protocol string|nil
---@field keymaps NvpicKeymaps
---@field telescope boolean

M.DEFAULT_COMMENTSTRING = '// %s'

local defaults = {
  pics_dir = 'pics',
  default_scale = 1.0,
  auto_render = true,
  debounce_ms = 200,
  protocol = nil,
  keymaps = {
    paste = '<leader>ip',
    pick = '<leader>if',
    toggle = '<leader>it',
    refresh = '<leader>ir',
  },
  telescope = false,
}

---@type NvpicConfig
local current = vim.deepcopy(defaults)

---@param path string
local function validate_pics_dir(path)
  if type(path) ~= 'string' or path == '' then
    error('nvpic: pics_dir must be a non-empty relative path')
  end

  if path:sub(1, 1) == '/' then
    error('nvpic: pics_dir must be relative to the project root')
  end

  for segment in path:gmatch('[^/]+') do
    if segment == '.' or segment == '..' then
      error('nvpic: pics_dir must not contain "." or ".." segments')
    end
  end
end

---@param base table
---@param override table
---@return table
local function deep_merge(base, override)
  local result = vim.deepcopy(base)
  for k, v in pairs(override) do
    if type(v) == 'table' and type(result[k]) == 'table' then
      result[k] = deep_merge(result[k], v)
    else
      result[k] = v
    end
  end
  return result
end

---@param cfg table
local function validate(cfg)
  validate_pics_dir(cfg.pics_dir)

  if type(cfg.default_scale) ~= 'number' or cfg.default_scale <= 0 or cfg.default_scale > 10 then
    error('nvpic: default_scale must be a number between 0 (exclusive) and 10')
  end

  if type(cfg.debounce_ms) ~= 'number' or cfg.debounce_ms < 0 then
    error('nvpic: debounce_ms must be a non-negative number')
  end
end

---@param opts? table
function M.setup(opts)
  local next_config = deep_merge(defaults, opts or {})
  validate(next_config)
  current = next_config
end

---@return NvpicConfig
function M.get()
  return vim.deepcopy(current)
end

function M.reset()
  current = vim.deepcopy(defaults)
end

--- Get commentstring for a buffer, falling back to default.
---@param bufnr number
---@return string
function M.commentstring(bufnr)
  local cs = vim.bo[bufnr].commentstring
  if cs and cs ~= '' then
    return cs
  end
  return M.DEFAULT_COMMENTSTRING
end

return M
