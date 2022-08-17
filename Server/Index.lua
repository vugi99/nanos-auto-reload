

Package.Require("Config.lua")

local packages_script_files = {}
local Scanning = false

function table_count(ta)
    local count = 0
    for k, v in pairs(ta) do count = count + 1 end
    return count
end

function split_str(str,sep)
    local sep, fields = sep or ":", {}
    local pattern = string.format("([^%s]+)", sep)
    str:gsub(pattern, function(c) fields[#fields+1] = c end)
    return fields
end

function split_lines(str)
    lines = {}
    for s in str:gmatch("[^\r\n]+") do
        table.insert(lines, s)
    end
    return lines
end

function IsBlacklistedDirectory(name)
    if string.sub(name, 1, 1) == "." then
        return true
    end
    return false
end

function GetFileExtension(filename)
    local split = split_str(filename, ".")
    if split[2] then
        return split[table_count(split)]
    else
        return ""
    end
end

function IsScriptFileExtension(extension)
    for i, v in ipairs(Script_Extensions) do
        if v == extension then
            return true
        end
    end
    return false
end

function GetDirectories(directory)
    local directories = io.popen("cd " .. directory .. " && dir /b /a:d")
    local splited_dirs = split_lines(directories:read("*a"))
    return splited_dirs
end

function GetFiles(directory)
    local files = io.popen("cd " .. directory .. " && dir /b /a:-d")
    local splited_files = split_lines(files:read("*a"))
    return splited_files
end

function UpdateFilesInDirectory(package_name, directory)
    local updated_file = false

    local files = GetFiles(directory)
    --print("directory", directory)
    for k, v in pairs(files) do
        --print(v)
        local extension = GetFileExtension(v)
        if IsScriptFileExtension(extension) then
            local file_last_modified = File.Time(directory .. "/" .. v)
            if file_last_modified then
                local stored_file_last_modified = packages_script_files[package_name][directory .. "/" .. v]
                if (not stored_file_last_modified or file_last_modified ~= stored_file_last_modified) then
                    packages_script_files[package_name][directory .. "/" .. v] = file_last_modified
                    updated_file = true
                end
            else
                print("Can't read last modified time for " .. v)
            end
        end
    end

    local KeysToRemove = {}

    for k, v in pairs(packages_script_files[package_name]) do
        local split_dir = split_str(k, "/")
        local dir_wo_end = ""
        local split_count = table_count(split_dir)
        local file_name = split_dir[split_count]
        for i2, v2 in ipairs(split_dir) do
            if i2 < split_count then
                if i2 == split_count - 1 then
                    dir_wo_end = dir_wo_end .. v2
                else
                    dir_wo_end = dir_wo_end .. v2 .. "/"
                end
            end
        end

        if dir_wo_end == directory then
            local found = false

            for k2, v2 in pairs(files) do
                if v2 == file_name then
                    found = true
                end
            end

            if not found then
                table.insert(KeysToRemove, k)
                updated_file = true
            end
        end
    end

    for i, v in ipairs(KeysToRemove) do
        packages_script_files[package_name][v] = nil
        --print("File Removed")
    end

    return updated_file
end

function UpdateDirectory(package_name, directory)
    local updated_file = UpdateFilesInDirectory(package_name, directory)

    local directories = GetDirectories(directory)
    for k, v in pairs(directories) do
        if not IsBlacklistedDirectory(v) then
            local updated = UpdateDirectory(package_name, directory .. "/" .. v)
            if updated then
                updated_file = true
            end
        end
    end

    local KeysToRemove = {}

    for k, v in pairs(packages_script_files[package_name]) do
        local split_dir = split_str(k, "/")
        local dir_wo_end = ""
        local split_count = table_count(split_dir)
        local dir_end = split_dir[split_count - 1]
        for i2, v2 in ipairs(split_dir) do
            if i2 < split_count - 1 then
                if i2 == split_count - 2 then
                    dir_wo_end = dir_wo_end .. v2
                else
                    dir_wo_end = dir_wo_end .. v2 .. "/"
                end
            end
        end

        if dir_wo_end == directory then
            local found = false

            for k2, v2 in pairs(directories) do
                if v2 == dir_end then
                    found = true
                end
            end

            if not found then
                table.insert(KeysToRemove, k)
                updated_file = true
            end
        end
    end

    for i, v in ipairs(KeysToRemove) do
        packages_script_files[package_name][v] = nil
        --print("Folder Removed")
    end

    return updated_file
end

Package.Subscribe("Load", function()
    Scanning = true

    for k, v in pairs(Server.GetPackages(true)) do
        if v ~= Package.GetPath() then
            packages_script_files[v] = {}
            UpdateDirectory(v, "Packages/" .. v)
        end
    end

    Scanning = false

    Timer.SetInterval(function()
        if not Scanning then
            Scanning = true

            for k, v in pairs(Server.GetPackages(true)) do
                if v ~= Package.GetPath() then
                    local updated = UpdateDirectory(v, "Packages/" .. v)
                    if updated then
                        print("Updated package detected " .. v .. ", reloading package")
                        Server.ReloadPackage(v)
                    end
                end
            end

            Scanning = false
        end
    end, ScanFiles_Interval)
end)