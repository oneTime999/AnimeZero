-- Optional developer test host.
-- New feature modules can add entries to ctx.DeveloperTests before this module
-- is loaded. No registered tests means no Developer tab in the interface.
return function(ctx)
    local guard = ctx.GameGuard
    if not guard or not guard.IsDeveloper() then return end

    local pending = ctx.DeveloperTests
    if type(pending) ~= "table" or #pending == 0 then return end

    local tests = {}
    for _, item in ipairs(pending) do
        if type(item) == "table"
            and type(item.Title) == "string" and item.Title ~= ""
            and type(item.Run) == "function" then
            table.insert(tests, item)
        end
    end
    if #tests == 0 then return end

    local fluent, window = ctx.Fluent, ctx.Window
    if not fluent or not window then return end
    local tab = window:AddTab({Title = "Developer", Icon = "flask-conical"})
    tab:AddSection("Experimental Features")

    for _, test in ipairs(tests) do
        tab:AddButton({
            Title = test.Title,
            Description = type(test.Description) == "string"
                and test.Description or "Test an experimental feature",
            Callback = function()
                if not guard.IsDeveloper() then return end
                task.spawn(function()
                    local success, ok, message = pcall(test.Run, ctx)
                    if not success then
                        warn("[Slow Hub Dev] " .. tostring(ok))
                        fluent:Notify({
                            Title = "Feature Test",
                            Content = "Test failed. Check the executor console.",
                            Duration = 6
                        })
                        return
                    end
                    if message ~= nil then
                        fluent:Notify({
                            Title = ok == false and "Feature Test Failed" or "Feature Test",
                            Content = tostring(message),
                            Duration = 6
                        })
                    end
                end)
            end
        })
    end

    ctx.DeveloperTab = tab
end
