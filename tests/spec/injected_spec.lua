-- `LanguageTree:for_each_tree` also visits injected trees, and node names are
-- not unique across grammars: the `latex` tree exposes a `\text` command as a
-- `latex_block`, so the `markdown_inline` query matched it too and added a
-- second, truncated equation (`\text` alone) next to the real one. MathJax then
-- reported "Missing argument for \text" on a formula that rendered fine.
---@diagnostic disable: duplicate-set-field

local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h:h')
local t = dofile(root .. '/tests/helper.lua')
t.bootstrap()

local mdmath = require'mdmath'
mdmath.setup({update_interval = 30})
-- The FileType autocmd would enable buffers behind the spec's back.
vim.api.nvim_clear_autocmds({group = 'MdMath'})
t.stub_image()
t.skip_without_injection()

-- The regression needs the `latex` parser (the injected tree is what used to be
-- queried). CI installs markdown/markdown_inline only, so skip there.
if not pcall(vim.treesitter.language.add, 'latex') then
    t.skip('latex injected tree', 'install the latex parser')
    t.finish()
end

local Processor = require'mdmath.Processor'
local requests = {}
Processor.from_bufnr = function()
    return {
        request = function(_, data, _, _, width, height, flags, _, callback)
            requests[#requests + 1] = {data = data, width = width, height = height, flags = flags}
            vim.schedule(function()
                callback({width = width, height = height, data = '/tmp/mdmath-injected.png'}, nil)
            end)
        end,
    }
end

t.collect_marks()

---@param lines string[]
---@return integer
local function parse(lines)
    requests = {}
    local bufnr = t.markdown_buffer(lines)
    t.full_view(lines)
    mdmath.enable(bufnr)
    return bufnr
end

local lines = {'$$\\text{中文} + \\alpha = \\beta$$'}
local bufnr = parse(lines)
t.eq(#requests, 1, 'the injected latex tree does not add a second equation')
t.eq(requests[1].data, '\\text{中文} + \\alpha = \\beta', 'the single request carries the whole TeX')
mdmath.disable(bufnr)

-- A command at the start of the block is the shape that used to break; make sure
-- ordinary display math still gets exactly one request.
bufnr = parse({'$$\\alpha + \\beta$$'})
t.eq(#requests, 1, 'plain display math is requested once')
t.eq(requests[1].data, '\\alpha + \\beta', 'plain display math keeps its TeX')
mdmath.disable(bufnr)

t.finish()
