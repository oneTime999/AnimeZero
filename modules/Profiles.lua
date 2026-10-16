return function(ctx)
    local S = ctx.S
    local Fluent, Profiles, Window = ctx.Fluent, ctx.Profiles, ctx.Window
    local SaveManager = Fluent.SaveManager
    local InterfaceManager = Fluent.InterfaceManager
    local AutoSave = {
        Available = SaveManager ~= nil and SaveManager.FileSystemAvailable == true,
        Ready = false,
        Dirty = false,
        LastChange = 0,
        Name = "Autosave"
    }

    -- Everything is saved under:  Slow Hub / Anime Zero
    --   settings/Autosave.json  -> the options you turned on
    --   options.json            -> interface options (theme, etc.)
    local FOLDER = "Slow Hub/Anime Zero"
    local OLD_SETTINGS_FOLDER = "PcdFnlBossV11"
    local OLD_INTERFACE_FOLDER = "PcdFnlBossInterface"

    local function safeCall(fn, ...)
        if type(fn) ~= "function" then return false, nil end
        return pcall(fn, ...)
    end

    local function pathExists(path)
        local ok, exists = safeCall(isfile, path)
        if ok and exists == true then return true end
        ok, exists = safeCall(isfolder, path)
        return ok and exists == true
    end

    local function ensureFolder(path)
        if type(makefolder) ~= "function" or pathExists(path) then return end
        pcall(makefolder, path)
    end

    -- Copies a file from the old location, only if the new one does not exist yet,
    -- so nothing you saved before is lost.
    local function migrateFile(oldPath, newPath)
        if type(readfile) ~= "function" or type(writefile) ~= "function" then return end
        if pathExists(newPath) or not pathExists(oldPath) then return end
        local ok, content = pcall(readfile, oldPath)
        if ok and type(content) == "string" then
            pcall(writefile, newPath, content)
        end
    end

    ensureFolder("Slow Hub")
    ensureFolder(FOLDER)
    ensureFolder(FOLDER .. "/settings")

    if AutoSave.Available then
        migrateFile(OLD_SETTINGS_FOLDER .. "/settings/" .. AutoSave.Name .. ".json",
            FOLDER .. "/settings/" .. AutoSave.Name .. ".json")
        migrateFile(OLD_SETTINGS_FOLDER .. "/settings/behind-default-v1.txt",
            FOLDER .. "/settings/behind-default-v1.txt")
        SaveManager:SetLibrary(Fluent)
        SaveManager:SetFolder(FOLDER)
        Profiles:AddParagraph({
            Title = "Automatic Saving",
            Content = "Settings are saved automatically."
        })
    else
        Profiles:AddParagraph({
            Title = "Saving Unavailable",
            Content = "Saving is unavailable on this device."
        })
    end

    if InterfaceManager and InterfaceManager.FileSystemAvailable then
        InterfaceManager:SetLibrary(Fluent)
        migrateFile(OLD_INTERFACE_FOLDER .. "/options.json", FOLDER .. "/options.json")
        InterfaceManager:SetFolder(FOLDER)
        InterfaceManager:BuildInterfaceSection(Profiles)
    end

    Window:SelectTab(1)

    if AutoSave.Available then
        for id, option in pairs(Fluent.Options) do
            if type(id) == "string"
                and type(option.OnChanged) == "function" then
                option:OnChanged(function()
                    if AutoSave.Ready then
                        AutoSave.Dirty = true
                        AutoSave.LastChange = os.clock()
                    end
                end)
            end
        end

        task.spawn(function()
            local fileExists = pathExists

            local path = SaveManager.Folder .. "/settings/" .. AutoSave.Name .. ".json"
            if fileExists(path) then
                pcall(function() SaveManager:Load(AutoSave.Name) end)
            else
                pcall(function() SaveManager:LoadAutoloadConfig() end)
            end
            task.wait(0.9)

            -- One-time migration: an older autosave may still set Below,
            -- even though the original default has been restored to Behind.
            local migrationPath = SaveManager.Folder .. "/settings/behind-default-v1.txt"
            local positionOption = Fluent.Options and Fluent.Options.V11_Position
            if not fileExists(migrationPath) then
                local migrated = true
                if positionOption and positionOption.Value == "Below" then
                    positionOption:SetValue("Behind")
                    local ok, saved = pcall(function()
                        return SaveManager:Save(AutoSave.Name)
                    end)
                    migrated = ok and saved == true
                end
                if migrated then
                    if type(writefile) == "function" then
                        pcall(writefile, migrationPath, "1")
                    end
                end
            end

            AutoSave.Ready = true
        end)

        task.spawn(function()
            while S.Alive and not Fluent.Unloaded do
                task.wait(0.4)
                if AutoSave.Ready and AutoSave.Dirty
                    and os.clock() - AutoSave.LastChange >= 1 then
                    local ok, success = pcall(function()
                        return SaveManager:Save(AutoSave.Name)
                    end)
                    if ok and success then
                        AutoSave.Dirty = false
                    else
                        AutoSave.LastChange = os.clock()
                    end
                end
            end
        end)
    end

    ctx.AutoSave = AutoSave
    ctx.SaveManager = SaveManager
    ctx.InterfaceManager = InterfaceManager
end
