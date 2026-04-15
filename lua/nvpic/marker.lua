local M = {}

---@class PicBlock
---@field start_line number
---@field end_line number
---@field path string
---@field scale number
---@field alt string

---@param commentstring string
---@return string, string
local function get_comment_parts(commentstring)
  local left, right = commentstring:match('^(.-)%%s(.-)$')
  return left or '', right or ''
end

---@param line string
---@param left string
---@param right string
---@return string
local function strip_commentstring(line, left, right)
  local escaped_left = vim.pesc(left)
  local escaped_right = vim.pesc(right)
  local stripped = line:match('^%s*' .. escaped_left .. '(.-)' .. escaped_right .. '%s*$')
  if stripped then
    return vim.trim(stripped)
  end
  return ''
end

---@param lines string[]
---@param commentstring string
---@return PicBlock[]
function M.parse(lines, commentstring)
  local left, right = get_comment_parts(commentstring)
  local blocks = {}
  local current_block = nil

  for i, line in ipairs(lines) do
    local content = strip_commentstring(line, left, right)

    if content == '$$pic-start' then
      current_block = {
        start_line = i - 1,
        path = nil,
        scale = 1.0,
        alt = '',
      }
    elseif content == '$$pic-end' and current_block then
      current_block.end_line = i - 1
      if current_block.path then
        table.insert(blocks, current_block)
      end
      current_block = nil
    elseif current_block then
      local key, value = content:match('^(%w+):%s*(.+)$')
      if key == 'path' then
        current_block.path = value
      elseif key == 'scale' then
        current_block.scale = tonumber(value) or 1.0
      elseif key == 'alt' then
        current_block.alt = value
      end
    end
  end

  return blocks
end

---@param pic { path: string, scale: number, alt: string }
---@param commentstring string
---@return string[]
function M.build(pic, commentstring)
  local lines = {}
  table.insert(lines, string.format(commentstring, '$$pic-start'))
  table.insert(lines, string.format(commentstring, 'path: ' .. pic.path))
  if pic.scale and pic.scale ~= 1.0 then
    table.insert(lines, string.format(commentstring, 'scale: ' .. tostring(pic.scale)))
  end
  if pic.alt and pic.alt ~= '' then
    table.insert(lines, string.format(commentstring, 'alt: ' .. pic.alt))
  end
  table.insert(lines, string.format(commentstring, '$$pic-end'))
  return lines
end

return M
