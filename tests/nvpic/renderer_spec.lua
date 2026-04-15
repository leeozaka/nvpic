local renderer = require('nvpic.renderer')
local config = require('nvpic.config')
local cache = require('nvpic.cache')
local protocol = require('nvpic.protocol')
local marker = require('nvpic.marker')

local function nvpic_diags(buf)
  local all = vim.diagnostic.get(buf)
  local r = {}
  for _, d in ipairs(all) do
    if d.source == 'nvpic' then
      table.insert(r, d)
    end
  end
  return r
end

describe('nvpic.renderer', function()
  local bufnr
  local saved_get_active
  local saved_bufwinid
  local saved_screenpos

  before_each(function()
    config.reset()
    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
    saved_get_active = protocol.get_active
    saved_bufwinid = vim.fn.bufwinid
    saved_screenpos = vim.fn.screenpos
  end)

  after_each(function()
    protocol.get_active = saved_get_active
    vim.fn.bufwinid = saved_bufwinid
    vim.fn.screenpos = saved_screenpos
    renderer.clear(bufnr)
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  describe('state tracking', function()
    it('starts with no placements', function()
      local placements = renderer.get_placements(bufnr)
      assert.equals(0, #placements)
    end)

    it('is_active returns false initially', function()
      assert.is_false(renderer.is_active(bufnr))
    end)
  end)

  describe('spacer_lines', function()
    it('generates correct number of spacer lines', function()
      local spacers = renderer.make_spacer_lines(5)
      assert.equals(5, #spacers)
      for _, line in ipairs(spacers) do
        assert.equals(1, #line)
        assert.equals('', line[1][1])
      end
    end)
  end)

  describe('render_block', function()
    it('returns nil when no active protocol', function()
      protocol.get_active = function()
        return nil
      end
      local block = {
        start_line = 0,
        end_line = 0,
        path = 'pics/missing.png',
        scale = 1.0,
        alt = '',
      }
      assert.is_nil(renderer.render_block(bufnr, block))
    end)

    it('creates placement and extmark when protocol and file exist', function()
      local test_dir = vim.fn.tempname()
      vim.fn.mkdir(test_dir .. '/pics', 'p')
      cache.set_root(test_dir)
      vim.fn.writefile({}, test_dir .. '/pics/exists.png')
      local cleared = {}
      local render_opts
      vim.fn.bufwinid = function()
        return 11
      end
      vim.fn.screenpos = function(_, lnum, col)
        return { row = lnum + 10, col = col + 20 }
      end
      protocol.get_active = function()
        return {
          name = 'stub',
          detect = function()
            return true
          end,
          render = function(opts)
            render_opts = opts
            return '42'
          end,
          clear = function(id)
            table.insert(cleared, id)
          end,
          clear_all = function() end,
        }
      end
      local block = {
        start_line = 0,
        end_line = 0,
        path = 'pics/exists.png',
        scale = 1.0,
        alt = '',
      }
      local placement = renderer.render_block(bufnr, block)
      assert.is_not_nil(placement)
      assert.equals('42', placement.placement_id)
      assert.equals(block, placement.block)
      assert.is_number(placement.extmark_id)
      assert.equals(1, #renderer.get_placements(bufnr))
      assert.equals(10, render_opts.row)
      assert.equals(20, render_opts.col)
      local ns = vim.api.nvim_create_namespace('nvpic')
      local ext = vim.api.nvim_buf_get_extmark_by_id(bufnr, ns, placement.extmark_id, {})
      assert.is_not_nil(ext)
    end)

    it('warns when image is missing', function()
      cache.set_root(vim.fn.tempname())
      vim.fn.mkdir(cache.resolve('pics'), 'p')
      protocol.get_active = function()
        return {
          name = 'stub',
          detect = function()
            return true
          end,
          render = function()
            return '1'
          end,
          clear = function() end,
          clear_all = function() end,
        }
      end
      local block = {
        start_line = 2,
        end_line = 3,
        path = 'pics/absent.png',
        scale = 1.0,
        alt = '',
      }
      assert.is_nil(renderer.render_block(bufnr, block))
      local diags = nvpic_diags(bufnr)
      assert.equals(1, #diags)
      assert.equals(vim.diagnostic.severity.WARN, diags[1].severity)
      assert.equals('nvpic', diags[1].source)
      assert.equals('Image not found: pics/absent.png', diags[1].message)
    end)

    it('warns when image path escapes the configured pics_dir', function()
      cache.set_root(vim.fn.tempname())
      protocol.get_active = function()
        return {
          name = 'stub',
          detect = function()
            return true
          end,
          render = function()
            error('render should not be called for rejected paths')
          end,
          clear = function() end,
          clear_all = function() end,
        }
      end
      local block = {
        start_line = 1,
        end_line = 2,
        path = '../secret.png',
        scale = 1.0,
        alt = '',
      }

      assert.is_nil(renderer.render_block(bufnr, block))

      local diags = nvpic_diags(bufnr)
      assert.equals(1, #diags)
      assert.equals('nvpic', diags[1].source)
      assert.equals('Invalid image path: ../secret.png', diags[1].message)
    end)
  end)

  describe('clear', function()
    it('resets active state and calls protocol clear for each placement', function()
      local test_dir = vim.fn.tempname()
      vim.fn.mkdir(test_dir .. '/pics', 'p')
      cache.set_root(test_dir)
      vim.fn.writefile({}, test_dir .. '/pics/here.png')
      local cleared = {}
      protocol.get_active = function()
        return {
          name = 'stub',
          detect = function()
            return true
          end,
          render = function()
            return '99'
          end,
          clear = function(id)
            table.insert(cleared, id)
          end,
          clear_all = function() end,
        }
      end
      renderer.render_block(bufnr, {
        start_line = 0,
        end_line = 0,
        path = 'pics/here.png',
        scale = 1.0,
        alt = '',
      })
      assert.is_true(renderer.is_active(bufnr))
      renderer.clear(bufnr)
      assert.is_false(renderer.is_active(bufnr))
      assert.equals(0, #renderer.get_placements(bufnr))
      assert.same({ '99' }, cleared)
    end)
  end)

  describe('toggle', function()
    local saved_parse

    before_each(function()
      saved_parse = marker.parse
    end)

    after_each(function()
      marker.parse = saved_parse
    end)

    it('turns rendering on and off with stubbed parse and protocol', function()
      local test_dir = vim.fn.tempname()
      vim.fn.mkdir(test_dir .. '/pics', 'p')
      cache.set_root(test_dir)
      vim.fn.writefile({}, test_dir .. '/pics/toggle.png')
      marker.parse = function()
        return {
          {
            start_line = 0,
            end_line = 0,
            path = 'pics/toggle.png',
            scale = 1.0,
            alt = '',
          },
        }
      end
      protocol.get_active = function()
        return {
          name = 'stub',
          detect = function()
            return true
          end,
          render = function()
            return '7'
          end,
          clear = function() end,
          clear_all = function() end,
        }
      end
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '// $$pic-start', '// path: pics/toggle.png', '// $$pic-end' })
      vim.bo[bufnr].commentstring = '// %s'

      assert.is_false(renderer.is_active(bufnr))
      renderer.toggle(bufnr)
      assert.is_true(renderer.is_active(bufnr))
      assert.equals(1, #renderer.get_placements(bufnr))

      renderer.toggle(bufnr)
      assert.is_false(renderer.is_active(bufnr))
      assert.equals(0, #renderer.get_placements(bufnr))
    end)
  end)

  describe('render_all', function()
    local saved_parse

    before_each(function()
      saved_parse = marker.parse
    end)

    after_each(function()
      marker.parse = saved_parse
    end)

    it('uses commentstring fallback when buffer commentstring is empty', function()
      local seen_cs
      marker.parse = function(lines, cs)
        seen_cs = cs
        return {}
      end
      vim.bo[bufnr].commentstring = ''
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'x' })
      protocol.get_active = function()
        return nil
      end
      renderer.render_all(bufnr)
      assert.equals('// %s', seen_cs)
    end)
  end)

  describe('schedule_rescan', function()
    local real_render_all

    before_each(function()
      real_render_all = renderer.render_all
    end)

    after_each(function()
      renderer.render_all = real_render_all
    end)

    it('debounces so render_all runs once after rapid calls', function()
      config.setup({ debounce_ms = 40 })
      local test_dir = vim.fn.tempname()
      vim.fn.mkdir(test_dir .. '/pics', 'p')
      cache.set_root(test_dir)
      vim.fn.writefile({}, test_dir .. '/pics/d.png')
      protocol.get_active = function()
        return {
          name = 'stub',
          detect = function()
            return true
          end,
          render = function()
            return '1'
          end,
          clear = function() end,
          clear_all = function() end,
        }
      end
      renderer.render_block(bufnr, {
        start_line = 0,
        end_line = 0,
        path = 'pics/d.png',
        scale = 1.0,
        alt = '',
      })
      local calls = 0
      renderer.render_all = function(b)
        calls = calls + 1
        return real_render_all(b)
      end
      for _ = 1, 5 do
        renderer.schedule_rescan(bufnr)
      end
      vim.wait(400, function()
        return calls >= 1
      end)
      assert.equals(1, calls)
    end)

    it('does not render when buffer is inactive after debounce', function()
      config.setup({ debounce_ms = 40 })
      local calls = 0
      renderer.render_all = function(b)
        calls = calls + 1
        return real_render_all(b)
      end
      assert.is_false(renderer.is_active(bufnr))
      renderer.schedule_rescan(bufnr)
      vim.wait(400, function()
        return false
      end)
      assert.equals(0, calls)
    end)
  end)
end)
