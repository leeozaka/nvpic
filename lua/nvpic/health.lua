local config = require('nvpic.config')
local protocol = require('nvpic.protocol')

local M = {}

local function is_macos()
  local uname = vim.uv.os_uname()
  return uname and uname.sysname == 'Darwin'
end

local function project_root()
  return vim.fs.root(0, { '.git', '.nvpic' }) or vim.fn.getcwd()
end

local function pics_status()
  local root = project_root()
  local rel = config.get().pics_dir
  local dir = root .. '/' .. rel
  if vim.fn.isdirectory(dir) == 0 then
    return nil, 0, dir
  end
  local files = vim.fn.glob(dir .. '/*.png', false, true)
  return true, #files, dir
end

function M.check()
  vim.health.start('nvpic')

  local active = protocol.get_active()
  if active then
    vim.health.ok('nvpic: image protocol `' .. active.name .. '` is active.')
  else
    local detected = protocol.detect()
    if detected then
      vim.health.ok('nvpic: image protocol `' .. detected.name .. '` is active (auto-detected).')
    else
      vim.health.warn(
        'nvpic: no supported image protocol detected. Terminal graphics (e.g. Kitty) are required; try `protocol = "kitty"` in `nvpic.setup({ ... })` if you use Kitty.'
      )
    end
  end

  local exists, count, pics_path = pics_status()
  if not exists then
    vim.health.info('nvpic: pics directory `' .. pics_path .. '` is missing; it will be created on first paste.')
  else
    vim.health.ok('nvpic: pics directory `' .. pics_path .. '` exists (' .. tostring(count) .. ' cached image(s)).')
  end

  if vim.fn.executable('osascript') == 1 then
    vim.health.ok('nvpic: `osascript` is available for macOS clipboard access.')
  elseif is_macos() then
    vim.health.error('nvpic: `osascript` was not found; clipboard paste on macOS requires it.')
  else
    vim.health.info('nvpic: `osascript` is unavailable; clipboard paste support is macOS-only.')
  end

  local ts_ok = pcall(vim.treesitter.get_parser, 0)
  if ts_ok then
    vim.health.ok('Treesitter parser available for current buffer')
  else
    vim.health.info('No treesitter parser for current filetype (comment validation will be skipped)')
  end

  local tel_ok = pcall(require, 'telescope')
  if tel_ok then
    vim.health.ok('nvpic: telescope.nvim is installed.')
  else
    vim.health.info('nvpic: telescope.nvim is not installed; `:Telescope nvpic` and `telescope = true` integration are unavailable.')
  end
end

return M
