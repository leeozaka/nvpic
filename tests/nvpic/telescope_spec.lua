describe('nvpic.integrations.telescope', function()
  local tel
  local orig_notify
  local orig_cache
  local orig_marker
  local orig_renderer
  local orig_config
  local notify_calls
  local target_buf
  local preload_orig

  local function set_preload(name, fn)
    if not preload_orig[name] then
      preload_orig[name] = package.preload[name]
    end
    package.preload[name] = fn
    package.loaded[name] = nil
  end

  local function clear_telescope_stubs()
    local names = {
      'telescope',
      'telescope._extensions.nvpic',
      'telescope.pickers',
      'telescope.finders',
      'telescope.config',
      'telescope.previewers',
      'telescope.actions',
      'telescope.actions.state',
    }
    for _, name in ipairs(names) do
      package.loaded[name] = nil
    end
    for name, orig in pairs(preload_orig) do
      package.preload[name] = orig
    end
    preload_orig = {}
  end

  local function reload_telescope_mod()
    package.loaded['nvpic.integrations.telescope'] = nil
    tel = require('nvpic.integrations.telescope')
  end

  local function set_cache_stub(t)
    package.loaded['nvpic.cache'] = t
  end

  local function set_marker_stub(t)
    package.loaded['nvpic.marker'] = t
  end

  local function set_renderer_stub(t)
    package.loaded['nvpic.renderer'] = t
  end

  before_each(function()
    preload_orig = {}
    notify_calls = {}
    orig_notify = vim.notify
    vim.notify = function(msg, level)
      table.insert(notify_calls, { msg = msg, level = level })
    end

    orig_cache = package.loaded['nvpic.cache']
    orig_marker = package.loaded['nvpic.marker']
    orig_renderer = package.loaded['nvpic.renderer']
    orig_config = package.loaded['nvpic.config']

    require('nvpic.config').reset()
    require('nvpic.config').setup({ pics_dir = 'pics', default_scale = 1.0 })

    target_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(target_buf)
    vim.api.nvim_buf_set_lines(target_buf, 0, -1, false, { 'line1', 'line2' })
    vim.api.nvim_win_set_cursor(0, { 2, 0 })

    for _, name in ipairs({
      'telescope',
      'telescope.pickers',
      'telescope.finders',
      'telescope.config',
      'telescope.previewers',
      'telescope.actions',
      'telescope.actions.state',
    }) do
      package.loaded[name] = nil
    end
    reload_telescope_mod()
  end)

  after_each(function()
    vim.notify = orig_notify
    package.loaded['nvpic.cache'] = orig_cache
    package.loaded['nvpic.marker'] = orig_marker
    package.loaded['nvpic.renderer'] = orig_renderer
    package.loaded['nvpic.config'] = orig_config
    package.loaded['nvpic.integrations.telescope'] = nil
    clear_telescope_stubs()
    if vim.api.nvim_buf_is_valid(target_buf) then
      vim.api.nvim_buf_delete(target_buf, { force = true })
    end
  end)

  it('pick() warns when telescope is unavailable', function()
    set_preload('telescope', function()
      error('module not found')
    end)
    reload_telescope_mod()
    tel.pick()
    assert.equals(1, #notify_calls)
    assert.truthy(notify_calls[1].msg:match('telescope'))
    assert.equals(vim.log.levels.WARN, notify_calls[1].level)
  end)

  it('pick() notifies when cache list is empty', function()
    set_preload('telescope', function()
      return {}
    end)
    set_cache_stub({
      list = function()
        return {}
      end,
    })
    reload_telescope_mod()
    tel.pick()
    assert.equals(1, #notify_calls)
    assert.equals('nvpic: no images in pics', notify_calls[1].msg)
    assert.equals(vim.log.levels.INFO, notify_calls[1].level)
  end)

  it('setup() registers the extension export', function()
    local captured
    set_preload('telescope', function()
      return {
        register_extension = function(cfg)
          captured = cfg
          return { _registered = true }
        end,
      }
    end)
    reload_telescope_mod()
    local ret = tel.setup()
    assert.is_not_nil(captured)
    assert.is_function(captured.exports.pick)
    assert.equals(tel.pick, captured.exports.pick)
    assert.same({ _registered = true }, ret)
  end)

  it('provides a Telescope extension loader module', function()
    local captured
    set_preload('telescope', function()
      return {
        register_extension = function(cfg)
          captured = cfg
          return cfg.exports
        end,
      }
    end)
    reload_telescope_mod()

    package.loaded['telescope._extensions.nvpic'] = nil
    local ext = require('telescope._extensions.nvpic')

    assert.is_not_nil(captured)
    assert.is_function(ext.pick)
    assert.equals(tel.pick, ext.pick)
  end)

  it('select_default inserts marker lines and calls renderer.render_block', function()
    local picker_cfg
    local select_default_fn
    local close_calls = {}

    set_cache_stub({
      list = function()
        return {
          {
            filename = 'z.png',
            path = 'pics/z.png',
            meta = nil,
          },
        }
      end,
    })

    local built_pic
    local built_cs
    set_marker_stub({
      build = function(pic, cs)
        built_pic = pic
        built_cs = cs
        return { '// $$pic-start', '// path: pics/z.png', '// $$pic-end' }
      end,
    })

    local render_calls = {}
    set_renderer_stub({
      render_block = function(bufnr, block)
        table.insert(render_calls, { bufnr = bufnr, block = block })
      end,
    })

    set_preload('telescope', function()
      return {}
    end)

    set_preload('telescope.pickers', function()
      return {
        new = function(_, cfg)
          picker_cfg = cfg
          return {
            find = function()
              if cfg.attach_mappings then
                local map = function() end
                cfg.attach_mappings(42, map)
              end
              if select_default_fn then
                select_default_fn()
              end
            end,
          }
        end,
      }
    end)

    set_preload('telescope.finders', function()
      return {
        new_table = function(t)
          return t
        end,
      }
    end)

    set_preload('telescope.config', function()
      return {
        values = {
          generic_sorter = function()
            return function() end
          end,
        },
      }
    end)

    set_preload('telescope.previewers', function()
      return {
        new_buffer_previewer = function() end,
      }
    end)

    set_preload('telescope.actions', function()
      return {
        select_default = {
          replace = function(_, fn)
            select_default_fn = fn
          end,
        },
        close = function(bufnr)
          table.insert(close_calls, bufnr)
        end,
      }
    end)

    set_preload('telescope.actions.state', function()
      return {
        get_selected_entry = function()
          return {
            value = {
              filename = 'z.png',
              path = 'pics/z.png',
              meta = nil,
            },
          }
        end,
      }
    end)

    reload_telescope_mod()
    vim.bo[target_buf].commentstring = '// %s'
    vim.api.nvim_set_current_buf(target_buf)
    vim.api.nvim_win_set_cursor(0, { 2, 0 })

    tel.pick()
    assert.is_not_nil(picker_cfg)
    assert.is_function(select_default_fn)

    assert.is_not_nil(built_pic)
    assert.equals('pics/z.png', built_pic.path)
    assert.equals(1.0, built_pic.scale)
    assert.equals('', built_pic.alt)
    assert.equals('// %s', built_cs)

    local lines = vim.api.nvim_buf_get_lines(target_buf, 0, -1, false)
    assert.same({ 'line1', '// $$pic-start', '// path: pics/z.png', '// $$pic-end', 'line2' }, lines)

    assert.equals(1, #render_calls)
    assert.equals(target_buf, render_calls[1].bufnr)
    assert.equals('pics/z.png', render_calls[1].block.path)
    assert.equals(1.0, render_calls[1].block.scale)
    assert.equals('', render_calls[1].block.alt)
    assert.equals(1, render_calls[1].block.start_line)
    assert.equals(3, render_calls[1].block.end_line)
    assert.same({ 42 }, close_calls)
  end)

  it('select_default keeps the original target buffer when focus changes before choice', function()
    local picker_cfg
    local select_default_fn
    local other_buf = vim.api.nvim_create_buf(false, true)

    set_cache_stub({
      list = function()
        return {
          {
            filename = 'z.png',
            path = 'pics/z.png',
            meta = nil,
          },
        }
      end,
    })
    set_marker_stub({
      build = function()
        return { '// $$pic-start', '// path: pics/z.png', '// $$pic-end' }
      end,
    })
    local render_calls = {}
    set_renderer_stub({
      render_block = function(bufnr, block)
        table.insert(render_calls, { bufnr = bufnr, block = block })
      end,
    })

    set_preload('telescope', function()
      return {}
    end)
    set_preload('telescope.pickers', function()
      return {
        new = function(_, cfg)
          picker_cfg = cfg
          return {
            find = function()
              cfg.attach_mappings(42, function() end)
            end,
          }
        end,
      }
    end)
    set_preload('telescope.finders', function()
      return { new_table = function(t) return t end }
    end)
    set_preload('telescope.config', function()
      return {
        values = {
          generic_sorter = function()
            return function() end
          end,
        },
      }
    end)
    set_preload('telescope.previewers', function()
      return {
        new_buffer_previewer = function()
          return {}
        end,
      }
    end)
    set_preload('telescope.actions', function()
      return {
        select_default = {
          replace = function(_, fn)
            select_default_fn = fn
          end,
        },
        close = function() end,
      }
    end)
    set_preload('telescope.actions.state', function()
      return {
        get_selected_entry = function()
          return {
            value = {
              filename = 'z.png',
              path = 'pics/z.png',
              meta = nil,
            },
          }
        end,
      }
    end)

    reload_telescope_mod()
    vim.bo[target_buf].commentstring = '// %s'
    vim.api.nvim_set_current_buf(target_buf)
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    tel.pick()

    assert.is_not_nil(picker_cfg)
    assert.is_function(select_default_fn)

    vim.api.nvim_set_current_buf(other_buf)
    vim.api.nvim_buf_set_lines(other_buf, 0, -1, false, { 'other' })
    select_default_fn()

    assert.same({ 'line1', '// $$pic-start', '// path: pics/z.png', '// $$pic-end', 'line2' }, vim.api.nvim_buf_get_lines(target_buf, 0, -1, false))
    assert.same({ 'other' }, vim.api.nvim_buf_get_lines(other_buf, 0, -1, false))
    assert.equals(1, #render_calls)
    assert.equals(target_buf, render_calls[1].bufnr)

    vim.api.nvim_buf_delete(other_buf, { force = true })
  end)

  it('previewer define_preview writes expected info lines when metadata exists', function()
    local previewer_opts
    local tmp = vim.fn.tempname() .. '_nvpic.png'
    vim.fn.writefile({ 'abcde' }, tmp)

    set_cache_stub({
      list = function()
        return {
          {
            filename = 'm.png',
            path = 'pics/m.png',
            meta = {
              source = 'clipboard',
              created = '2021-06-01T12:00:00Z',
            },
          },
        }
      end,
      resolve = function(rel)
        if rel == 'pics/m.png' then
          return tmp
        end
        return rel
      end,
    })

    set_preload('telescope', function()
      return {}
    end)
    set_preload('telescope.pickers', function()
      return {
        new = function()
          return { find = function() end }
        end,
      }
    end)
    set_preload('telescope.finders', function()
      return { new_table = function() end }
    end)
    set_preload('telescope.config', function()
      return {
        values = {
          generic_sorter = function()
            return function() end
          end,
        },
      }
    end)
    set_preload('telescope.previewers', function()
      return {
        new_buffer_previewer = function(opts)
          previewer_opts = opts
          return {}
        end,
      }
    end)
    set_preload('telescope.actions', function()
      return {
        select_default = { replace = function() end },
        close = function() end,
      }
    end)
    set_preload('telescope.actions.state', function()
      return { get_selected_entry = function() end }
    end)

    reload_telescope_mod()
    tel.pick()

    assert.is_not_nil(previewer_opts)
    assert.is_function(previewer_opts.define_preview)

    local preview_buf = vim.api.nvim_create_buf(false, true)
    local entry = {
      value = {
        filename = 'm.png',
        path = 'pics/m.png',
        meta = {
          width = 100,
          height = 50,
          source = 'clipboard',
          created = '2021-06-01T12:00:00Z',
        },
      },
    }
    previewer_opts.define_preview({ state = { bufnr = preview_buf } }, entry, {})

    local plines = vim.api.nvim_buf_get_lines(preview_buf, 0, -1, false)
    local blob = table.concat(plines, '\n')
    assert.truthy(blob:match('m%.png'))
    assert.truthy(blob:match('pics/m%.png'))
    assert.truthy(blob:match('Size:%s+100x50'))
    assert.truthy(blob:match('clipboard'))
    assert.truthy(blob:match('2021%-06%-01T12:00:00Z'))

    vim.fn.delete(tmp)
    if vim.api.nvim_buf_is_valid(preview_buf) then
      vim.api.nvim_buf_delete(preview_buf, { force = true })
    end
  end)
end)
