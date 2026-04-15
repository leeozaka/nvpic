local M = {}

---@class NvpicProtocol
---@field name string
---@field detect fun(): boolean
---@field render fun(opts: NvpicRenderOpts): string|nil
---@field clear fun(placement_id: string)
---@field clear_all fun()

---@class NvpicRenderOpts
---@field image_path string
---@field row number
---@field col number
---@field scale number
---@field max_cols number
---@field max_rows number

---@type NvpicProtocol[]
local registry = {}

---@type NvpicProtocol|nil
local active = nil

---@param proto NvpicProtocol
function M.register(proto)
  table.insert(registry, proto)
end

---@return NvpicProtocol|nil
function M.detect()
  for _, proto in ipairs(registry) do
    if proto.detect() then
      active = proto
      return proto
    end
  end
  return nil
end

---@param name string
---@return NvpicProtocol|nil
function M.set(name)
  for _, proto in ipairs(registry) do
    if proto.name == name then
      active = proto
      return proto
    end
  end
  return nil
end

---@return NvpicProtocol|nil
function M.get_active()
  return active
end

---@return NvpicProtocol[]
function M.list()
  return registry
end

M.register(require('nvpic.protocol.kitty'))
M.detect()

return M
