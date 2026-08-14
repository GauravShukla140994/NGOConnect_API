-- ============================================================
-- patch_seed_missing_settings.sql
-- Seeds all settings and LookupValues required by
-- NGOConnect_ProjectFlow_Requirements_v1.1.docx §5.4 and §5.5
-- that were missing from or incorrectly valued in the DB.
--
-- Run on: local → Railway staging → Railway production
-- Safe to re-run: INSERT IGNORE skips existing rows.
-- ============================================================

-- ============================================================
-- PART 1: Fix wrong values on existing settings
-- ============================================================

-- FLEXIBLE_MAX_DURATION_DAYS was seeded as 90; doc spec is 60
UPDATE Settings SET SettingValue = '60',
    Description = 'Max calendar days a FLEXIBLE project can span'
WHERE SettingKey = 'FLEXIBLE_MAX_DURATION_DAYS' AND SettingValue = '90';

-- SKILL_RATING_WINDOW_DAYS was seeded as 30; doc spec (SESSION_SKILL_RATING_EDIT_DAYS) is 7
UPDATE Settings SET SettingValue = '7'
WHERE SettingKey = 'SKILL_RATING_WINDOW_DAYS' AND SettingValue = '30';

-- ============================================================
-- PART 2: Missing LookupValues (§5.4)
-- ============================================================

-- ATTENDANCE_STATUS / WITHDRAWN — volunteer withdrew from a session (opt-out). No penalty.
INSERT IGNORE INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsActive, IsSystemValue)
SELECT lt.LookupTypeId, 'WITHDRAWN', 'Withdrawn', 6, 1, 1
FROM LookupTypes lt WHERE lt.TypeCode = 'ATTENDANCE_STATUS';

-- NOTIFICATION_TYPE / CHECKOUT_REMINDER — sent 15 min before session end to checked-in FLEXIBLE volunteers
INSERT IGNORE INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsActive, IsSystemValue)
SELECT lt.LookupTypeId, 'CHECKOUT_REMINDER', 'Checkout Reminder', 85, 1, 1
FROM LookupTypes lt WHERE lt.TypeCode = 'NOTIFICATION_TYPE';

-- NOTIFICATION_TYPE / SESSION_CANCELLED — sent to all approved participants when admin cancels a session
INSERT IGNORE INTO LookupValues (LookupTypeId, ValueCode, ValueName, OrderNo, IsActive, IsSystemValue)
SELECT lt.LookupTypeId, 'SESSION_CANCELLED', 'Session Cancelled', 86, 1, 1
FROM LookupTypes lt WHERE lt.TypeCode = 'NOTIFICATION_TYPE';

-- ============================================================
-- PART 3: Missing Settings (§5.5) — 29 doc-spec keys
-- ============================================================

INSERT IGNORE INTO Settings (SettingGroup, SettingKey, SettingValue, DataType, Description, IsPublic) VALUES

-- PROJECT_VALIDATION
('PROJECT', 'OT_MAX_DURATION_HOURS',          '12',          'NUMBER',  'Max hours a ONE_TIME project session can span',                                                                                              0),
('PROJECT', 'RECURRING_MIN_DURATION_DAYS',     '7',           'NUMBER',  'Min calendar days a RECURRING project must span',                                                                                           0),
('PROJECT', 'FLEXIBLE_MIN_DURATION_DAYS',      '3',           'NUMBER',  'Min calendar days a FLEXIBLE project must span',                                                                                            0),

-- ATTENDANCE
('PROJECT', 'FLEXIBLE_MAX_DAILY_HOURS',        '8',           'NUMBER',  'Default max hours a volunteer can log per day on FLEXIBLE projects. Project can override upward.',                                          1),
('PROJECT', 'FLEXIBLE_MIN_SESSION_HOURS',      '1',           'NUMBER',  'Default minimum check-in duration (hours) for a FLEXIBLE session to count toward attendance. Project can override.',                       0),
('PROJECT', 'FLEXIBLE_MIN_ATTEND_PCT',         '70',          'NUMBER',  'Default min attendance % (hours-based) for certificate eligibility on FLEXIBLE projects. Project can override upward.',                    1),
('PROJECT', 'RECURRING_MIN_ATTEND_PCT',        '70',          'NUMBER',  'Default min attendance % (session-based) for certificate eligibility on RECURRING projects. Project can override upward.',                 1),
('PROJECT', 'CHECKIN_BUFFER_MINUTES',          '15',          'NUMBER',  'Minutes before SessionStartTime that check-in window opens. Applies to both RECURRING and FLEXIBLE.',                                      0),
('PROJECT', 'AUTO_CHECKOUT_GRACE_MINUTES',     '30',          'NUMBER',  'Minutes after SessionEndTime before Hangfire auto-marks CHECKED_IN records as CHECKOUT_MISSED.',                                           0),

-- CERTIFICATE
('PROJECT', 'CERT_ISSUE_WINDOW_DAYS',          '14',          'NUMBER',  'Days after project end that admin can manually issue certificates.',                                                                        0),
('PROJECT', 'CERT_AUTO_CLOSE_DAYS',            '21',          'NUMBER',  'Days after CLOSING starts before Hangfire auto-transitions project to COMPLETED (safety net).',                                            0),

-- MILESTONE_NOTIFICATION
('PROJECT', 'MILESTONE_1_PCT',                 '25',          'NUMBER',  'First milestone push-notification threshold (% attendance). Sends once per volunteer per project.',                                        0),
('PROJECT', 'MILESTONE_2_PCT',                 '50',          'NUMBER',  'Second milestone push-notification threshold (% attendance).',                                                                             0),
('PROJECT', 'MILESTONE_3_PCT',                 '75',          'NUMBER',  'Third milestone push-notification threshold (% attendance).',                                                                              0),

-- SKILL_RATING
('PROJECT', 'SESSION_SKILL_RATING_EDIT_DAYS',  '7',           'NUMBER',  'Days after a session date that admin can edit its per-session skill ratings.',                                                             0),
('PROJECT', 'FINAL_SKILL_RATING_EDIT_DAYS',    '14',          'NUMBER',  'Days after CLOSING starts that admin can still enter/edit final skill ratings before Finalize.',                                           0),

-- LIFECYCLE
('PROJECT', 'RECURRING_SESSION_GEN_DAYS',      '7',           'NUMBER',  'Days ahead Hangfire pre-generates sessions for RECURRING projects (rolling window).',                                                      0),
('PROJECT', 'PROJECT_REOPEN_ALLOWED',          '1',           'BOOLEAN', 'Whether FLEXIBLE projects can be reopened from CANCELLED state (1=allowed, 0=blocked).',                                                  0),
('PROJECT', 'CLOSING_SAME_DAY',                '1',           'BOOLEAN', 'Auto-move project to CLOSING on the project end date itself (1=yes, 0=next day).',                                                        0),

-- HANGFIRE_CRON (doc-spec key names; legacy keys kept in DB for current C# wiring)
('HANGFIRE', 'CRON_GENERATE_SESSIONS',         '0 0 * * *',   'STRING',  'Cron: GenerateSessionsJob — daily midnight UTC',                                                                                           0),
('HANGFIRE', 'CRON_AUTO_ACTIVATE',             '0 * * * *',   'STRING',  'Cron: AutoActivateProjectsJob — hourly',                                                                                                   0),
('HANGFIRE', 'CRON_AUTO_COMPLETE_SESSIONS',    '30 * * * *',  'STRING',  'Cron: AutoCompleteSessionsJob — hourly at :30',                                                                                            0),
('HANGFIRE', 'CRON_AUTO_CHECKOUT',             '*/15 * * * *','STRING',  'Cron: AutoCheckoutMissedJob — every 15 min',                                                                                               0),
('HANGFIRE', 'CRON_CHECKOUT_REMINDER',         '*/5 * * * *', 'STRING',  'Cron: CheckoutReminderJob — every 5 min',                                                                                                 0),
('HANGFIRE', 'CRON_AUTO_CLOSING',              '0 1 * * *',   'STRING',  'Cron: TransitionToClosingJob — daily 1:00 AM UTC',                                                                                        0),
('HANGFIRE', 'CRON_MARK_NOSHOW',               '0 2 * * *',   'STRING',  'Cron: MarkNoShowJob — daily 2:00 AM UTC (RECURRING only)',                                                                                 0),
('HANGFIRE', 'CRON_MILESTONE_CHECK',           '0 3 * * *',   'STRING',  'Cron: MilestoneCheckJob — daily 3:00 AM UTC',                                                                                             0),
('HANGFIRE', 'CRON_AUTO_FINALIZE_CLOSING',     '0 4 * * *',   'STRING',  'Cron: AutoFinalizeStaleClosingJob — daily 4:00 AM UTC (safety net)',                                                                       0);

-- ============================================================
-- VERIFICATION QUERY (run after applying to confirm count)
-- ============================================================
-- SELECT COUNT(*) FROM Settings WHERE SettingKey IN (
--   'OT_MAX_DURATION_HOURS','RECURRING_MIN_DURATION_DAYS','FLEXIBLE_MIN_DURATION_DAYS',
--   'FLEXIBLE_MAX_DAILY_HOURS','FLEXIBLE_MIN_SESSION_HOURS','FLEXIBLE_MIN_ATTEND_PCT',
--   'RECURRING_MIN_ATTEND_PCT','CHECKIN_BUFFER_MINUTES','AUTO_CHECKOUT_GRACE_MINUTES',
--   'CERT_ISSUE_WINDOW_DAYS','CERT_AUTO_CLOSE_DAYS',
--   'MILESTONE_1_PCT','MILESTONE_2_PCT','MILESTONE_3_PCT',
--   'SESSION_SKILL_RATING_EDIT_DAYS','FINAL_SKILL_RATING_EDIT_DAYS',
--   'RECURRING_SESSION_GEN_DAYS','PROJECT_REOPEN_ALLOWED','CLOSING_SAME_DAY',
--   'CRON_GENERATE_SESSIONS','CRON_AUTO_ACTIVATE','CRON_AUTO_COMPLETE_SESSIONS',
--   'CRON_AUTO_CHECKOUT','CRON_CHECKOUT_REMINDER','CRON_AUTO_CLOSING',
--   'CRON_MARK_NOSHOW','CRON_MILESTONE_CHECK','CRON_AUTO_FINALIZE_CLOSING'
-- );
-- Expected: 28 rows (FLEXIBLE_MAX_DURATION_DAYS already existed, only value was updated)
