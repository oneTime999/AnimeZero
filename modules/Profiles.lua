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

    if AutoSave.Available then
        SaveManager:SetLibrary(Fluent)
        SaveManager:SetFolder("PcdFnlBossV11")
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
        InterfaceManager:SetFolder("PcdFnlBossInterface")
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
            local path = SaveManager.Folder .. "/settings/" .. AutoSave.Name .. ".json"
            if isfile(path) then
                pcall(function() SaveManager:Load(AutoSave.Name) end)
            else
                pcall(function() SaveManager:LoadAutoloadConfig() end)
            end
            task.wait(0.9)

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
