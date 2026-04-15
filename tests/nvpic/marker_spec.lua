local marker = require('nvpic.marker')

describe('nvpic.marker', function()
  describe('parse', function()
    it('parses a lua comment block', function()
      local lines = {
        'local x = 1',
        '-- $$pic-start',
        '-- path: pics/a3f8b2.png',
        '-- scale: 0.5',
        '-- alt: Test image',
        '-- $$pic-end',
        'local y = 2',
      }
      local blocks = marker.parse(lines, '-- %s')
      assert.equals(1, #blocks)
      assert.equals(1, blocks[1].start_line)
      assert.equals(5, blocks[1].end_line)
      assert.equals('pics/a3f8b2.png', blocks[1].path)
      assert.equals(0.5, blocks[1].scale)
      assert.equals('Test image', blocks[1].alt)
    end)

    it('parses a python comment block', function()
      local lines = {
        '# $$pic-start',
        '# path: pics/abc123.png',
        '# $$pic-end',
      }
      local blocks = marker.parse(lines, '# %s')
      assert.equals(1, #blocks)
      assert.equals('pics/abc123.png', blocks[1].path)
      assert.equals(1.0, blocks[1].scale)
      assert.equals('', blocks[1].alt)
    end)

    it('parses javascript comment block', function()
      local lines = {
        '// $$pic-start',
        '// path: pics/def456.png',
        '// scale: 0.75',
        '// $$pic-end',
      }
      local blocks = marker.parse(lines, '// %s')
      assert.equals(1, #blocks)
      assert.equals(0.75, blocks[1].scale)
    end)

    it('parses wrapped comment blocks', function()
      local lines = {
        '/* $$pic-start */',
        '/* path: pics/wrapped.png */',
        '/* alt: Wrapped comment */',
        '/* $$pic-end */',
      }
      local blocks = marker.parse(lines, '/* %s */')
      assert.equals(1, #blocks)
      assert.equals('pics/wrapped.png', blocks[1].path)
      assert.equals('Wrapped comment', blocks[1].alt)
    end)

    it('parses multiple blocks', function()
      local lines = {
        '-- $$pic-start',
        '-- path: pics/aaa.png',
        '-- $$pic-end',
        'code here',
        '-- $$pic-start',
        '-- path: pics/bbb.png',
        '-- $$pic-end',
      }
      local blocks = marker.parse(lines, '-- %s')
      assert.equals(2, #blocks)
      assert.equals('pics/aaa.png', blocks[1].path)
      assert.equals('pics/bbb.png', blocks[2].path)
    end)

    it('ignores incomplete blocks (start without end)', function()
      local lines = {
        '-- $$pic-start',
        '-- path: pics/aaa.png',
      }
      local blocks = marker.parse(lines, '-- %s')
      assert.equals(0, #blocks)
    end)

    it('ignores blocks without required path field', function()
      local lines = {
        '-- $$pic-start',
        '-- scale: 0.5',
        '-- $$pic-end',
      }
      local blocks = marker.parse(lines, '-- %s')
      assert.equals(0, #blocks)
    end)
  end)

  describe('build', function()
    it('builds a lua comment block', function()
      local lines = marker.build({
        path = 'pics/a3f8b2.png',
        scale = 0.5,
        alt = 'Test image',
      }, '-- %s')
      assert.equals('-- $$pic-start', lines[1])
      assert.equals('-- path: pics/a3f8b2.png', lines[2])
      assert.equals('-- scale: 0.5', lines[3])
      assert.equals('-- alt: Test image', lines[4])
      assert.equals('-- $$pic-end', lines[5])
    end)

    it('omits alt when empty', function()
      local lines = marker.build({
        path = 'pics/a3f8b2.png',
        scale = 0.5,
        alt = '',
      }, '-- %s')
      assert.equals(4, #lines)
      assert.equals('-- $$pic-start', lines[1])
      assert.equals('-- path: pics/a3f8b2.png', lines[2])
      assert.equals('-- scale: 0.5', lines[3])
      assert.equals('-- $$pic-end', lines[4])
    end)

    it('omits scale when default', function()
      local lines = marker.build({
        path = 'pics/a3f8b2.png',
        scale = 1.0,
        alt = '',
      }, '-- %s')
      assert.equals(3, #lines)
      assert.equals('-- $$pic-start', lines[1])
      assert.equals('-- path: pics/a3f8b2.png', lines[2])
      assert.equals('-- $$pic-end', lines[3])
    end)
  end)
end)
