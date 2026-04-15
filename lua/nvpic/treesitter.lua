local M = {}

local COMMENT_TYPES = {
  comment = true,
  line_comment = true,
  block_comment = true,
}

---@param bufnr number
---@param start_line number
---@param end_line number
---@return boolean
function M.is_in_comment(bufnr, start_line, end_line)
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
  if not ok or not parser then
    return true
  end

  local trees = parser:parse()
  if not trees or not trees[1] then
    return true
  end

  local root = trees[1]:root()
  if not root then
    return true
  end

  local node = root:named_descendant_for_range(start_line, 0, start_line, 0)
  while node do
    if COMMENT_TYPES[node:type()] then
      return true
    end
    node = node:parent()
  end

  return false
end

---@param bufnr number
---@param blocks { start_line: number, end_line: number }[]
---@return vim.Diagnostic[]
function M.validate(bufnr, blocks)
  local diagnostics = {}
  for _, block in ipairs(blocks) do
    if not M.is_in_comment(bufnr, block.start_line, block.end_line) then
      table.insert(diagnostics, {
        lnum = block.start_line,
        col = 0,
        severity = vim.diagnostic.severity.WARN,
        message = '$$pic block is outside a comment node',
        source = 'nvpic',
      })
    end
  end
  return diagnostics
end

return M
