-- ════════════════════════════════════════════════════════════════
-- NGO Connect — Patch: Support_LogContact SP
-- Version : v4.9 patch
-- Date    : 2026-07-22
-- Run on  : Railway staging → Railway production
-- ════════════════════════════════════════════════════════════════
-- Phase 1 support: logs user contact submissions to AuditLogs.
-- Includes optional p_AttachmentUrl (public URL of uploaded file).
-- No new tables required.
-- ════════════════════════════════════════════════════════════════

DROP PROCEDURE IF EXISTS Support_LogContact;

DELIMITER //
CREATE PROCEDURE Support_LogContact(
    IN p_UserId         INT UNSIGNED,
    IN p_CategoryCode   VARCHAR(50),
    IN p_Subject        VARCHAR(255),
    IN p_Description    TEXT,
    IN p_ContactEmail   VARCHAR(150),
    IN p_ContactName    VARCHAR(100),
    IN p_IpAddress      VARCHAR(45),
    IN p_AttachmentUrl  VARCHAR(2048)
)
BEGIN
    INSERT INTO AuditLogs (
        UserId,
        Action,
        EntityName,
        EntityId,
        NewValue,
        IpAddress,
        CreatedAt
    )
    VALUES (
        p_UserId,
        'SUPPORT_CONTACT',
        'SupportContact',
        NULL,
        JSON_OBJECT(
            'category',      p_CategoryCode,
            'subject',       p_Subject,
            'description',   p_Description,
            'contactEmail',  p_ContactEmail,
            'contactName',   p_ContactName,
            'attachmentUrl', p_AttachmentUrl
        ),
        p_IpAddress,
        NOW()
    );

    SELECT 1 AS IsSuccess, 'Your message has been sent. We\'ll get back to you shortly.' AS Message;
END //

DELIMITER ;
