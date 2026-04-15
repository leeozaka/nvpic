local config = require('nvpic.config')
local protocol = require('nvpic.protocol')

describe('nvpic.health', function()
  local orig_health = {}
  local health_calls = {}
  local orig_executable
  local orig_get_parser
  local orig_telescope_loaded
  local orig_telescope_preload
  local saved_get_active
  local saved_detect
  local orig_os_uname

  local function stub_health()
    for _, name in ipairs({ 'start', 'ok', 'warn', 'info', 'error' }) do
      orig_health[name] = vim.health[name]
      vim.health[name] = function(msg)
        table.insert(health_calls, { name, msg })
      end
    end
  end

  local function restore_health()
    for name, fn in pairs(orig_health) do
      vim.health[name] = fn
    end
    orig_health = {}
  end

  local function reload_health()
    package.loaded['nvpic.health'] = nil
    return require('nvpic.health')
  end

  local function msg_with_pred(kind, pred)
    for _, call in ipairs(health_calls) do
      if call[1] == kind and pred(call[2]) then
        return true
      end
    end
    return false
  end

  before_each(function()
    health_calls = {}
    saved_get_active = protocol.get_active
    saved_detect = protocol.detect
    stub_health()
    orig_executable = vim.fn.executable
    orig_get_parser = vim.treesitter.get_parser
    orig_telescope_loaded = package.loaded['telescope']
    orig_telescope_preload = package.preload['telescope']
    orig_os_uname = vim.uv.os_uname
  end)

  after_each(function()
    protocol.get_active = saved_get_active
    protocol.detect = saved_detect
    restore_health()
    vim.fn.executable = orig_executable
    vim.treesitter.get_parser = orig_get_parser
    package.loaded['telescope'] = orig_telescope_loaded
    package.preload['telescope'] = orig_telescope_preload
    vim.uv.os_uname = orig_os_uname
    config.reset()
    package.loaded['nvpic.health'] = nil
  end)

  it('reports ok when an image protocol is active', function()
    protocol.get_active = function()
      return { name = 'kitty' }
    end
    protocol.detect = function()
      return nil
    end
    local health = reload_health()
    health.check()
    assert.truthy(msg_with_pred('ok', function(m)
      return m:find('kitty', 1, true) and m:find('protocol', 1, true)
    end))
  end)

  it('warns with hints when no protocol is active and detection fails', function()
    protocol.get_active = function()
      return nil
    end
    protocol.detect = function()
      return nil
    end
    local health = reload_health()
    health.check()
    assert.truthy(msg_with_pred('warn', function(m)
      return m:find('no supported image protocol', 1, true)
        and (m:find('protocol', 1, true) or m:find('kitty', 1, true) or m:find('setup', 1, true))
    end))
  end)

  it('reports ok when protocol detection succeeds without an active protocol', function()
    protocol.get_active = function()
      return nil
    end
    protocol.detect = function()
      return { name = 'kitty' }
    end
    local health = reload_health()
    health.check()
    assert.truthy(msg_with_pred('ok', function(m)
      return m:find('kitty', 1, true) and m:find('auto', 1, true)
    end))
  end)

  describe('pics directory', function()
    local test_dir
    local orig_getcwd
    local orig_fs_root

    before_each(function()
      test_dir = vim.fn.tempname()
      vim.fn.mkdir(test_dir, 'p')
      orig_getcwd = vim.fn.getcwd
      orig_fs_root = vim.fs.root
      vim.fn.getcwd = function()
        return test_dir
      end
      vim.fs.root = function()
        return nil
      end
      config.setup({ pics_dir = 'pics' })
      protocol.get_active = function()
        return { name = 'kitty' }
      end
      protocol.detect = function()
        return nil
      end
    end)

    after_each(function()
      vim.fn.getcwd = orig_getcwd
      vim.fs.root = orig_fs_root
      vim.fn.delete(test_dir, 'rf')
    end)

    it('reports ok with image count when pics dir exists', function()
      local pics = test_dir .. '/pics'
      vim.fn.mkdir(pics, 'p')
      vim.fn.writefile({}, pics .. '/a.png')
      vim.fn.writefile({}, pics .. '/b.png')
      vim.fn.executable = function(name)
        if name == 'osascript' then
          return 1
        end
        return orig_executable(name)
      end
      vim.treesitter.get_parser = function()
        return {}
      end
      local health = reload_health()
      health.check()
      assert.truthy(msg_with_pred('ok', function(m)
        return m:find('pics', 1, true) and m:find('2', 1, true)
      end))
    end)

    it('reports info when pics dir is missing', function()
      vim.fn.executable = function(name)
        if name == 'osascript' then
          return 1
        end
        return orig_executable(name)
      end
      vim.treesitter.get_parser = function()
        return {}
      end
      local health = reload_health()
      health.check()
      assert.truthy(msg_with_pred('info', function(m)
        return m:find('pics', 1, true) and (m:find('missing', 1, true) or m:find('created', 1, true))
      end))
    end)
  end)

  it('reports ok when osascript is present', function()
    protocol.get_active = function()
      return { name = 'kitty' }
    end
    protocol.detect = function()
      return nil
    end
    vim.fn.executable = function(name)
      if name == 'osascript' then
        return 1
      end
      return orig_executable(name)
    end
    vim.treesitter.get_parser = function()
      return {}
    end
    local health = reload_health()
    health.check()
    assert.truthy(msg_with_pred('ok', function(m)
      return m:find('osascript', 1, true)
    end))
  end)

  it('reports error when osascript is missing', function()
    protocol.get_active = function()
      return { name = 'kitty' }
    end
    protocol.detect = function()
      return nil
    end
    vim.fn.executable = function(name)
      if name == 'osascript' then
        return 0
      end
      return orig_executable(name)
    end
    vim.treesitter.get_parser = function()
      return {}
    end
    local health = reload_health()
    health.check()
    assert.truthy(msg_with_pred('error', function(m)
      return m:find('osascript', 1, true)
    end))
  end)

  it('reports info when osascript is missing on non-macOS', function()
    protocol.get_active = function()
      return { name = 'kitty' }
    end
    protocol.detect = function()
      return nil
    end
    vim.fn.executable = function(name)
      if name == 'osascript' then
        return 0
      end
      return orig_executable(name)
    end
    vim.uv.os_uname = function()
      return { sysname = 'Linux' }
    end
    vim.treesitter.get_parser = function()
      return {}
    end
    local health = reload_health()
    health.check()
    assert.truthy(msg_with_pred('info', function(m)
      return m:find('osascript', 1, true)
    end))
  end)

  it('reports ok when treesitter parser is available', function()
    protocol.get_active = function()
      return { name = 'kitty' }
    end
    protocol.detect = function()
      return nil
    end
    vim.fn.executable = function(name)
      if name == 'osascript' then
        return 1
      end
      return orig_executable(name)
    end
    vim.treesitter.get_parser = function(bufnr)
      assert.equals(0, bufnr)
      return {}
    end
    local health = reload_health()
    health.check()
    assert.truthy(msg_with_pred('ok', function(m)
      return m:find('Treesitter parser available for current buffer', 1, true)
    end))
  end)

  it('reports info when treesitter parser is unavailable', function()
    protocol.get_active = function()
      return { name = 'kitty' }
    end
    protocol.detect = function()
      return nil
    end
    vim.fn.executable = function(name)
      if name == 'osascript' then
        return 1
      end
      return orig_executable(name)
    end
    vim.treesitter.get_parser = function(bufnr)
      assert.equals(0, bufnr)
      error('no parser')
    end
    local health = reload_health()
    health.check()
    assert.truthy(msg_with_pred('info', function(m)
      return m:find('No treesitter parser for current filetype', 1, true)
    end))
  end)

  it('reports ok when telescope is available', function()
    protocol.get_active = function()
      return { name = 'kitty' }
    end
    protocol.detect = function()
      return nil
    end
    vim.fn.executable = function(name)
      if name == 'osascript' then
        return 1
      end
      return orig_executable(name)
    end
    vim.treesitter.get_parser = function()
      return {}
    end
    package.loaded['telescope'] = {}
    local health = reload_health()
    health.check()
    assert.truthy(msg_with_pred('ok', function(m)
      return m:find('telescope', 1, true)
    end))
  end)

  it('reports info when telescope is not installed', function()
    protocol.get_active = function()
      return { name = 'kitty' }
    end
    protocol.detect = function()
      return nil
    end
    vim.fn.executable = function(name)
      if name == 'osascript' then
        return 1
      end
      return orig_executable(name)
    end
    vim.treesitter.get_parser = function()
      return {}
    end
    package.loaded['telescope'] = nil
    package.preload['telescope'] = function()
      error('telescope not installed')
    end
    local health = reload_health()
    health.check()
    assert.truthy(msg_with_pred('info', function(m)
      return m:find('telescope', 1, true)
    end))
  end)

  it('calls vim.health.start', function()
    protocol.get_active = function()
      return { name = 'kitty' }
    end
    protocol.detect = function()
      return nil
    end
    vim.fn.executable = function(name)
      if name == 'osascript' then
        return 1
      end
      return orig_executable(name)
    end
    vim.treesitter.get_parser = function()
      return {}
    end
    local health = reload_health()
    health.check()
    assert.equals('start', health_calls[1][1])
    assert.truthy(health_calls[1][2]:lower():find('nvpic', 1, true))
  end)
end)
