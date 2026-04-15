local config = require('nvpic.config')
local uv = vim.uv

local M = {}

local root_dir = ''

---@param path string
---@return boolean
local function is_safe_relative_path(path)
  if type(path) ~= 'string' or path == '' or path:sub(1, 1) == '/' then
    return false
  end

  for segment in path:gmatch('[^/]+') do
    if segment == '.' or segment == '..' then
      return false
    end
  end

  return true
end

---@param rel_path string
---@return boolean
local function is_in_pics_dir(rel_path)
  local dir = config.get().pics_dir
  return rel_path == dir or rel_path:sub(1, #dir + 1) == dir .. '/'
end

---@param dir string
function M.set_root(dir)
  root_dir = dir
end

---@return string
local function pics_dir()
  return root_dir .. '/' .. config.get().pics_dir
end

---@param data string
---@param len? number
---@return string
local function hash(data, len)
  len = len or 6
  local raw = vim.fn.sha256(vim.base64.encode(data))
  return raw:sub(1, len)
end

---@param path string
---@return string|nil
local function read_binary(path)
  local fd = uv.fs_open(path, 'r', 438)
  if not fd then
    return nil
  end

  local stat = uv.fs_fstat(fd)
  if not stat then
    uv.fs_close(fd)
    return nil
  end

  local data = uv.fs_read(fd, stat.size, 0)
  uv.fs_close(fd)
  return data
end

---@param path string
---@param data string
local function write_binary(path, data)
  local fd = assert(uv.fs_open(path, 'w', 420))
  assert(uv.fs_write(fd, data, 0))
  uv.fs_close(fd)
end

---@param full_hash string
---@return integer[]
local function hash_lengths(full_hash)
  local lengths = { 6 }

  for len = 8, #full_hash, 2 do
    table.insert(lengths, len)
  end

  if lengths[#lengths] ~= #full_hash then
    table.insert(lengths, #full_hash)
  end

  return lengths
end

--- Extract width and height from a PNG file's IHDR chunk.
--- PNG layout: 8-byte signature, then IHDR chunk with width (4 bytes BE) at offset 16, height at offset 20.
---@param data string
---@return number|nil width, number|nil height
local function png_dimensions(data)
  if #data < 24 then
    return nil, nil
  end
  -- Verify PNG signature (first 4 bytes: \x89PNG)
  if data:sub(1, 4) ~= '\137PNG' then
    return nil, nil
  end
  local function read_u32be(s, offset)
    local b1, b2, b3, b4 = s:byte(offset, offset + 3)
    return b1 * 0x1000000 + b2 * 0x10000 + b3 * 0x100 + b4
  end
  return read_u32be(data, 17), read_u32be(data, 21)
end

---@return table
local function read_manifest()
  local path = pics_dir() .. '/manifest.json'
  if vim.fn.filereadable(path) == 0 then
    return {}
  end
  local content = vim.fn.readfile(path)
  local ok, manifest = pcall(vim.json.decode, table.concat(content, '\n'))
  if ok and type(manifest) == 'table' then
    return manifest
  end
  vim.notify('nvpic: manifest.json is corrupt, starting fresh', vim.log.levels.WARN)
  return {}
end

---@param manifest table
local function write_manifest(manifest)
  local path = pics_dir() .. '/manifest.json'
  local json = vim.json.encode(manifest)
  vim.fn.writefile({ json }, path)
end

---@param data string
---@param source string
---@return string
function M.store(data, source)
  local dir = pics_dir()
  if vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, 'p')
  end

  local full_hash = hash(data, 64)

  for _, len in ipairs(hash_lengths(full_hash)) do
    local filename = full_hash:sub(1, len) .. '.png'
    local abs_path = dir .. '/' .. filename
    local existing = read_binary(abs_path)

    if not existing then
      write_binary(abs_path, data)

      local w, h = png_dimensions(data)
      local manifest = read_manifest()
      manifest[filename] = {
        original_name = source == 'clipboard' and 'clipboard_paste' or source,
        created = os.date('!%Y-%m-%dT%H:%M:%SZ'),
        source = source,
        width = w,
        height = h,
      }
      write_manifest(manifest)

      return config.get().pics_dir .. '/' .. filename
    end

    if existing == data then
      return config.get().pics_dir .. '/' .. filename
    end
  end

  error('Unable to resolve hash collision for cached image')
end

---@param rel_path string
---@return string|nil
function M.resolve(rel_path)
  if not is_safe_relative_path(rel_path) or not is_in_pics_dir(rel_path) then
    return nil
  end

  return root_dir .. '/' .. rel_path
end

---@param rel_path string
---@return boolean
function M.exists(rel_path)
  local resolved = M.resolve(rel_path)
  return resolved ~= nil and vim.fn.filereadable(resolved) == 1
end

---@return { filename: string, path: string, meta: table|nil }[]
function M.list()
  local dir = pics_dir()
  if vim.fn.isdirectory(dir) == 0 then
    return {}
  end
  local files = vim.fn.glob(dir .. '/*.png', false, true)
  local entries = {}
  local manifest = read_manifest()
  for _, abs in ipairs(files) do
    local filename = vim.fn.fnamemodify(abs, ':t')
    table.insert(entries, {
      filename = filename,
      path = config.get().pics_dir .. '/' .. filename,
      meta = manifest[filename],
    })
  end
  return entries
end

return M
