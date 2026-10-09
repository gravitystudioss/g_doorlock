-- Gravity Doorlock - install
-- The resource also creates these tables by itself on start if they are missing.

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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `g_doorlock_groups` (
    `name` VARCHAR(32) NOT NULL,
    `label` VARCHAR(64) NOT NULL,
    PRIMARY KEY (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `g_doorlock_templates` (
    `name` VARCHAR(48) NOT NULL,
    `data` LONGTEXT NOT NULL,
    PRIMARY KEY (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
