local M = {}

local config = {
  ssh_config_path = vim.fn.expand("~/.ssh/config"),
  remote_nvim_path = "~/.local/share/nvim",
  sync_interval = 300,
}

function M.setup(opts)
  config = vim.tbl_deep_extend("force", config, opts or {})
end

local function parse_ssh_hosts()
  local config_path = vim.fn.expand(config.ssh_config_path)
  if vim.fn.filereadable(config_path) ~= 1 then
    vim.notify("SSH config not found: " .. config_path, vim.log.levels.ERROR)
    return {}
  end

  local content = vim.fn.readfile(config_path)
  local hosts = {}
  local current_host = nil

  for _, line in ipairs(content) do
    if line:match("^Host%s") then
      current_host = line:match("^Host%s+(%S+)")
      hosts[current_host] = { options = {} }
    elseif current_host and line:match("%S") then
      local key, value = line:match("^%s*(%S+)%s+(.+)$")
      if key and value then
        hosts[current_host].options[key:lower()] = value
      end
    end
  end

  return hosts
end

local function execute_remote(host, cmd)
  local ssh_cmd = string.format(
    "ssh -p %s %s@%s '%s'",
    host.options.port or 22,
    host.options.user or "root",
    host.options.hostname,
    cmd
  )

  return vim.fn.system(ssh_cmd)
end

function M.connect()
  local hosts = parse_ssh_hosts()
  local choices = vim.tbl_keys(hosts)

  vim.ui.select(choices, {
    prompt = "Select SSH host:",
    format_item = function(item)
      return string.format("%s (%s)", item, hosts[item].options.hostname)
    end,
  }, function(choice)
    if choice then
      local host = hosts[choice]

      -- Check Neovim installation
      local nvim_check = execute_remote(host, "which nvim")
      if nvim_check == "" then
        -- will handle it later
        print("nvim not found on server")
      end

      -- Sync plugins
      local sync_cmd = string.format(
        "rsync -az %s/.local/share/nvim/site/ %s:%s/site/",
        vim.env.HOME,
        host.options.hostname,
        config.remote_nvim_path
      )
      vim.fn.system(sync_cmd)

      -- Launch remote session
      vim.cmd(
        string.format(
          "terminal ssh -t %s@%s 'NVIM_APPNAME=remote-nvim nvim'",
          host.options.user or "root",
          host.options.hostname
        )
      )
    end
  end)
end

function M.add_ssh_config(host, hostname, user, port)
  local config_path = vim.fn.expand(config.ssh_config_path)
  local file = io.open(config_path, "a")
  if file then
    file:write(string.format("\nHost %s\n", host))
    file:write(string.format("  HostName %s\n", hostname))
    file:write(string.format("  User %s\n", user))
    file:write(string.format("  Port %s\n", port or 22))
    file:close()
    vim.notify("SSH config added for host: " .. host, vim.log.levels.INFO)
  else
    vim.notify("Failed to open SSH config file: " .. config_path, vim.log.levels.ERROR)
  end
end

--  Command
vim.api.nvim_create_user_command("RemoteSSHConnect", function()
  require("remote-ssh").connect()
end, {})

vim.api.nvim_create_user_command("RemoteSSHAddSSHConfig", function(opts)
  local args = vim.split(opts.args, " ")
  if #args < 3 then
    vim.notify("Usage: AddSSHConfig <host> <hostname> <user> [port]", vim.log.levels.ERROR)
    return
  end
  require("remote-ssh").add_ssh_config(args[1], args[2], args[3], args[4])
end, { nargs = "*" })
return M
