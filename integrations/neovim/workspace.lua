local M = {}

local app_path = "/Applications/Neovim.app"
local resource_path = app_path .. "/Contents/Resources"
local prepare_picker = resource_path .. "/prepare-yazi-config.zsh"
local picker_active = false

local function find_yazi()
   for _, candidate in ipairs({ "/opt/homebrew/bin/yazi", "/usr/local/bin/yazi" }) do
      if vim.fn.executable(candidate) == 1 then
         return candidate
      end
   end
end

local function read_workspace(cwd_file)
   local file = io.open(cwd_file, "rb")
   if not file then
      return nil
   end

   local directory = file:read("*a") or ""
   file:close()
   vim.fn.delete(cwd_file)
   directory = directory:gsub("%z+$", ""):gsub("%s+$", "")
   return directory ~= "" and directory or nil
end

local function close_picker(tabpage, buffer, previous_showtabline, previous_laststatus)
   if vim.api.nvim_tabpage_is_valid(tabpage) then
      vim.api.nvim_set_current_tabpage(tabpage)
      vim.cmd("tabclose!")
   end
   if buffer and vim.api.nvim_buf_is_valid(buffer) then
      vim.api.nvim_buf_delete(buffer, { force = true })
   end
   if previous_showtabline ~= nil then
      vim.o.showtabline = previous_showtabline
   end
   if previous_laststatus ~= nil then
      vim.o.laststatus = previous_laststatus
   end
   picker_active = false
end

local function remove_picker_config(directory)
   if directory and vim.startswith(vim.fn.fnamemodify(directory, ":t"), "nvim-wezterm-yazi.") then
      vim.fn.delete(directory, "rf")
   end
end

local function prepare_picker_config()
   if vim.fn.executable(prepare_picker) ~= 1 then
      vim.notify("Il preparatore della configurazione Yazi non è presente nell'app", vim.log.levels.ERROR)
      return nil
   end

   local result = vim.system({ prepare_picker }, { text = true }):wait()
   local directory = (result.stdout or ""):gsub("%s+$", "")
   if result.code ~= 0 or directory == "" or vim.fn.isdirectory(directory) ~= 1 then
      vim.notify("Impossibile preparare la configurazione Yazi", vim.log.levels.ERROR)
      return nil
   end

   return directory
end

local function change_workspace(directory)
   local expanded = vim.fn.fnamemodify(vim.fn.expand(directory), ":p"):gsub("/$", "")
   if vim.fn.isdirectory(expanded) ~= 1 then
      vim.notify("Cartella non trovata: " .. expanded, vim.log.levels.ERROR)
      return false
   end

   vim.cmd("cd " .. vim.fn.fnameescape(expanded))
   vim.notify("Workspace: " .. vim.fn.fnamemodify(expanded, ":~"))
   return true
end

local function choose_with_yazi()
   if picker_active then
      return
   end

   local yazi = find_yazi()
   if not yazi then
      vim.notify("Yazi non è installato", vim.log.levels.ERROR)
      return
   end

   local picker_config = prepare_picker_config()
   if not picker_config then
      return
   end

   local cwd_file = vim.fn.tempname()
   local starting_directory = vim.fn.getcwd()
   local previous_showtabline = vim.o.showtabline
   local previous_laststatus = vim.o.laststatus
   picker_active = true
   vim.o.showtabline = 0
   vim.o.laststatus = 0
   vim.cmd("tabnew")
   local picker_tab = vim.api.nvim_get_current_tabpage()
   local picker_buffer = vim.api.nvim_get_current_buf()
   local picker_window = vim.api.nvim_get_current_win()

   local job = vim.fn.jobstart({ yazi, starting_directory, "--cwd-file", cwd_file }, {
      term = true,
      env = { YAZI_CONFIG_HOME = picker_config },
      on_exit = function()
         vim.schedule(function()
            local directory = read_workspace(cwd_file)
            close_picker(picker_tab, picker_buffer, previous_showtabline, previous_laststatus)
            remove_picker_config(picker_config)
            if directory then
               change_workspace(directory)
            end
         end)
      end,
   })

   if job <= 0 then
      vim.fn.delete(cwd_file)
      close_picker(picker_tab, picker_buffer, previous_showtabline, previous_laststatus)
      remove_picker_config(picker_config)
      vim.notify("Impossibile avviare Yazi", vim.log.levels.ERROR)
      return
   end

   vim.bo[picker_buffer].bufhidden = "wipe"
   vim.bo[picker_buffer].filetype = "yazi"
   vim.wo[picker_window].winbar = ""
   pcall(vim.keymap.del, "t", "<Esc>", { buffer = picker_buffer })
   vim.cmd("startinsert")
end

function M.setup()
   pcall(vim.api.nvim_del_user_command, "Workspace")
   vim.api.nvim_create_user_command("Workspace", function(opts)
      if opts.args == "" then
         choose_with_yazi()
      else
         change_workspace(opts.args)
      end
   end, { nargs = "?", complete = "dir", desc = "Cambia workspace nella sessione corrente" })

   vim.keymap.set("n", "<leader>fw", "<cmd>Workspace<CR>", {
      desc = "Cambia workspace con Yazi",
      silent = true,
   })
end

return M
