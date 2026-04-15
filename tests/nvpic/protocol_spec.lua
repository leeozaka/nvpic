local protocol = require('nvpic.protocol')
local kitty = require('nvpic.protocol.kitty')

describe('nvpic.protocol', function()
  describe('interface', function()
    it('kitty module has required fields', function()
      assert.is_string(kitty.name)
      assert.is_function(kitty.capabilities)
      assert.is_function(kitty.detect)
      assert.is_function(kitty.upload)
      assert.is_function(kitty.place)
      assert.is_function(kitty.render)
      assert.is_function(kitty.clear)
      assert.is_function(kitty.clear_all)
    end)

    it('kitty name is "kitty"', function()
      assert.equals('kitty', kitty.name)
    end)
  end)

  describe('registry', function()
    it('registers kitty protocol', function()
      local protocols = protocol.list()
      local names = vim.tbl_map(function(p)
        return p.name
      end, protocols)
      assert.truthy(vim.tbl_contains(names, 'kitty'))
    end)

    it('auto-detects the active protocol when supported', function()
      local previous_term = vim.env.TERM_PROGRAM
      package.loaded['nvpic.protocol'] = nil
      vim.env.TERM_PROGRAM = 'ghostty'

      local fresh_protocol = require('nvpic.protocol')
      assert.equals('kitty', fresh_protocol.get_active().name)

      package.loaded['nvpic.protocol'] = protocol
      vim.env.TERM_PROGRAM = previous_term
    end)
  end)

  describe('kitty escape sequences', function()
    it('reports explicit kitty capabilities', function()
      local capabilities = kitty.capabilities()
      assert.is_boolean(capabilities.supports_reposition)
      assert.is_boolean(capabilities.supports_virtual_anchor)
    end)

    it('builds an upload escape sequence', function()
      local esc = kitty.build_upload_escape({
        image_path = '/tmp/test.png',
        image_id = 9,
      })
      assert.truthy(esc:match('^%z?'))
      assert.truthy(esc:match('^\027_G'))
      assert.truthy(esc:match('a=t'))
      assert.truthy(esc:match('i=9'))
      assert.truthy(esc:match('t=f'))
      assert.truthy(esc:match('f=100'))
    end)

    it('builds a placement escape sequence with explicit cursor policy', function()
      local esc = kitty.build_place_escape({
        image_id = 9,
        placement_id = 4,
        cols = 20,
        rows = 8,
      })
      assert.truthy(esc:match('^\027_G'))
      assert.truthy(esc:match('a=p'))
      assert.truthy(esc:match('i=9'))
      assert.truthy(esc:match('p=4'))
      assert.truthy(esc:match('c=20'))
      assert.truthy(esc:match('r=8'))
      assert.truthy(esc:match('C=1'))
    end)

    it('builds a render escape sequence', function()
      local esc = kitty.build_render_escape({
        image_path = '/tmp/test.png',
        id = 1,
        cols = 40,
        rows = 10,
      })
      assert.truthy(esc:match('^\027_G'))
      assert.truthy(esc:match('\027\\$'))
      assert.truthy(esc:match('a=T'))
      assert.truthy(esc:match('f=100'))
      assert.truthy(esc:match('t=f'))
      assert.truthy(esc:match('q=1'))
      assert.truthy(esc:match('C=1'))
    end)

    it('builds a clear escape sequence for single image', function()
      local esc = kitty.build_clear_escape(42, 7)
      assert.truthy(esc:match('^\027_G'))
      assert.truthy(esc:match('a=d'))
      assert.truthy(esc:match('d=i'))
      assert.truthy(esc:match('i=42'))
      assert.truthy(esc:match('p=7'))
      assert.truthy(esc:match('q=1'))
    end)

    it('builds a clear-all escape sequence', function()
      local esc = kitty.build_clear_all_escape()
      assert.truthy(esc:match('a=d'))
      assert.truthy(esc:match('d=a'))
      assert.truthy(esc:match('q=1'))
    end)

    it('builds a detect query escape sequence', function()
      local esc = kitty.build_detect_escape()
      assert.truthy(esc:match('a=q'))
      assert.truthy(esc:match('i=31'))
    end)

    it('render() positions the image using row and col', function()
      local sent = {}
      local orig_send = vim.api.nvim_chan_send
      vim.api.nvim_chan_send = function(_, data)
        table.insert(sent, data)
      end

      local ok, err = pcall(function()
        kitty.render({
          image_path = '/tmp/test.png',
          row = 5,
          col = 2,
          max_cols = 40,
          max_rows = 10,
        })
      end)

      vim.api.nvim_chan_send = orig_send
      if not ok then
        error(err)
      end

      assert.equals(1, #sent)
      assert.truthy(sent[1]:find('\027%[6;3H'))
    end)

    it('place() positions an uploaded image using row and col', function()
      local sent = {}
      local orig_send = vim.api.nvim_chan_send
      vim.api.nvim_chan_send = function(_, data)
        table.insert(sent, data)
      end

      local ok, err = pcall(function()
        local handle = kitty.place({
          image_id = 12,
          placement_id = 5,
          row = 3,
          col = 1,
          max_cols = 20,
          max_rows = 6,
        })
        assert.equals('12:5', handle)
      end)

      vim.api.nvim_chan_send = orig_send
      if not ok then
        error(err)
      end

      assert.equals(1, #sent)
      assert.truthy(sent[1]:find('\027%[4;2H'))
      assert.truthy(sent[1]:find('a=p'))
      assert.truthy(sent[1]:find('p=5'))
    end)
  end)
end)
