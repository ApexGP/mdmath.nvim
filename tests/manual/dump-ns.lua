-- Dump every extmark namespace touching a markdown buffer, so we can see which
-- plugin is decorating LaTeX source besides mdmath.
--
-- Run it from a live session that already has all plugins loaded:
--   :edit tests/manual/mdmath-test.md
--   :luafile tests/manual/dump-ns.lua
-- Do not start it with `nvim --headless -u <LazyVim init>`: the distro blocks
-- before `-c` runs and the process hangs instead of producing the log.
local out = {}

local function log(fmt, ...)
    out[#out + 1] = select("#", ...) > 0 and string.format(fmt, ...) or fmt
end

local buf = vim.api.nvim_get_current_buf()
log("buf=%d file=%s", buf, vim.api.nvim_buf_get_name(buf))

-- Registered namespaces (id -> name).
local ns_names = {}
for name, id in pairs(vim.api.nvim_get_namespaces()) do
    ns_names[id] = name
end

local marks = vim.api.nvim_buf_get_extmarks(buf, -1, 0, -1, { details = true, type = "extmark" })
log("total extmarks=%d", #marks)

local per_ns = {}
for _, m in ipairs(marks) do
    local ns = m[1]
    per_ns[ns] = per_ns[ns] or {}
    table.insert(per_ns[ns], m)
end

for ns, list in pairs(per_ns) do
    log("--- ns=%s (%s) count=%d", tostring(ns), ns_names[ns] or "?", #list)
    for i, m in ipairs(list) do
        if i > 6 then
            log("    ... %d more", #list - 6)
            break
        end
        local d = m[4] or {}
        local vt = d.virt_text
        local vtl = d.virt_text_pos
        local hl = d.hl_group
        local concise = {}
        if d.end_col then
            concise[#concise + 1] = string.format("%d:%d-%d", m[2] + 1, m[3], d.end_col)
        else
            concise[#concise + 1] = string.format("%d:%d", m[2] + 1, m[3])
        end
        if vt then
            local parts = {}
            for _, p in ipairs(vt) do
                parts[#parts + 1] = p[1]
            end
            concise[#concise + 1] = string.format("virt_text=%q pos=%s", table.concat(parts, "|"), tostring(vtl))
        end
        if hl then
            concise[#concise + 1] = "hl=" .. hl
        end
        if d.conceal then
            concise[#concise + 1] = "conceal=" .. tostring(d.conceal)
        end
        if d.virt_lines then
            concise[#concise + 1] = "virt_lines=" .. #d.virt_lines
        end
        log("    %s", table.concat(concise, " "))
    end
end

-- What loaded markdown-ish modules?
for _, mod in ipairs({
    "render-markdown",
    "snacks.image",
    "snacks.image.latex",
    "markdown-preview",
    "vimtex",
}) do
    local ok = pcall(require, mod)
    log("module %s loaded=%s", mod, tostring(ok))
end

-- Latex-related config as seen at runtime.
for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) then
        local name = vim.api.nvim_buf_get_name(b)
        if name ~= "" and vim.bo[b].filetype == "markdown" then
            log("markdown buffer %d: %s", b, name)
        end
    end
end

local f = assert(io.open("/tmp/mdmath-dump-ns.log", "w"), "cannot open the dump log")
f:write(table.concat(out, "\n"), "\n")
f:close()
print("namespace dump written to /tmp/mdmath-dump-ns.log")
