DB = {}

-- tables from the old gravity_doorlock name are renamed once
local function renameOld()
    for _, suffix in ipairs({ '', '_templates', '_groups' }) do
        local old, new = 'gravity_doorlock' .. suffix, 'g_doorlock' .. suffix
        local found = MySQL.query.await([[
            SELECT TABLE_NAME FROM information_schema.TABLES
            WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME IN (?, ?)
        ]], { old, new }) or {}
        if #found == 1 and found[1].TABLE_NAME == old then
            MySQL.query.await(('RENAME TABLE `%s` TO `%s`'):format(old, new))
            print(('[g_doorlock] table %s renamed to %s'):format(old, new))
        end
    end
end

function DB.ensureSchema()
    renameOld()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `g_doorlock` (
            `id` VARCHAR(64) NOT NULL,
            `data` LONGTEXT NOT NULL,
            `pin_hash` VARCHAR(255) NULL DEFAULT NULL,
            `state` TINYINT(1) NULL DEFAULT NULL,
            `state_rev` BIGINT UNSIGNED NOT NULL DEFAULT 0,
            `rev` INT UNSIGNED NOT NULL DEFAULT 1,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `g_doorlock_templates` (
            `name` VARCHAR(48) NOT NULL,
            `data` LONGTEXT NOT NULL,
            PRIMARY KEY (`name`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `g_doorlock_groups` (
            `name` VARCHAR(32) NOT NULL,
            `label` VARCHAR(64) NOT NULL,
            PRIMARY KEY (`name`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
end

function DB.loadAll()
    return MySQL.query.await('SELECT `id`, `data`, `pin_hash`, `state`, `state_rev`, `rev` FROM `g_doorlock`') or {}
end

function DB.saveDoor(door, rev, pinHash)
    local data = json.encode(door)
    if pinHash == nil then
        return MySQL.update.await([[
            INSERT INTO `g_doorlock` (`id`, `data`, `rev`) VALUES (?, ?, ?)
            ON DUPLICATE KEY UPDATE `data` = VALUES(`data`), `rev` = VALUES(`rev`)
        ]], { door.id, data, rev })
    end
    return MySQL.update.await([[
        INSERT INTO `g_doorlock` (`id`, `data`, `rev`, `pin_hash`) VALUES (?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE `data` = VALUES(`data`), `rev` = VALUES(`rev`), `pin_hash` = VALUES(`pin_hash`)
    ]], { door.id, data, rev, pinHash or nil })
end

function DB.deleteDoor(id)
    return MySQL.update.await('DELETE FROM `g_doorlock` WHERE `id` = ?', { id })
end

function DB.saveState(id, locked, stateRev)
    MySQL.update('UPDATE `g_doorlock` SET `state` = ?, `state_rev` = ? WHERE `id` = ? AND `state_rev` < ?',
        { locked and 1 or 0, stateRev, id, stateRev })
end

function DB.clearState(id)
    MySQL.update('UPDATE `g_doorlock` SET `state` = NULL WHERE `id` = ?', { id })
end

function DB.loadGroups()
    return MySQL.query.await('SELECT `name`, `label` FROM `g_doorlock_groups`') or {}
end

function DB.saveGroup(name, label)
    MySQL.update.await('INSERT INTO `g_doorlock_groups` (`name`, `label`) VALUES (?, ?) ON DUPLICATE KEY UPDATE `label` = VALUES(`label`)', { name, label })
end

function DB.deleteGroup(name)
    MySQL.update.await('DELETE FROM `g_doorlock_groups` WHERE `name` = ?', { name })
end

function DB.loadTemplates()
    return MySQL.query.await('SELECT `name`, `data` FROM `g_doorlock_templates`') or {}
end

function DB.saveTemplate(name, data)
    MySQL.update.await('INSERT INTO `g_doorlock_templates` (`name`, `data`) VALUES (?, ?) ON DUPLICATE KEY UPDATE `data` = VALUES(`data`)', { name, data })
end

function DB.deleteTemplate(name)
    MySQL.update.await('DELETE FROM `g_doorlock_templates` WHERE `name` = ?', { name })
end
