local Path = require("plenary.path")
local Utils = require("avante.utils")

local M = {}

---@alias AvantePermissionAction "allow" | "ask" | "deny"

---@param action any
---@return AvantePermissionAction
function M.normalize_action(action)
  if action == "allow" or action == "ask" or action == "deny" then return action end
  return "ask"
end

---@param glob string
---@return string
local function glob_to_lua_pattern(glob)
  -- Escape Lua pattern magic, then expand '*' to '.*'
  local pat = glob:gsub("([%^%$%(%)%%%.%[%]%+%-%?])", "%%%1")
  pat = pat:gsub("%*", ".*")
  return "^" .. pat .. "$"
end

---@param glob string
---@param text string
---@return boolean
local function glob_match(glob, text)
  if glob == "*" then return true end
  local ok, res = pcall(function() return text:match(glob_to_lua_pattern(glob)) ~= nil end)
  return ok and res or false
end

---@param glob string
---@return integer
local function specificity(glob)
  -- Higher = more specific
  local s = glob:gsub("%*", "")
  return #s
end

---@param rules any
---@param text string
---@param default_action AvantePermissionAction
---@return AvantePermissionAction action
---@return string|nil matched
function M.resolve_glob_rules(rules, text, default_action)
  default_action = M.normalize_action(default_action)

  if rules == nil then return default_action, nil end
  if type(rules) == "string" then return M.normalize_action(rules), nil end
  if type(rules) ~= "table" then return default_action, nil end

  -- Support either an array of {pattern=..., action=...} or a map { [pattern]=action }.
  local best_action = default_action
  local best_pattern = nil
  local best_score = -1

  if vim.islist(rules) then
    for _, entry in ipairs(rules) do
      local pat = entry and (entry.pattern or entry[1])
      local act = entry and (entry.action or entry[2])
      if type(pat) == "string" and glob_match(pat, text) then
        local score = specificity(pat)
        if score > best_score then
          best_score = score
          best_action = M.normalize_action(act)
          best_pattern = pat
        end
      end
    end
    return best_action, best_pattern
  end

  for pat, act in pairs(rules) do
    if type(pat) == "string" and glob_match(pat, text) then
      local score = specificity(pat)
      if score > best_score then
        best_score = score
        best_action = M.normalize_action(act)
        best_pattern = pat
      end
    end
  end

  return best_action, best_pattern
end

---@param command string
---@param permission_cfg any
---@return AvantePermissionAction
---@return string|nil
function M.resolve_bash(command, permission_cfg)
  local rules = permission_cfg and permission_cfg.bash
  return M.resolve_glob_rules(rules, command, "ask")
end

---@param abs_path string
---@return "project"|"config"|"external"|"invalid" scope
---@return string|nil err
function M.classify_path(abs_path)
  if type(abs_path) ~= "string" or abs_path == "" then return "invalid", "Invalid path" end
  if not Path:new(abs_path):is_absolute() then return "invalid", "Path is not absolute: " .. abs_path end

  abs_path = vim.fs.normalize(abs_path)

  local project_root = Utils.get_project_root()
  local config_dir = vim.fn.stdpath("config")
  if type(project_root) == "string" then project_root = vim.fs.normalize(project_root) end
  if type(config_dir) == "string" then config_dir = vim.fs.normalize(config_dir) end
  if type(project_root) == "string" and abs_path:sub(1, #project_root) == project_root then return "project", nil end
  if type(config_dir) == "string" and abs_path:sub(1, #config_dir) == config_dir then return "config", nil end
  return "external", nil
end

return M
