Editor = { open = false, selecting = false, preview = nil, radius = nil }

local outlined = {}

local function setOutline(ent, on)
    if not ent or ent == 0 or not DoesEntityExist(ent) then return end
    SetEntityDrawOutline(ent, on)
    if on then outlined[ent] = true else outlined[ent] = nil end
end

local function clearOutlines()
    for ent in pairs(outlined) do
        if DoesEntityExist(ent) then SetEntityDrawOutline(ent, false) end
    end
    outlined = {}
end

local function startPreviewThread()
    CreateThread(function()
        while Editor.open and Editor.preview do
            local leaves = Editor.preview
            local r = Editor.radius
            if r then
                -- rings on the ground: interaction (purple) and automatic opening (cyan)
                local cx, cy, cz = Utils.doorCenter({ doors = leaves })
                if r.interact and r.interact > 0 then
                    DrawMarker(1, cx, cy, cz - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, r.interact * 2, r.interact * 2, 0.4,
                        154, 92, 240, 70, false, false, 2, false, nil, nil, false)
                end
                if r.auto and r.auto > 0 then
                    DrawMarker(1, cx, cy, cz - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, r.auto * 2, r.auto * 2, 0.25,
                        103, 217, 237, 45, false, false, 2, false, nil, nil, false)
                end
            end
            for i, leaf in ipairs(leaves) do
                local c = leaf.coords
                DrawMarker(2, c.x, c.y, c.z + 1.4, 0.0, 0.0, 0.0, 180.0, 0.0, 0.0, 0.25, 0.25, 0.25,
                    124, 92, 255, 200, true, true, 2, false, nil, nil, false)
                DrawMarker(28, c.x, c.y, c.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.12, 0.12, 0.12,
                    255, 255, 255, 180, false, false, 2, false, nil, nil, false)
                if i == 2 then
                    local a = leaves[1].coords
                    DrawLine(a.x, a.y, a.z + 1.0, c.x, c.y, c.z + 1.0, 124, 92, 255, 255)
                end
            end
            Wait(0)
        end
    end)
end

function Editor.setPreview(leaves, radius)
    Editor.radius = radius
    local wasRunning = Editor.preview ~= nil
    if type(leaves) == 'table' and #leaves > 0 then
        Editor.preview = leaves
        if not wasRunning then startPreviewThread() end
    else
        Editor.preview = nil
    end
end

function Editor.openMenu()
    if Editor.open then return end
    local data = lib.callback.await('g_doorlock:admin:open', false)
    if not data then
        Notify(L('no_permission'), 'error')
        return
    end
    Editor.open = true
    Nui.send('editor:open', data)
    Nui.setFocus('editor')
end

function Editor.close()
    Editor.selecting = false
    Editor.open = false
    Editor.preview = nil
    clearOutlines()
    Nui.send('editor:close', {})
    Nui.send('selection', { show = false })
    if Nui.focus == 'editor' then Nui.setFocus(nil) end
end

local function sameLeaf(a, b)
    return a.model == b.model and #(vector3(a.coords.x, a.coords.y, a.coords.z) - vector3(b.coords.x, b.coords.y, b.coords.z)) < 0.05
end

-- min/max leaves: single 1/1, double 2/2, gate 1/2 (enter finishes early)
function Editor.startSelection(min, max)
    if Editor.selecting then return end
    Editor.selecting = true
    Editor.preview = nil
    Nui.setFocus(nil)
    Nui.send('editor:hide', {})

    local picked = {}
    local hovered = 0
    SetEntityDrawOutlineColor(124, 92, 255, 255)
    SetEntityDrawOutlineShader(1)

    CreateThread(function()
        local result = nil
        local lastText, lastHint
        while Editor.selecting do
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            DisableControlAction(0, 140, true)
            DisableControlAction(0, 200, true)

            local hit, ent = lib.raycast.fromCamera(17, 4, 30.0)
            if not hit or not ent or ent == 0 or GetEntityType(ent) ~= 3 then ent = 0 end

            if ent ~= hovered then
                local wasPicked = false
                for _, p in ipairs(picked) do
                    if p.entity == hovered then wasPicked = true end
                end
                if not wasPicked then setOutline(hovered, false) end
                hovered = ent
                if ent ~= 0 then setOutline(ent, true) end
            end

            local text = L('sel_leaf', #picked + 1, max)
            local hint = (#picked >= min and L('sel_finish')) or (ent == 0 and L('sel_not_door')) or nil
            if text ~= lastText or hint ~= lastHint then
                lastText, lastHint = text, hint
                Nui.send('selection', { show = true, text = text, hint = hint })
            end

            for _, p in ipairs(picked) do
                local c = p.coords
                DrawMarker(2, c.x, c.y, c.z + 1.4, 0.0, 0.0, 0.0, 180.0, 0.0, 0.0, 0.25, 0.25, 0.25,
                    124, 92, 255, 220, true, true, 2, false, nil, nil, false)
            end

            if IsControlJustPressed(0, 38) and ent ~= 0 then
                local pos = GetEntityCoords(ent)
                local leaf = {
                    entity = ent,
                    model = GetEntityModel(ent),
                    coords = { x = pos.x, y = pos.y, z = pos.z },
                    heading = GetEntityHeading(ent),
                }
                local dup = false
                for _, p in ipairs(picked) do
                    if p.entity == ent or sameLeaf(p, leaf) then dup = true end
                end
                if dup then
                    Notify(L('sel_already'), 'error')
                else
                    picked[#picked + 1] = leaf
                    if #picked >= max then
                        result = picked
                        Editor.selecting = false
                    end
                end
            elseif #picked >= min and (IsControlJustPressed(0, 191) or IsControlJustPressed(0, 201)) then
                result = picked
                Editor.selecting = false
            elseif IsControlJustPressed(0, 177) or IsDisabledControlJustPressed(0, 200) then
                Editor.selecting = false
            end
            Wait(0)
        end

        clearOutlines()
        Nui.send('selection', { show = false })

        if not Editor.open then return end

        local leaves = nil
        if result then
            leaves = {}
            for i, p in ipairs(result) do
                leaves[i] = { model = p.model, coords = p.coords, heading = p.heading }
            end
            Notify(L('sel_done'), 'success')
            Editor.setPreview(leaves)
        else
            Notify(L('sel_cancel'), 'info')
        end
        Nui.send('editor:show', { leaves = leaves })
        Nui.setFocus('editor')
    end)
end

local function forward(name, cbName, getArgs)
    RegisterNUICallback(name, function(data, cb)
        local args = getArgs(type(data) == 'table' and data or {})
        cb(lib.callback.await(cbName, false, table.unpack(args)) or false)
    end)
end

forward('editor:save', 'g_doorlock:admin:save', function(d) return { d } end)
forward('editor:delete', 'g_doorlock:admin:delete', function(d) return { d.id } end)
forward('editor:setState', 'g_doorlock:admin:setState', function(d) return { d.id, d.locked == true } end)
forward('editor:export', 'g_doorlock:admin:export', function(d) return { d.ids } end)
forward('editor:import', 'g_doorlock:admin:import', function(d) return { d.text, d.overwrite == true } end)
forward('editor:identifier', 'g_doorlock:admin:identifier', function(d) return { d.target } end)
forward('editor:reload', 'g_doorlock:admin:open', function() return {} end)
forward('editor:migrate', 'g_doorlock:admin:migrate', function(d) return { d.from, d.overwrite == true } end)
forward('editor:restore', 'g_doorlock:admin:restore', function(d) return { d.id } end)
forward('editor:bulk', 'g_doorlock:admin:bulk', function(d) return { d.ids, d.patch } end)
forward('editor:templateSave', 'g_doorlock:admin:templateSave', function(d) return { d.name, d.access } end)
forward('editor:templateDelete', 'g_doorlock:admin:templateDelete', function(d) return { d.name } end)
forward('editor:importPack', 'g_doorlock:admin:importPack', function(d) return { d.file, d.overwrite == true } end)
forward('editor:groupSave', 'g_doorlock:admin:groupSave', function(d) return { d.name, d.label } end)
forward('editor:groupDelete', 'g_doorlock:admin:groupDelete', function(d) return { d.name } end)
forward('editor:groupState', 'g_doorlock:admin:groupState', function(d) return { d.name, d.locked == true } end)

RegisterNUICallback('editor:goto', function(data, cb)
    local ok = lib.callback.await('g_doorlock:admin:goto', false, data.id)
    cb(ok == true)
end)

RegisterNUICallback('editor:select', function(data, cb)
    cb(true)
    local max = tonumber(data.max) == 2 and 2 or 1
    local min = tonumber(data.min) == 2 and 2 or 1
    if min > max then min = max end
    Editor.startSelection(min, max)
end)

-- nearest saved door within 5 m
RegisterNUICallback('editor:nearest', function(_, cb)
    local pos = GetEntityCoords(PlayerPedId())
    local best, bestDist
    for _, door in ipairs(ClientDoors.nearby(pos, 5.0)) do
        local dist = #(pos - door.center)
        if not bestDist or dist < bestDist then best, bestDist = door, dist end
    end
    cb(best and best.id or false)
end)

RegisterNUICallback('editor:preview', function(data, cb)
    cb(true)
    Editor.setPreview(data.leaves, { interact = tonumber(data.interact), auto = tonumber(data.auto) })
end)

RegisterNUICallback('editor:copy', function(data, cb)
    cb(true)
    if type(data.text) == 'string' then lib.setClipboard(data.text) end
end)

RegisterNetEvent('g_doorlock:openEditor', function()
    Editor.openMenu()
end)
