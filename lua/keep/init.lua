--定义模块
--最终这个M就是require("keep")得到的模块对象
local M = {}

local default_config = {
    ignore_dirs = {
        "%.git/",
    }
}

local final_config = {}

--@brief:将路径分隔符统一为正斜杠'/',这是为了在进行字符串匹配时,确保无论在哪个操作系统上,匹配模式都能正确工作
--@param path string | nil:需要标准化的路径字符串
--@return string:标准化后的路径字符串,如果输入为nil则返回空字符串
local function normalize_path_separators(path)
    if path then
        --将所有反斜杠替换为正斜杠
        return path:gsub("\\", "/")
    end

    return ""
end

--@brief:获取neovim的state目录下的keep文件夹路径
--@return string:keep文件夹的绝对路径
local function get_state_dir()
    --vim.fn.stdpath("state"):获取neovim的state目录,通常是~/.local/state/nvim(返回的是一个绝对路径)
    --vim.fs.joinpath:确保跨平台路径分隔符正确
    local state_dir = vim.fs.joinpath(vim.fn.stdpath("state"), "keep")
    --创建目录,"p"表示递归创建
    vim.fn.mkdir(state_dir, "p")

    return state_dir
end

--@brief:根据当前工作目录获取会话文件路径
--@return string:会话文件的绝对路径
local function get_session_file()
    --获取当前工作目录(cwd),这是一个绝对路径(neovim启动的路径)
    local cwd = vim.loop.cwd()
    local hash = vim.fn.sha256(cwd)
    local state_dir = get_state_dir()

    return vim.fs.joinpath(state_dir, hash .. ".txt")
end

--@brief:保存当前neovim会话中所有打开的有效文件
function M.save_session()
    --如果是站在.git/里面打开的neovim,那么不保存
    local cwd = vim.loop.cwd()
    local normalized_cwd = normalize_path_separators(cwd)
    for _, dir in ipairs(final_config.ignore_dirs) do
        if normalized_cwd:mathch(dir) then return end
    end

    --如果是站在.git/外面打开的neovim
    --把非.git/里面的buffer标记出来
    --vim.api.nvim_list_bufs():返回的是buf的ID
    local bufs = vim.api.nvim_list_bufs()
    local bufs_pool_a = {}
    for _, buf in ipairs(bufs) do
        local buf_name = vim.api.nvim_buf_get_name(buf)
        local normalized_buf_name = normalize_path_separators(buf_name)
        for _, dir in ipairs(final_config.ignore_dirs) do
            if not normalized_buf_name:match(dir) then
                table.insert(bufs_pool_a, buf_name)
            end
        end
    end
    --如果非.git/里面的buffer数量为0,则不保存
    if #bufs_pool_a == 0 then return end

    local bufs_pool_b = {}
    for _, buf in ipairs(bufs_pool_a) do
        --vim.api.nvim_buf_is_loaded():检查给定ID的缓冲区是否已经被加载到内存中(当前正在编辑或查看的文件)
        local is_loaded = vim.api.nvim_buf_is_loaded(buf)

        --vim.api.nvim_buf_get_option(buf,"buftype"):获取给定缓冲区的buftype选项的值
        --常见的buftype值包括:
        --""(空字符串):普通文件缓冲区(通常编辑的实际文件)
        --nofile:没有关联文件的缓冲区,通常用于scratchpad或临时文本
        --nowrite:缓冲区不能被写入,通常用于帮助文件或只读文件
        --quickfix:快速修复列表
        --prompt:提示缓冲区
        --terminal:终端缓冲区
        --== "":这个条件表示我们只对普通文件缓冲区感兴趣,排除掉那些特殊用途的缓冲区
        local buftype = vim.api.nvim_buf_get_option(buf, "buftype")

        --vim.api.nvim_buf_get_name(buf):获取给定缓冲区的名称(即它所关联的文件路径)
        --有文件路径的才保存(排除掉一些没有明确文件路径的临时缓冲区)
        local name = vim.api.nvim_buf_get_name(buf)

        --筛选条件:已加载,普通文件类型,有文件路径
        if is_loaded and buftype == "" and name ~= "" then
            --files中存储的是文件的绝对路径
            table.insert(bufs_pool_b, name)
        end
    end
    --如果这一轮筛选后,池子里面的buf数量为0,则直接返回
    if #bufs_pool_b == 0 then return end

    --走到这里,就需要真正的写入session记录文件了
    local session_file = get_session_file()
    --"w"表示文本写入模式,lua会自动处理\n和\r\n之间的转换
    local f = io.open(session_file, "w")
    if f then
        --写入第一行为工作目录路径
        cwd = vim.loop.cwd()
        f:write("# " .. cwd .. "\n")

        --逐行写入文件路径
        for _, file in ipairs(bufs_pool_b) do
            f:write(file .. "\n")
        end
        f:close()
    end
end

--@brief:从会话文件中加载并恢复上次打开的文件
function M.load_session()
    local session_file = get_session_file()
    local f = io.open(session_file, "r")
    if not f then
        vim.notify("No session found for this directory.", vim.log.levels.INFO)
        return
    end

    --获取加载会话前,当前buffer的文件路径
    --vim.api.nvim_buf_get_name(0):在没有打开文件时会返回空字符串
    local current_original_path = vim.api.nvim_buf_get_name(0)
    local normalized_current_original_path = normalize_path_separators(current_original_path)

    --收集会话文件中保存的文件路径
    local files = {}
    for line in f:lines() do
        --忽略以#开头的注释行(即第一行写入的cwd信息)
        if not line:match("^#") then
            table.insert(files, line)
        end
    end
    f:close()

    --打印记录的数量
    vim.notify("Session contains " .. #files .. " records.", vim.log.levels.INFO)

    for _, file in ipairs(files) do
        --标准化以避免因分隔符差异导致误判
        local normalized_file = normalize_path_separators(file)

        --确保要打开的文件不是当前已经打开的缓冲区,并且文件实际可读
        --vim.fn.filereadable(file) == 1:检查给定路径的文件是否可读(避免尝试打开一个已经不存在或没有权限访问的文件),1:表示可读,0:表示不可读
        if normalized_file ~= normalized_current_original_path and vim.fn.filereadable(file) == 1 then
            --vim.fn.fnameescape(file):用于转义文件路径中的特殊字符(如空格,%,#等),使其能够安全地作为neovim命令的参数,如果没有这个转义,包含特殊字符的文件路径可能会导致命令解析错误
            vim.cmd("edit " .. vim.fn.fnameescape(file))
        end
    end

    --如果neovim是通过指定文件启动的(例如nvim file.txt),在加载会话后焦点可能切换到了其他文件,则切换回原始文件
    if current_original_path ~= "" then
        --再次获取当前活跃buffer的文件路径,以检查加载会话后焦点是否变化
        local current_after_load = vim.api.nvim_buf_get_name(0)
        --比较路径时进行标准化
        local normalized_current_after_load = normalize_path_separators(current_after_load)
        local normalized_current_original_path_again = normalize_path_separators(current_original_path)

        --如果当前焦点不在原始启动文件上,则切换回去
        if normalized_current_original_path_again ~= normalized_current_after_load then
            --获取原始文件的缓冲区ID
            local target_buf_id = vim.fn.bufnr(current_original_path)

            --检查目标文件是否仍然存在且可读,并且缓冲区ID有效
            if vim.fn.filereadable(current_original_path) == 1
                and target_buf_id >= 0
                and vim.api.nvim_buf_is_valid(target_buf_id) then
                --vim.api.nvim_set_current_buf:直接切换缓冲区
                vim.api.nvim_set_current_buf(target_buf_id)
                vim.notify("Set focus back to: " .. current_original_path, vim.log.levels.INFO)
            else
                vim.notify(
                    "Could not set focus back to file: "
                    .. current_original_path
                    .. " (file not readable or buffer invalid).",
                    vim.log.levels.WARN
                )
            end
        end
    end

    --vim.notify("Session restored (" .. #files .. " files).", vim.log.levels.INFO)
end

--@brief:插件设置函数,用于创建自动命令和键位映射
function M.setup(user_opts)
    --合并用户配置与默认配置
    --force:当键冲突时,使用后面的表值覆盖前面的,如果后面的表是空的,就没有冲突,则什么都不覆盖
    --user_opts or {}:如果用户没有传任何参数(即nil),就用空表{}避免报错
    final_config = vim.tbl_deep_extend("force", default_config, user_opts or {})

    --创建自动命令:在退出neovim之前(VimLeavePre事件)触发save_session()
    vim.api.nvim_create_autocmd("VimLeavePre", {
        callback = M.save_session,
    })

    --设置键位映射:在普通模式下按下<space>ls恢复会话
    vim.keymap.set("n", "<space>ls", M.load_session, { desc = "Restore session" })
end

--返回模块表M,供require("keep")使用
return M
