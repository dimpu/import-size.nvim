local M = {}
local ns_id = vim.api.nvim_create_namespace 'ImportSize'

M.config = {
    private_scopes = { '@byted' },
}

local function extract_package_name(line)
    local pkg = line:match 'from%s+[\'"](.-)[\'"]'
    if pkg then
        return pkg:match '^(@?[^/]+/[^/]+)' or pkg:match '^(@?[^/]+)'
    end
    return nil
end

local function set_virtual_text(buf, row, msg)
    vim.api.nvim_buf_set_extmark(buf, ns_id, row, -1, {
        virt_text = { { ' ' .. msg, 'Comment' } },
        virt_text_pos = 'eol',
    })
end

local function estimate_local_package_size(pkg, callback)
    local path = 'node_modules/' .. pkg
    local cmd = {
        'find',
        path,
        '-type',
        'f',
        '-name',
        '*.js',
        '-or',
        '-name',
        '*.ts',
        '-or',
        '-name',
        '*.json',
        '-exec',
        'du',
        '-b',
        '{}',
        '+',
    }

    vim.fn.jobstart(cmd, {
        stdout_buffered = true,
        on_stdout = function(_, data)
            if not data then
                return
            end
            local total = 0
            for _, line in ipairs(data) do
                local size = tonumber(line:match '^(%d+)')
                if size then
                    total = total + size
                end
            end
            local kb = math.floor(total / 1000)
            callback(string.format('~%d KB (local)', kb))
        end,
        on_stderr = function(_, err)
            if err and #err > 0 then
                callback 'error getting local size'
            end
        end,
    })
end

local function is_local_package(pkg)
    -- Always treat path aliases or known monorepo scopes as local
    if pkg:match '^@/' or pkg:match '^%.?/' then
        return true
    end

    for _, scope in ipairs(M.config.private_scopes) do
        if pkg:match('^' .. vim.pesc(scope)) then
            return true
        end
    end

    return false
end

local function fetch_and_display_size(buf, row, pkg)
    if is_local_package(pkg) then
        estimate_local_package_size(pkg, function(msg)
            set_virtual_text(buf, row, msg)
        end)
        return
    end

    local url = 'https://bundlephobia.com/api/size?package=' .. pkg
    vim.fn.jobstart({ 'curl', '-s', url }, {
        stdout_buffered = true,
        on_stdout = function(_, data)
            if not data then
                return
            end
            local joined = table.concat(data, '')
            local ok, json = pcall(vim.fn.json_decode, joined)
            if ok and json and json.gzip then
                local msg = string.format(
                    '%s KB (gzipped: %s KB)',
                    tostring(json.size / 1000),
                    tostring(json.gzip / 1000)
                )
                set_virtual_text(buf, row, msg)
            else
                set_virtual_text(buf, row, 'Bundlephobia error')
            end
        end,
        on_stderr = function()
            set_virtual_text(buf, row, 'Size fetch failed')
        end,
    })
end

function M.scan_imports()
    local buf = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)

    for i, line in ipairs(lines) do
        local pkg = extract_package_name(line)
        if pkg then
            fetch_and_display_size(buf, i - 1, pkg)
        end
    end
end

function M.setup(user_config)
    M.config = vim.tbl_deep_extend('force', M.config, user_config or {})

    vim.api.nvim_create_autocmd({ 'BufReadPost', 'BufEnter' }, {
        pattern = { '*.ts', '*.tsx', '*.js', '*.jsx' },
        callback = function()
            vim.schedule(function()
                require('import_size').scan_imports()
            end)
        end,
    })
end

return M
