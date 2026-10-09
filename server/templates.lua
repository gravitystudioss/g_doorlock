-- saved permission sets ("Police grade 2+") that can be applied to doors in the editor

Templates = { list_ = {} } -- name -> access

-- run the access through the door validation with a dummy door
local function cleanAccess(access)
    local door, err = DoorSchema.normalize({
        id = 'template', type = 'single', access = access,
        doors = { { model = 1, coords = { x = 0, y = 0, z = 0 } } },
    })
    if not door then return nil, err end
    door.access.pin = false -- a template never carries a PIN
    return door.access
end

function Templates.load()
    for _, row in ipairs(DB.loadTemplates()) do
        local ok, data = pcall(json.decode, row.data)
        local access = ok and cleanAccess(data)
        if access then Templates.list_[row.name] = access end
    end
end

function Templates.list()
    local out = {}
    for name, access in pairs(Templates.list_) do
        out[#out + 1] = { name = name, access = access }
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

function Templates.get(name)
    return Templates.list_[name] and Utils.deepCopy(Templates.list_[name]) or nil
end

function Templates.save(name, access)
    if type(name) ~= 'string' then return false, 'err_invalid_data' end
    name = name:match('^%s*(.-)%s*$')
    if name == '' or #name > 48 then return false, 'err_invalid_data' end
    local clean, err = cleanAccess(access)
    if not clean then return false, err end
    if not DoorSchema.hasCriteria(clean) then return false, 'err_no_criteria' end
    Templates.list_[name] = clean
    DB.saveTemplate(name, json.encode(clean))
    return true
end

function Templates.delete(name)
    if type(name) ~= 'string' or not Templates.list_[name] then return end
    Templates.list_[name] = nil
    DB.deleteTemplate(name)
end
