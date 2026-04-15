describe('nvpic.treesitter', function()
  local treesitter
  local original_get_parser

  before_each(function()
    package.loaded['nvpic.treesitter'] = nil
    original_get_parser = vim.treesitter.get_parser
    treesitter = require('nvpic.treesitter')
  end)

  after_each(function()
    vim.treesitter.get_parser = original_get_parser
    package.loaded['nvpic.treesitter'] = nil
  end)

  describe('is_in_comment', function()
    it('returns true when no parser is available', function()
      vim.treesitter.get_parser = function()
        return nil
      end
      assert.is_true(treesitter.is_in_comment(1, 0, 2))
    end)

    it('returns true when parse yields no primary tree', function()
      vim.treesitter.get_parser = function()
        return {
          parse = function()
            return {}
          end,
        }
      end
      assert.is_true(treesitter.is_in_comment(1, 0, 2))
    end)

    it('returns true when a comment ancestor exists', function()
      local comment = {}
      function comment:type()
        return 'comment'
      end
      function comment:parent()
        return nil
      end
      local inner = {}
      function inner:type()
        return 'chunk'
      end
      function inner:parent()
        return comment
      end
      local root = {}
      function root:named_descendant_for_range()
        return inner
      end
      local tstree = {}
      function tstree:root()
        return root
      end
      vim.treesitter.get_parser = function()
        return {
          parse = function()
            return { [1] = tstree }
          end,
        }
      end
      assert.is_true(treesitter.is_in_comment(1, 3, 5))
    end)

    it('returns true for line_comment ancestor', function()
      local c = {}
      function c:type()
        return 'line_comment'
      end
      function c:parent()
        return nil
      end
      local inner = {}
      function inner:type()
        return 'text'
      end
      function inner:parent()
        return c
      end
      local root = {}
      function root:named_descendant_for_range()
        return inner
      end
      local tstree = {}
      function tstree:root()
        return root
      end
      vim.treesitter.get_parser = function()
        return {
          parse = function()
            return { [1] = tstree }
          end,
        }
      end
      assert.is_true(treesitter.is_in_comment(1, 0, 0))
    end)

    it('returns false when no comment ancestor exists', function()
      local stmt = {}
      function stmt:type()
        return 'statement'
      end
      function stmt:parent()
        return nil
      end
      local inner = {}
      function inner:type()
        return 'identifier'
      end
      function inner:parent()
        return stmt
      end
      local root = {}
      function root:named_descendant_for_range()
        return inner
      end
      local tstree = {}
      function tstree:root()
        return root
      end
      vim.treesitter.get_parser = function()
        return {
          parse = function()
            return { [1] = tstree }
          end,
        }
      end
      assert.is_false(treesitter.is_in_comment(1, 2, 4))
    end)
  end)

  describe('validate', function()
    it('returns one warning for a block outside a comment and none for a valid block', function()
      local valid_comment = {}
      function valid_comment:type()
        return 'block_comment'
      end
      function valid_comment:parent()
        return nil
      end
      local valid_inner = {}
      function valid_inner:type()
        return 'x'
      end
      function valid_inner:parent()
        return valid_comment
      end
      local valid_root = {}
      function valid_root:named_descendant_for_range()
        return valid_inner
      end
      local valid_tstree = {}
      function valid_tstree:root()
        return valid_root
      end

      local bad_stmt = {}
      function bad_stmt:type()
        return 'function'
      end
      function bad_stmt:parent()
        return nil
      end
      local bad_inner = {}
      function bad_inner:type()
        return 'identifier'
      end
      function bad_inner:parent()
        return bad_stmt
      end
      local bad_root = {}
      function bad_root:named_descendant_for_range()
        return bad_inner
      end
      local bad_tstree = {}
      function bad_tstree:root()
        return bad_root
      end

      local bufnr = 7
      vim.treesitter.get_parser = function(b)
        assert.equals(bufnr, b)
        return {
          parse = function()
            return { [1] = bad_tstree }
          end,
        }
      end

      local bad_diags = treesitter.validate(bufnr, { { start_line = 10, end_line = 12 } })
      assert.equals(1, #bad_diags)
      assert.equals(10, bad_diags[1].lnum)
      assert.equals(0, bad_diags[1].col)
      assert.equals(vim.diagnostic.severity.WARN, bad_diags[1].severity)
      assert.equals('$$pic block is outside a comment node', bad_diags[1].message)
      assert.equals('nvpic', bad_diags[1].source)

      vim.treesitter.get_parser = function()
        return {
          parse = function()
            return { [1] = valid_tstree }
          end,
        }
      end
      local good_diags = treesitter.validate(0, { { start_line = 1, end_line = 2 } })
      assert.equals(0, #good_diags)
    end)
  end)
end)
