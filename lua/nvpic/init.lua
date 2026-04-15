local config = require('nvpic.config')
local renderer = require('nvpic.renderer')
local protocol = require('nvpic.protocol')
local cache = require('nvpic.cache')

local M = {}

local augroup = vim.api.nvim_create_augroup('nvpic', { clear = true })

---@param bufnr? number
local function find_root(bufnr)
  bufnr = bufnr or 0
  local name = vim.api.nvim_buf_get_name(bufnr)
  local root = nil
  if name ~= '' then
    root = vim.fs.root(name, { '.git', '.nvpic' })
  end
  if not root and bufnr == 0 then
    root = vim.fs.root(0, { '.git', '.nvpic' })
  end
  return root or vim.fn.getcwd()
end

---@param bufnr? number
local function sync_root(bufnr)
  cache.set_root(find_root(bufnr))
end

local function refresh_visible_active_buffers()
  local ordered_wins = {}
  local current_win = vim.api.nvim_get_current_win()
  if vim.api.nvim_win_is_valid(current_win) then
    table.insert(ordered_wins, current_win)
  end
  for _, winid in ipairs(vim.api.nvim_list_wins()) do
    if winid ~= current_win then
      table.insert(ordered_wins, winid)
    end
  end

  local seen = {}
  for _, winid in ipairs(ordered_wins) do
    if vim.api.nvim_win_is_valid(winid) then
      local bufnr = vim.api.nvim_win_get_buf(winid)
      if not seen[bufnr] and renderer.is_active(bufnr) then
        seen[bufnr] = true
        sync_root(bufnr)
        renderer.render_all(bufnr, winid)
      end
    end
  end
end

---@param opts? table
function M.setup(opts)
  config.setup(opts)
  local cfg = config.get()

  sync_root()
  vim.api.nvim_clear_autocmds({ group = augroup })

  if cfg.protocol then
    local proto = protocol.set(cfg.protocol)
    if not proto then
      vim.notify('nvpic: protocol "' .. cfg.protocol .. '" not found', vim.log.levels.WARN)
    end
  else
    local proto = protocol.detect()
    if not proto then
      vim.notify('nvpic: no supported image protocol detected', vim.log.levels.WARN)
    end
  end

  if cfg.keymaps.paste then
    vim.keymap.set('n', cfg.keymaps.paste, function()
      M.paste()
    end, { desc = 'nvpic: paste image' })
  end
  if cfg.keymaps.pick then
    vim.keymap.set('n', cfg.keymaps.pick, function()
      M.pick()
    end, { desc = 'nvpic: pick image' })
  end
  if cfg.keymaps.toggle then
    vim.keymap.set('n', cfg.keymaps.toggle, function()
      M.toggle()
    end, { desc = 'nvpic: toggle images' })
  end
  if cfg.keymaps.refresh then
    vim.keymap.set('n', cfg.keymaps.refresh, function()
      M.refresh()
    end, { desc = 'nvpic: refresh images' })
  end

  if cfg.auto_render then
    vim.api.nvim_create_autocmd({ 'BufRead', 'BufEnter', 'WinEnter' }, {
      group = augroup,
      callback = function(ev)
        sync_root(ev.buf)
        renderer.render_all(ev.buf, vim.api.nvim_get_current_win())
      end,
      desc = 'nvpic: auto-render images',
    })
  end

  vim.api.nvim_create_autocmd({ 'BufLeave', 'BufDelete' }, {
    group = augroup,
    callback = function(ev)
      renderer.clear(ev.buf)
    end,
    desc = 'nvpic: clear images on leave',
  })

  vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, {
    group = augroup,
    callback = function(ev)
      if renderer.is_active(ev.buf) then
        renderer.schedule_rescan(ev.buf)
      end
    end,
    desc = 'nvpic: debounced re-scan on edit',
  })

  vim.api.nvim_create_autocmd({ 'VimResized', 'WinResized', 'WinScrolled' }, {
    group = augroup,
    callback = function()
      refresh_visible_active_buffers()
    end,
    desc = 'nvpic: refresh images on window changes',
  })

  if cfg.telescope then
    pcall(function()
      require('nvpic.integrations.telescope').setup()
    end)
  end
end

function M.paste()
  sync_root()
  require('nvpic.ui.float').open()
end

function M.pick()
  sync_root()
  local cfg = config.get()
  if cfg.telescope then
    local ok = pcall(function()
      require('telescope').extensions.nvpic.pick()
    end)
    if ok then
      return
    end
  end
  require('nvpic.ui.picker').open()
end

---@param bufnr? number
function M.toggle(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  sync_root()
  renderer.toggle(bufnr)
end

---@param bufnr? number
function M.refresh(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  sync_root(bufnr)
  local winid = nil
  if bufnr == vim.api.nvim_get_current_buf() then
    winid = vim.api.nvim_get_current_win()
  end
  renderer.render_all(bufnr, winid)
end

---@param bufnr? number
function M.clear(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  renderer.clear(bufnr)
end

---@param bufnr? number
---@return boolean
function M.is_active(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  return renderer.is_active(bufnr)
end

---@return string|nil
function M.get_protocol()
  local proto = protocol.get_active()
  return proto and proto.name or nil
end

function M.info()
  sync_root()
  local cfg = config.get()
  local proto = protocol.get_active()
  local entries = cache.list()
  local lines = {
    'nvpic info:',
    '  Protocol: ' .. (proto and proto.name or 'none'),
    '  Pics dir: ' .. cfg.pics_dir,
    '  Images:   ' .. tostring(#entries),
    '  Auto-render: ' .. tostring(cfg.auto_render),
    '  Telescope: ' .. tostring(cfg.telescope),
  }
  vim.notify(table.concat(lines, '\n'), vim.log.levels.INFO)
end

return M
