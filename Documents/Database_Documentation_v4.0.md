# NGOConnect Database Documentation v4.0

**Database:** MySQL 8.0+  
**Version:** 4.0  
**Tables:** 47  
**Stored Procedures:** 100  
**Generated:** 2026-06-26  

---

## Architecture Principles

- **SP naming:** `{Module}_{Action}` — `Auth_SendOTP`, `Org_Register`, `Project_Create`
- **Parameter prefix:** `p_` — `p_UserId`, `p_OrgId`, `p_PageNumber`
- **WRITE SPs always return:** `IsSuccess INT`, `Message VARCHAR`, `[EntityId]`
- **READ SPs return:** direct SELECT rows; paged SPs add second result set `SELECT COUNT(*) AS TotalCount`
- **Soft delete:** all master tables have `IsDeleted TINYINT(1)`, `DeletedAt`, `DeletedBy`
- **LookupValues:** all category columns use `INT UNSIGNED FK → LookupValues` not enums
- **30/70 rule:** 30% typed C# models, 70% DynamicRow for display queries

---

## Tables (47 Total)

### Group 1 — Auth (3 tables)

#### Users
| Column | Type | Notes |
|---|---|---|
| UserId | INT UNSIGNED PK AUTO_INCREMENT | |
| Mobile | VARCHAR(20) UNIQUE NOT NULL | |
| Email | VARCHAR(255) UNIQUE NULL | |
| CountryCode | VARCHAR(5) DEFAULT '+91' | |
| IsVerified | TINYINT(1) DEFAULT 0 | |
| IsActive | TINYINT(1) DEFAULT 1 | |
| IsDeleted | TINYINT(1) DEFAULT 0 | |
| DeletedAt | DATETIME NULL | |
| DeletedBy | INT UNSIGNED NULL | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |
| UpdatedAt | DATETIME NULL ON UPDATE CURRENT_TIMESTAMP | |

#### OtpTokens
| Column | Type | Notes |
|---|---|---|
| OtpTokenId | INT UNSIGNED PK AUTO_INCREMENT | |
| Recipient | VARCHAR(255) NOT NULL | Mobile or email |
| OtpCode | VARCHAR(10) NOT NULL | Hashed |
| PurposeLkpId | INT UNSIGNED FK→LookupValues | |
| AttemptCount | TINYINT DEFAULT 0 | Max 3 |
| ExpiresAt | DATETIME NOT NULL | |
| IsUsed | TINYINT(1) DEFAULT 0 | |
| IpAddress | VARCHAR(45) NULL | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |

#### RefreshTokens
| Column | Type | Notes |
|---|---|---|
| RefreshTokenId | INT UNSIGNED PK AUTO_INCREMENT | |
| UserId | INT UNSIGNED FK→Users | |
| TokenHash | VARCHAR(500) NOT NULL | SHA-256 |
| DeviceInfo | VARCHAR(500) NULL | |
| IpAddress | VARCHAR(45) NULL | |
| ExpiresAt | DATETIME NOT NULL | 30 days |
| RevokedAt | DATETIME NULL | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |

---

### Group 2 — Profiles (7 tables)

#### UserProfiles
| Column | Type | Notes |
|---|---|---|
| UserProfileId | INT UNSIGNED PK AUTO_INCREMENT | |
| UserId | INT UNSIGNED UNIQUE FK→Users | |
| FirstName | VARCHAR(100) NULL | |
| LastName | VARCHAR(100) NULL | |
| Bio | TEXT NULL | Maps to About in SP |
| GenderLkpId | INT UNSIGNED FK→LookupValues NULL | |
| DateOfBirth | DATE NULL | |
| ProfilePhoto | VARCHAR(500) NULL | Azure Blob URL |
| Occupation | VARCHAR(200) NULL | |
| Organisation | VARCHAR(200) NULL | Employer name |
| EducationLkpId | INT UNSIGNED FK→LookupValues NULL | v4.0 |
| FieldOfStudy | VARCHAR(200) NULL | v4.0 |
| WorkExpLkpId | INT UNSIGNED FK→LookupValues NULL | v4.0 |
| AddressLine1 | VARCHAR(300) NULL | v4.0 |
| AddressLine2 | VARCHAR(300) NULL | v4.0 |
| Pincode | VARCHAR(20) NULL | v4.0 |
| City | VARCHAR(100) NULL | |
| State | VARCHAR(100) NULL | |
| Country | VARCHAR(100) DEFAULT 'India' | |
| ImpactScore | INT DEFAULT 0 | |
| ReliabilityPct | DECIMAL(5,2) DEFAULT 0.00 | |
| IsProfileComplete | TINYINT(1) DEFAULT 0 | |
| UpdatedAt | DATETIME NULL | |

#### UserDocuments
| Column | Type | Notes |
|---|---|---|
| UserDocumentId | INT UNSIGNED PK AUTO_INCREMENT | |
| UserId | INT UNSIGNED FK→Users | |
| DocumentTypeLkpId | INT UNSIGNED FK→LookupValues | |
| DocumentUrl | VARCHAR(500) NOT NULL | |
| ExpiryDate | DATE NULL | |
| IsVerified | TINYINT(1) DEFAULT 0 | |
| UploadedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |

#### UserSkills
| Column | Type | Notes |
|---|---|---|
| UserSkillId | INT UNSIGNED PK AUTO_INCREMENT | |
| UserId | INT UNSIGNED FK→Users | |
| SkillName | VARCHAR(100) NOT NULL | |
| AvgRating | DECIMAL(3,2) DEFAULT 0.00 | Denormalized |
| RatingCount | INT DEFAULT 0 | Denormalized |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |
| UNIQUE | (UserId, SkillName) | |

#### UserSkillRatings
| Column | Type | Notes |
|---|---|---|
| SkillRatingId | INT UNSIGNED PK AUTO_INCREMENT | |
| RaterUserId | INT UNSIGNED FK→Users | |
| RatedUserId | INT UNSIGNED FK→Users | |
| UserSkillId | INT UNSIGNED FK→UserSkills | |
| Rating | TINYINT NOT NULL | 1–5 |
| Review | VARCHAR(500) NULL | |
| ProjectId | INT UNSIGNED FK→Projects NULL | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |
| UNIQUE | (RaterUserId, UserSkillId) | ON DUPLICATE KEY UPDATE |

#### UserBadges
| Column | Type | Notes |
|---|---|---|
| UserBadgeId | INT UNSIGNED PK AUTO_INCREMENT | |
| UserId | INT UNSIGNED FK→Users | |
| BadgeLkpId | INT UNSIGNED FK→LookupValues | |
| AwardedBy | INT UNSIGNED FK→Users NULL | |
| ProjectId | INT UNSIGNED FK→Projects NULL | |
| AwardedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |
| UNIQUE | (UserId, BadgeLkpId) | INSERT IGNORE |

#### UserInterests
| Column | Type | Notes |
|---|---|---|
| UserInterestId | INT UNSIGNED PK AUTO_INCREMENT | |
| UserId | INT UNSIGNED FK→Users | |
| InterestLkpId | INT UNSIGNED FK→LookupValues | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |
| UNIQUE | (UserId, InterestLkpId) | |

#### UserSafetyPreferences
| Column | Type | Notes |
|---|---|---|
| SafetyPrefId | INT UNSIGNED PK AUTO_INCREMENT | |
| UserId | INT UNSIGNED UNIQUE FK→Users | |
| SosAlertTypeLkpId | INT UNSIGNED FK→LookupValues NULL | |
| EmergencyContactName | VARCHAR(200) NULL | |
| EmergencyContactPhone | VARCHAR(20) NULL | |
| EmergencyContactRelation | VARCHAR(100) NULL | |
| ShareLocationDuringSos | TINYINT(1) DEFAULT 1 | |
| UpdatedAt | DATETIME NULL | |

---

### Group 3 — Organisations (4 tables)

#### Organisations
| Column | Type | Notes |
|---|---|---|
| OrgId | INT UNSIGNED PK AUTO_INCREMENT | |
| OrgName | VARCHAR(300) NOT NULL | |
| RegistrationNumber | VARCHAR(100) UNIQUE NULL | v4.0 |
| OrgTypeLkpId | INT UNSIGNED FK→LookupValues NOT NULL | |
| Mission | TEXT NULL | v4.0 |
| Vision | TEXT NULL | v4.0 |
| LogoUrl | VARCHAR(500) NULL | v4.0 |
| AddressLine1 | VARCHAR(300) NULL | v4.0 |
| AddressLine2 | VARCHAR(300) NULL | v4.0 |
| Pincode | VARCHAR(20) NULL | v4.0 |
| City | VARCHAR(100) NULL | |
| State | VARCHAR(100) NULL | |
| Country | VARCHAR(100) DEFAULT 'India' | |
| Website | VARCHAR(300) NULL | |
| ContactEmail | VARCHAR(255) NULL | |
| ContactPhone | VARCHAR(20) NULL | |
| StatusLkpId | INT UNSIGNED FK→LookupValues NOT NULL | PENDING/VERIFIED/SUSPENDED |
| MemberCount | INT DEFAULT 0 | Denormalized |
| IsDeleted | TINYINT(1) DEFAULT 0 | |
| CreatedBy | INT UNSIGNED FK→Users NOT NULL | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |
| UpdatedAt | DATETIME NULL | |

#### OrgDocuments
| Column | Type | Notes |
|---|---|---|
| OrgDocumentId | INT UNSIGNED PK AUTO_INCREMENT | |
| OrgId | INT UNSIGNED FK→Organisations | |
| UploadedBy | INT UNSIGNED FK→Users | |
| DocumentTypeLkpId | INT UNSIGNED FK→LookupValues | |
| DocumentUrl | VARCHAR(500) NOT NULL | |
| ExpiryDate | DATE NULL | |
| IsVerified | TINYINT(1) DEFAULT 0 | |
| UploadedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |

#### OrgMembers
| Column | Type | Notes |
|---|---|---|
| OrgMemberId | INT UNSIGNED PK AUTO_INCREMENT | |
| OrgId | INT UNSIGNED FK→Organisations | |
| UserId | INT UNSIGNED FK→Users | |
| RoleLkpId | INT UNSIGNED FK→LookupValues | ADMIN/STAFF/MEMBER |
| ApprovalStatusLkpId | INT UNSIGNED FK→LookupValues | PENDING/APPROVED/REJECTED |
| AdminNotes | VARCHAR(500) NULL | |
| RequestMessage | TEXT NULL | v4.0 |
| CanPost | TINYINT(1) DEFAULT 1 | v4.0 |
| CanComment | TINYINT(1) DEFAULT 1 | v4.0 |
| CanCommunityPost | TINYINT(1) DEFAULT 1 | v4.0 |
| MaxPostsPerDay | TINYINT DEFAULT 10 | v4.0 |
| LocationSharingLkpId | INT UNSIGNED FK→LookupValues NULL | v4.0 |
| RequestedBy | INT UNSIGNED FK→Users NULL | |
| ReviewedBy | INT UNSIGNED FK→Users NULL | |
| JoinedAt | DATETIME NULL | Set when approved |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |
| UNIQUE | (OrgId, UserId) | |

#### OrgDonationSettings (legacy, kept for compatibility)
| Column | Type | Notes |
|---|---|---|
| OrgDonSettingId | INT UNSIGNED PK AUTO_INCREMENT | |
| OrgId | INT UNSIGNED UNIQUE FK→Organisations | |
| RazorpayKeyId | VARCHAR(200) NULL | |
| RazorpayKeySecret | VARCHAR(200) NULL | Encrypted |
| WithdrawalEnabled | TINYINT(1) DEFAULT 0 | |
| UpdatedAt | DATETIME NULL | |

---

### Group 4 — Projects (6 tables)

#### Projects
| Column | Type | Notes |
|---|---|---|
| ProjectId | INT UNSIGNED PK AUTO_INCREMENT | |
| OrgId | INT UNSIGNED FK→Organisations NOT NULL | |
| CreatedBy | INT UNSIGNED FK→Users NOT NULL | |
| Title | VARCHAR(200) NOT NULL | |
| Description | TEXT NULL | |
| ProjectTypeLkpId | INT UNSIGNED FK→LookupValues NULL | |
| JoinTypeLkpId | INT UNSIGNED FK→LookupValues NULL | OPEN/APPROVAL/INVITE |
| StatusLkpId | INT UNSIGNED FK→LookupValues NOT NULL | DRAFT/ACTIVE/COMPLETED/CANCELLED |
| MaxVolunteers | INT NULL | |
| MinAge | TINYINT NULL | |
| MaxAge | TINYINT NULL | |
| IsPublic | TINYINT(1) DEFAULT 1 | |
| StartDate | DATE NULL | |
| EndDate | DATE NULL | |
| ScheduleType | VARCHAR(20) NULL | ONE_TIME/RECURRING/ONGOING |
| RecurrenceDays | VARCHAR(100) NULL | Mon,Wed,Fri |
| StartTime | TIME NULL | |
| EndTime | TIME NULL | |
| DurationMinutes | INT NULL | |
| LocationTypeLkpId | INT UNSIGNED FK→LookupValues NULL | IN_PERSON/ONLINE/HYBRID |
| LocationName | VARCHAR(200) NULL | |
| Address | VARCHAR(500) NULL | |
| Latitude | DECIMAL(10,7) NULL | |
| Longitude | DECIMAL(10,7) NULL | |
| MeetingLink | VARCHAR(500) NULL | |
| GenderRestriction | VARCHAR(20) NULL | ANY/MALE/FEMALE |
| RequiresApproval | TINYINT(1) DEFAULT 0 | |
| CoverImageUrl | VARCHAR(500) NULL | |
| City | VARCHAR(100) NULL | |
| State | VARCHAR(100) NULL | |
| AppliedCount | INT DEFAULT 0 | Denormalized |
| IsDeleted | TINYINT(1) DEFAULT 0 | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |
| UpdatedAt | DATETIME NULL | |

#### ProjectSkills
| Column | Type | Notes |
|---|---|---|
| ProjectSkillId | INT UNSIGNED PK AUTO_INCREMENT | |
| ProjectId | INT UNSIGNED FK→Projects | |
| SkillName | VARCHAR(100) NOT NULL | |
| IsRequired | TINYINT(1) DEFAULT 0 | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |

#### ProjectSessions
| Column | Type | Notes |
|---|---|---|
| SessionId | INT UNSIGNED PK AUTO_INCREMENT | |
| ProjectId | INT UNSIGNED FK→Projects | |
| SessionDate | DATE NOT NULL | |
| StartTime | TIME NOT NULL | |
| EndTime | TIME NOT NULL | |
| MaxVolunteers | INT NULL | |
| QrCode | VARCHAR(500) NULL | UUID token |
| QrExpiresAt | DATETIME NULL | |
| SessionStatusLkpId | INT UNSIGNED FK→LookupValues NULL | UPCOMING/ACTIVE/COMPLETED |
| AttendeeCount | INT DEFAULT 0 | Denormalized |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |

#### ProjectApplications
| Column | Type | Notes |
|---|---|---|
| ApplicationId | INT UNSIGNED PK AUTO_INCREMENT | |
| ProjectId | INT UNSIGNED FK→Projects | |
| UserId | INT UNSIGNED FK→Users | |
| StatusLkpId | INT UNSIGNED FK→LookupValues | PENDING/APPROVED/REJECTED |
| Note | TEXT NULL | |
| ReviewedBy | INT UNSIGNED FK→Users NULL | |
| ReviewedAt | DATETIME NULL | |
| AdminNotes | TEXT NULL | |
| AppliedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |
| UNIQUE | (ProjectId, UserId) | |

#### ProjectAttendance
| Column | Type | Notes |
|---|---|---|
| AttendanceId | INT UNSIGNED PK AUTO_INCREMENT | |
| SessionId | INT UNSIGNED FK→ProjectSessions | |
| UserId | INT UNSIGNED FK→Users | |
| CheckInAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |
| CheckInMethod | VARCHAR(20) DEFAULT 'QR' | |
| UNIQUE | (SessionId, UserId) | |

#### VolunteerCertificates
| Column | Type | Notes |
|---|---|---|
| CertificateId | INT UNSIGNED PK AUTO_INCREMENT | |
| UserId | INT UNSIGNED FK→Users | |
| ProjectId | INT UNSIGNED FK→Projects | |
| OrgId | INT UNSIGNED FK→Organisations | |
| CertificateUrl | VARCHAR(500) NULL | Azure Blob |
| IssuedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |
| HoursLogged | INT NULL | |
| UNIQUE | (UserId, ProjectId) | |

---

### Group 5 — Content (9 tables)

#### Posts
| Column | Type | Notes |
|---|---|---|
| PostId | INT UNSIGNED PK AUTO_INCREMENT | |
| UserId | INT UNSIGNED FK→Users | |
| OrgId | INT UNSIGNED FK→Organisations NULL | |
| Content | TEXT NOT NULL | |
| PostTypeLkpId | INT UNSIGNED FK→LookupValues NULL | |
| VisibilityLkpId | INT UNSIGNED FK→LookupValues NULL | |
| LikeCount | INT DEFAULT 0 | Denormalized |
| CommentCount | INT DEFAULT 0 | Denormalized |
| IsPinned | TINYINT(1) DEFAULT 0 | |
| IsDeleted | TINYINT(1) DEFAULT 0 | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |
| UpdatedAt | DATETIME NULL | |

#### PostMedia
| Column | Type | Notes |
|---|---|---|
| PostMediaId | INT UNSIGNED PK AUTO_INCREMENT | |
| PostId | INT UNSIGNED FK→Posts | |
| MediaUrl | VARCHAR(500) NOT NULL | |
| MediaTypeLkpId | INT UNSIGNED FK→LookupValues NULL | |
| SortOrder | TINYINT DEFAULT 0 | |

#### PostLikes
| Column | Type | Notes |
|---|---|---|
| PostLikeId | INT UNSIGNED PK AUTO_INCREMENT | |
| PostId | INT UNSIGNED FK→Posts | |
| UserId | INT UNSIGNED FK→Users | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |
| UNIQUE | (PostId, UserId) | |

#### PostComments
| Column | Type | Notes |
|---|---|---|
| CommentId | INT UNSIGNED PK AUTO_INCREMENT | |
| PostId | INT UNSIGNED FK→Posts | |
| UserId | INT UNSIGNED FK→Users | |
| ParentCommentId | INT UNSIGNED FK→PostComments NULL | Threading |
| Content | TEXT NOT NULL | |
| IsDeleted | TINYINT(1) DEFAULT 0 | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |

#### PostReports
| Column | Type | Notes |
|---|---|---|
| PostReportId | INT UNSIGNED PK AUTO_INCREMENT | |
| PostId | INT UNSIGNED FK→Posts | |
| ReportedBy | INT UNSIGNED FK→Users | |
| ReasonLkpId | INT UNSIGNED FK→LookupValues | |
| Details | TEXT NULL | |
| StatusLkpId | INT UNSIGNED FK→LookupValues NULL | PENDING/REVIEWED/DISMISSED |
| ReviewedBy | INT UNSIGNED FK→Users NULL | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |

#### CommunityPosts
| Column | Type | Notes |
|---|---|---|
| CommunityPostId | INT UNSIGNED PK AUTO_INCREMENT | |
| OrgId | INT UNSIGNED FK→Organisations NOT NULL | |
| UserId | INT UNSIGNED FK→Users | |
| Title | VARCHAR(300) NOT NULL | |
| Content | TEXT NULL | |
| PostTypeLkpId | INT UNSIGNED FK→LookupValues NOT NULL | |
| AudienceLkpId | INT UNSIGNED FK→LookupValues NULL | |
| IsDeleted | TINYINT(1) DEFAULT 0 | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |

#### PollOptions
| Column | Type | Notes |
|---|---|---|
| PollOptionId | INT UNSIGNED PK AUTO_INCREMENT | |
| CommunityPostId | INT UNSIGNED FK→CommunityPosts | |
| OptionText | VARCHAR(500) NOT NULL | |
| VoteCount | INT DEFAULT 0 | Denormalized |
| PollEndsAt | DATETIME NULL | |

#### PollVotes
| Column | Type | Notes |
|---|---|---|
| PollVoteId | INT UNSIGNED PK AUTO_INCREMENT | |
| PollOptionId | INT UNSIGNED FK→PollOptions | |
| UserId | INT UNSIGNED FK→Users | |
| VotedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |
| UNIQUE | (PollOptionId, UserId) | |

#### Notifications
| Column | Type | Notes |
|---|---|---|
| NotificationId | BIGINT UNSIGNED PK AUTO_INCREMENT | BIGINT — billions at scale |
| UserId | INT UNSIGNED FK→Users | |
| TypeLkpId | INT UNSIGNED FK→LookupValues NULL | |
| Title | VARCHAR(200) NOT NULL | |
| Body | TEXT NULL | |
| EntityType | VARCHAR(50) NULL | POST/PROJECT/SOS/DONATION |
| EntityId | INT UNSIGNED NULL | Related entity ID |
| IsRead | TINYINT(1) DEFAULT 0 | |
| ReadAt | DATETIME NULL | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |

---

### Group 6 — Safety / SOS (3 tables)

#### SosIncidents
| Column | Type | Notes |
|---|---|---|
| SosIncidentId | INT UNSIGNED PK AUTO_INCREMENT | |
| VictimUserId | INT UNSIGNED FK→Users | |
| OrgId | INT UNSIGNED FK→Organisations NULL | |
| AlertTypeLkpId | INT UNSIGNED FK→LookupValues | |
| StatusLkpId | INT UNSIGNED FK→LookupValues | ACTIVE/RESOLVED/CANCELLED |
| Description | TEXT NULL | |
| ApproxLocation | VARCHAR(500) NULL | |
| Latitude | DECIMAL(10,7) NULL | Last known |
| Longitude | DECIMAL(10,7) NULL | Last known |
| CancelReason | TEXT NULL | v4.0 |
| ResolvedByLkpId | INT UNSIGNED FK→LookupValues NULL | |
| ResolvedAt | DATETIME NULL | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |

#### SosResponders
| Column | Type | Notes |
|---|---|---|
| SosResponderId | INT UNSIGNED PK AUTO_INCREMENT | |
| SosIncidentId | INT UNSIGNED FK→SosIncidents | |
| UserId | INT UNSIGNED FK→Users | Responder |
| ApprovalStatusLkpId | INT UNSIGNED FK→LookupValues | PENDING/APPROVED/REJECTED |
| CanViewLocation | TINYINT(1) DEFAULT 0 | v4.0 |
| RespondedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |
| UNIQUE | (SosIncidentId, UserId) | |

#### SosLocationLogs
| Column | Type | Notes |
|---|---|---|
| SosLocationLogId | BIGINT UNSIGNED PK AUTO_INCREMENT | BIGINT — every 10s |
| SosIncidentId | INT UNSIGNED FK→SosIncidents | |
| UserId | INT UNSIGNED FK→Users | |
| Latitude | DECIMAL(10,7) NOT NULL | |
| Longitude | DECIMAL(10,7) NOT NULL | |
| Accuracy | DECIMAL(8,2) NULL | Metres |
| LoggedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |

---

### Group 7 — Donations (6 tables)

#### DonationCampaigns
| Column | Type | Notes |
|---|---|---|
| CampaignId | INT UNSIGNED PK AUTO_INCREMENT | |
| OrgId | INT UNSIGNED FK→Organisations | |
| CreatedBy | INT UNSIGNED FK→Users | |
| CampaignName | VARCHAR(200) NOT NULL | SP param: p_Title |
| Description | TEXT NULL | |
| CampaignTypeLkpId | INT UNSIGNED FK→LookupValues | |
| TargetAmount | DECIMAL(12,2) NOT NULL | SP param: p_GoalAmount |
| RaisedAmount | DECIMAL(12,2) DEFAULT 0 | Denormalized |
| StartDate | DATE NOT NULL | |
| EndDate | DATE NULL | |
| BannerUrl | VARCHAR(500) NULL | |
| StatusLkpId | INT UNSIGNED FK→LookupValues | DRAFT/ACTIVE/COMPLETED/SUSPENDED |
| IsDeleted | TINYINT(1) DEFAULT 0 | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |
| UpdatedAt | DATETIME NULL | |

#### DonationTransactions
| Column | Type | Notes |
|---|---|---|
| DonationId | INT UNSIGNED PK AUTO_INCREMENT | |
| DonationRef | VARCHAR(30) UNIQUE | DON-2026-000001 via IdSequences |
| UserId | INT UNSIGNED FK→Users | |
| CampaignId | INT UNSIGNED FK→DonationCampaigns | |
| Amount | DECIMAL(10,2) NOT NULL | |
| PayMethodLkpId | INT UNSIGNED FK→LookupValues | |
| StatusLkpId | INT UNSIGNED FK→LookupValues | PENDING/COMPLETED/FAILED/REFUNDED |
| RazorpayOrderId | VARCHAR(200) NULL | |
| RazorpayPaymentId | VARCHAR(200) NULL | |
| Note | TEXT NULL | |
| IsAnonymous | TINYINT(1) DEFAULT 0 | |
| PaidAt | DATETIME NULL | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |

#### RecurringDonations
| Column | Type | Notes |
|---|---|---|
| RecurringDonId | INT UNSIGNED PK AUTO_INCREMENT | |
| UserId | INT UNSIGNED FK→Users | |
| OrgId | INT UNSIGNED FK→Organisations | |
| CampaignId | INT UNSIGNED FK→DonationCampaigns | |
| Amount | DECIMAL(10,2) NOT NULL | |
| FrequencyLkpId | INT UNSIGNED FK→LookupValues | WEEKLY/MONTHLY/QUARTERLY/YEARLY |
| StartDate | DATE NOT NULL | |
| NextRunAt | DATETIME NULL | |
| IsActive | TINYINT(1) DEFAULT 1 | |
| PausedAt | DATETIME NULL | v4.0 |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |

#### DonationReceipts
| Column | Type | Notes |
|---|---|---|
| ReceiptId | INT UNSIGNED PK AUTO_INCREMENT | |
| DonationId | INT UNSIGNED UNIQUE FK→DonationTransactions | |
| ReceiptNumber | VARCHAR(50) UNIQUE | |
| ReceiptUrl | VARCHAR(500) NULL | Azure Blob |
| ReceiptType | VARCHAR(20) DEFAULT '80G' | |
| GeneratedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |

#### WithdrawalRequests
| Column | Type | Notes |
|---|---|---|
| WithdrawalId | INT UNSIGNED PK AUTO_INCREMENT | |
| WithdrawalRef | VARCHAR(20) UNIQUE | WDR-2026-0001 via IdSequences |
| OrgId | INT UNSIGNED FK→Organisations | |
| CampaignId | INT UNSIGNED FK→DonationCampaigns | |
| RequestedBy | INT UNSIGNED FK→Users | |
| Amount | DECIMAL(10,2) NOT NULL | |
| BankAccount | VARCHAR(200) NOT NULL | |
| IfscCode | VARCHAR(20) NOT NULL | |
| AccountHolder | VARCHAR(200) NOT NULL | |
| Purpose | VARCHAR(500) NULL | |
| StatusLkpId | INT UNSIGNED FK→LookupValues | PENDING/APPROVED/REJECTED |
| AdminNotes | TEXT NULL | |
| ReviewedBy | INT UNSIGNED FK→Users NULL | |
| ReviewedAt | DATETIME NULL | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |

#### PaymentGatewayLogs
| Column | Type | Notes |
|---|---|---|
| GatewayLogId | INT UNSIGNED PK AUTO_INCREMENT | |
| DonationId | INT UNSIGNED FK→DonationTransactions NULL | |
| GatewayName | VARCHAR(50) DEFAULT 'Razorpay' | |
| EventType | VARCHAR(100) NULL | |
| Payload | JSON NULL | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |

---

### Group 8 — System (2 tables)

#### AuditLogs
| Column | Type | Notes |
|---|---|---|
| AuditLogId | BIGINT UNSIGNED PK AUTO_INCREMENT | BIGINT — every write |
| UserId | INT UNSIGNED NULL | |
| Action | VARCHAR(100) NOT NULL | CREATE/UPDATE/DELETE |
| EntityName | VARCHAR(100) NOT NULL | |
| EntityId | INT UNSIGNED NULL | |
| OldValue | JSON NULL | |
| NewValue | JSON NULL | |
| IpAddress | VARCHAR(45) NULL | |
| UserAgent | VARCHAR(500) NULL | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |

#### IdSequences
| Column | Type | Notes |
|---|---|---|
| SequenceId | INT UNSIGNED PK AUTO_INCREMENT | |
| PrefixCode | VARCHAR(10) UNIQUE NOT NULL | DON, WDR, REC |
| CurrentYear | SMALLINT NOT NULL | |
| LastNumber | INT DEFAULT 0 | |
| Padding | TINYINT DEFAULT 6 | Leading zeros |

> **Readable ID format:** `{PREFIX}-{YEAR}-{PADDED_NUMBER}`  
> DON-2026-000001, WDR-2026-0001, REC-2026-0001

---

### Group 9 — Lookup (2 tables)

#### LookupTypes
| Column | Type | Notes |
|---|---|---|
| LookupTypeId | INT UNSIGNED PK AUTO_INCREMENT | |
| TypeCode | VARCHAR(50) UNIQUE NOT NULL | GENDER, ORG_TYPE, etc. |
| TypeName | VARCHAR(200) NOT NULL | |
| Description | TEXT NULL | |
| IsSystem | TINYINT(1) DEFAULT 1 | |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |

#### LookupValues
| Column | Type | Notes |
|---|---|---|
| LookupValueId | INT UNSIGNED PK AUTO_INCREMENT | |
| LookupTypeId | INT UNSIGNED FK→LookupTypes | |
| ValueCode | VARCHAR(50) NOT NULL | MALE, FEMALE, NGO, etc. |
| ValueName | VARCHAR(200) NOT NULL | Display label |
| Description | TEXT NULL | |
| OrderNo | SMALLINT DEFAULT 0 | UI display order |
| IsDefault | TINYINT(1) DEFAULT 0 | Pre-selected in UI |
| IsSystemValue | TINYINT(1) DEFAULT 1 | Cannot be deleted |
| CreatedAt | DATETIME DEFAULT CURRENT_TIMESTAMP | |
| UNIQUE | (LookupTypeId, ValueCode) | |

---

### Group 10 — Settings (1 table)

#### Settings
| Column | Type | Notes |
|---|---|---|
| SettingId | INT UNSIGNED PK AUTO_INCREMENT | |
| SettingGroup | VARCHAR(50) NOT NULL | SMS, OTP, AUTH, UPLOAD, etc. |
| SettingKey | VARCHAR(100) UNIQUE NOT NULL | |
| SettingValue | TEXT NOT NULL | |
| DataType | VARCHAR(20) DEFAULT 'STRING' | STRING/NUMBER/BOOLEAN/URL/JSON |
| Description | VARCHAR(500) NULL | |
| IsPublic | TINYINT(1) DEFAULT 0 | Safe for frontend |
| IsEditable | TINYINT(1) DEFAULT 1 | |
| UpdatedAt | DATETIME NULL | |
| UpdatedBy | INT UNSIGNED NULL | |

> **SettingsCache:** All settings loaded at startup into singleton. Zero DB reads on config access.  
> **IsPublic=1:** returned by `GET /api/v1/settings/public` — never expose secrets.

---

## LookupTypes (44 Types)

| TypeCode | Description |
|---|---|
| GENDER | Male, Female, Non-Binary, Prefer Not to Say |
| ORG_TYPE | NGO, CSR, Government, Educational, Social Enterprise, Foundation |
| ORG_STATUS | Pending Verification, Verified, Suspended, Rejected |
| USER_ROLE | Super Admin, NGO Admin, Volunteer, Donor, Beneficiary, Staff |
| ORG_MEMBER_ROLE | Admin, Staff, Member |
| MEMBER_APPROVAL | Pending, Approved, Rejected |
| LOCATION_SHARING | Always, During Activity, On Request, Never |
| PROJECT_TYPE | Education, Healthcare, Environment, Animal Welfare, Disaster Relief, Women Empowerment, Child Welfare, Elderly Care, Poverty Alleviation, Arts & Culture |
| PROJECT_STATUS | Draft, Active, Completed, Cancelled, Paused |
| JOIN_TYPE | Open, Requires Approval, Invite Only |
| LOCATION_TYPE | In-Person, Online, Hybrid |
| APPLICATION_STATUS | Pending, Approved, Rejected, Waitlisted, Withdrawn |
| SESSION_STATUS | Upcoming, Active, Completed, Cancelled |
| ATTENDANCE_METHOD | QR Scan, Manual, GPS |
| BADGE_TYPE | First Volunteer, 10 Hours, 50 Hours, 100 Hours, 500 Hours, Mentor, Top Donor, SOS Hero, Community Leader, Impact Champion |
| EDUCATION | Below 10th, 10th Pass, 12th Pass, Diploma, Graduate, Post Graduate, Doctorate |
| WORK_EXPERIENCE | Fresher, 1-2 Years, 3-5 Years, 6-10 Years, 10+ Years |
| INTEREST_TYPE | Education, Healthcare, Environment, Sports, Arts, Technology, Community, Animal Welfare |
| DOC_TYPE_USER | Aadhaar, PAN, Passport, Driving License, Voter ID |
| DOC_TYPE_ORG | Registration Certificate, 80G Certificate, 12A Certificate, FCRA Certificate, CSR Policy, Annual Report |
| POST_TYPE_FEED | Update, Announcement, Opportunity, Story, Article |
| POST_VISIBILITY | Public, Followers, Organisation Members, Private |
| POST_TYPE_COMMUNITY | Discussion, Question, Announcement, Resource, Event, Achievement |
| REPORT_REASON | Spam, Inappropriate Content, Misleading, Hate Speech, Harassment, Other |
| REPORT_STATUS | Pending, Under Review, Action Taken, Dismissed |
| SOS_ALERT_TYPE | SOS Emergency, Help Request, Missing Volunteer, Safe Arrival |
| SOS_STATUS | Active, Resolved, Cancelled |
| SOS_APPROVAL | Pending, Approved, Rejected |
| SOS_RESOLUTION | Self Resolved, Helped By Volunteer, Emergency Services, False Alarm |
| OTP_PURPOSE | Login/Registration, Mobile Change, Email Change, Password Reset |
| CAMPAIGN_TYPE | General, Project Specific, Emergency, Recurring |
| CAMPAIGN_STATUS | Draft, Active, Completed, Suspended, Archived |
| PAYMENT_METHOD | UPI, Credit/Debit Card, Net Banking, Wallet, NEFT/RTGS |
| PAYMENT_STATUS | Pending, Completed, Failed, Refunded |
| RECURRING_FREQUENCY | Weekly, Monthly, Quarterly, Yearly |
| WITHDRAWAL_STATUS | Pending, Under Review, Approved, Rejected, Processed |
| NOTIFICATION_TYPE | Project Update, New Application, SOS Alert, Donation Received, Badge Earned, New Follower, Comment, Mention, System |
| RECEIPT_TYPE | 80G, General, CSR |
| MEDIA_TYPE | Image, Video, Document, Audio |
| CERTIFICATE_TYPE | Volunteer Completion, Skills Assessment, Training, Achievement |
| SETTING_DATA_TYPE | String, Number, Boolean, URL, JSON |
| BENEFICIARY_TYPE | Individual, Family, Community, Institution |
| LANGUAGE | English, Hindi, Marathi, Tamil, Telugu, Kannada, Bengali, Gujarati |
| COUNTRY | India, USA, UK, Canada, Australia, UAE, Singapore, Germany |

---

## Stored Procedures (100 Total)

### Auth (7 SPs)
| SP Name | Type | Description |
|---|---|---|
| Auth_SendOTP | WRITE | Generates OTP, enforces rate limits (3/10min, max 3 attempts) |
| Auth_VerifyOTP | WRITE | Validates OTP, creates user if new, returns UserId + IsNewUser |
| Auth_SaveRefreshToken | WRITE | Stores hashed refresh token |
| Auth_GetRefreshToken | READ | Gets token for rotation |
| Auth_RevokeRefreshToken | WRITE | Soft-revokes token |
| Auth_RevokeRefreshTokenById | WRITE | Revokes by ID (internal) |
| Auth_GetRefreshToken | READ | Validates hash, returns UserId + Recipient |

### User (9 SPs)
| SP Name | Type | Description |
|---|---|---|
| User_GetProfile | GET | Returns full profile + LookupValue codes for v4.0 fields |
| User_GetPublicProfile | GET | Public-safe profile (no sensitive fields) |
| User_UpdateProfile | WRITE | 18 params including all v4.0 fields |
| User_UpdateSafetyPrefs | WRITE | SOS alert type + emergency contact |
| User_SaveInterests | WRITE | Accepts JSON array of InterestLkpIds, DELETE+INSERT |
| User_UploadDocument | WRITE | Inserts into UserDocuments |
| User_GetSkills | READ | Returns UserSkills with AvgRating, RatingCount |
| User_AddSkill | WRITE | Inserts skill (or ignores duplicate) |
| User_RemoveSkill | WRITE | Soft-deletes |

### Lookup (3 SPs)
| SP Name | Type | Description |
|---|---|---|
| Lookup_GetAllTypes | READ | All LookupTypes |
| Lookup_GetValuesByType | READ | Values by TypeCode |
| Lookup_GetValuesByTypeCode | READ | Alias (same as above) |

### Settings (4 SPs)
| SP Name | Type | Description |
|---|---|---|
| Settings_GetPublic | READ | IsPublic=1 settings |
| Settings_GetByGroup | READ | Filter by SettingGroup |
| Settings_GetAll | READ | Admin only |
| Settings_Update | WRITE | Update value, refresh cache |

### Organisation (10 SPs)
| SP Name | Type | Description |
|---|---|---|
| Org_Register | WRITE | Creates org + adds creator as ADMIN member |
| Org_GetProfile | GET | Full org profile with member count, type |
| Org_Update | WRITE | Updates all v4.0 fields |
| Org_List | PAGED | Keyword + orgType filter |
| Org_GetMembers | LIST | All members with role, status, permissions |
| Org_AddMember | WRITE | Direct add (admin action) |
| Org_RemoveMember | WRITE | Soft remove |
| Org_RequestMembership | WRITE | User self-requests; stores RequestMessage |
| Org_ReviewMembership | WRITE | APPROVED/REJECTED with AdminNotes |
| Org_GetPendingMembers | LIST | PENDING approval requests |
| Org_UpdateMemberPermissions | WRITE | CanPost, CanComment, MaxPostsPerDay, LocationSharing |
| Org_UploadDocument | WRITE | OrgDocuments insert |

### Project (10 SPs)
| SP Name | Type | Description |
|---|---|---|
| Project_Create | WRITE | All 29 params including schedule + location |
| Project_GetById | GET | Full project with org name, status label |
| Project_Update | WRITE | Same 29 params as Create |
| Project_List | PAGED | orgId + keyword + projectType filter |
| Project_AddSkill | WRITE | Inserts ProjectSkill |
| Project_AddSession | WRITE | Creates session + generates QR UUID |
| Project_GetSessions | LIST | Sessions with attendee count, QR, status |
| Project_GetSessionQr | GET | Returns QR token for org admin |
| Project_CheckIn | WRITE | Validates QR token, records attendance |
| Project_Apply | WRITE | Inserts application |
| Project_ReviewApplication | WRITE | APPROVED/REJECTED |
| Project_GetApplications | PAGED | Filter by statusCode |
| Project_Complete | WRITE | Sets status COMPLETED, triggers certificate generation |

### Application (4 SPs — standalone module)
| SP Name | Type | Description |
|---|---|---|
| Application_Apply | WRITE | Alias for Project_Apply |
| Application_GetByProject | PAGED | By project + statusLkpId |
| Application_Review | WRITE | Uses StatusLkpId (INT) |
| Application_GetByUser | LIST | My applications across all projects |

### Post / Feed (9 SPs)
| SP Name | Type | Description |
|---|---|---|
| Post_Create | WRITE | Content + optional MediaUrls CSV |
| Post_GetFeed | PAGED | Personalized feed for logged-in user |
| Post_GetById | GET | Single post with like/comment counts |
| Post_Delete | WRITE | Soft delete |
| Post_Pin | WRITE | Toggle IsPinned |
| Post_Like | WRITE | INSERT IGNORE into PostLikes |
| Post_Unlike | WRITE | DELETE from PostLikes |
| Post_AddComment | WRITE | Supports threading via ParentCommentId |
| Post_GetComments | PAGED | Nested comments |
| Post_Report | WRITE | PostReports insert |

### Community (5 SPs)
| SP Name | Type | Description |
|---|---|---|
| Community_CreatePost | WRITE | Title required, PostTypeLkpId, AudienceLkpId |
| Community_GetFeed | PAGED | Optional OrgId filter |
| Community_AcknowledgePost | WRITE | Mark post acknowledged |
| Community_CreatePoll | WRITE | Creates CommunityPost + PollOptions from JSON |
| Community_Vote | WRITE | INSERT IGNORE (one vote per user per option) |

### SOS (9 SPs)
| SP Name | Type | Description |
|---|---|---|
| Sos_Trigger | WRITE | Creates incident, logs initial location |
| Sos_GetActive | LIST | p_OrgId nullable filter (v4.0) |
| Sos_GetById | GET | Incident details + responders list |
| Sos_Respond | WRITE | Adds user to SosResponders (PENDING approval) |
| Sos_ApproveResponder | WRITE | Sets APPROVED, sets CanViewLocation |
| Sos_Resolve | WRITE | RESOLVED or CANCELLED via p_StatusCode |
| Sos_Cancel | WRITE | Alias calls Sos_Resolve with CANCELLED |
| Sos_GetLatestLocation | GET | Checks victim or approved responder before returning |
| Sos_UpdateLocation | WRITE | Logs to SosLocationLogs every ~10 sec |

### Donation (14 SPs)
| SP Name | Type | Description |
|---|---|---|
| Donation_CreateCampaign | WRITE | All campaign fields |
| Donation_GetCampaigns | PAGED | orgId + keyword filter |
| Donation_GetCampaignById | GET | Campaign with raised amount |
| Donation_GetDonors | PAGED | Respects IsAnonymous flag |
| Donation_Donate | WRITE | Generates DON-YYYY-NNNNNN readable ID |
| Donation_ConfirmPayment | WRITE | Updates status COMPLETED, updates RaisedAmount |
| Donation_GetHistory | PAGED | Donor's transaction history |
| Donation_GetReceipt | GET | 80G receipt by DonationId |
| Donation_SetupRecurring | WRITE | Creates RecurringDonations record |
| Donation_PauseRecurring | WRITE | IsActive=0, PausedAt=NOW() |
| Donation_ResumeRecurring | WRITE | IsActive=1, PausedAt=NULL, NextRunAt=+1month |
| Donation_CancelRecurring | WRITE | Marks inactive permanently |
| Donation_GetAnnualSummary | GET | Year summary + per-NGO breakdown (2 result sets) |
| Donation_GetSupportedNGOs | LIST | All NGOs a donor has supported |
| Donation_GetOrgTransactions | PAGED | Finance view for org admins |

### Withdrawal (3 SPs)
| SP Name | Type | Description |
|---|---|---|
| Withdrawal_Create | WRITE | Validates RaisedAmount ≥ Amount; generates WDR-YYYY-NNNN |
| Withdrawal_GetByOrg | PAGED | Withdrawal list with campaign title + status |
| Withdrawal_AdminReview | WRITE | APPROVED deducts from RaisedAmount |

### Certificate / Badge / Rating (3 SPs)
| SP Name | Type | Description |
|---|---|---|
| Certificate_GetByUser | LIST | Joins Projects + Organisations |
| UserSkillRating_Add | WRITE | ON DUPLICATE KEY UPDATE |
| UserBadge_Award | WRITE | INSERT IGNORE |

### Notification (5 SPs)
| SP Name | Type | Description |
|---|---|---|
| Notification_GetByUser | PAGED | p_OnlyUnread filter (v4.0) |
| Notification_MarkRead | WRITE | Single notification |
| Notification_MarkAllRead | WRITE | All for user |
| Notification_GetUnreadCount | GET | Returns UnreadCount |
| Notification_Create | WRITE | Internal use by other SPs |
| Notification_SaveDeviceToken | WRITE | FCM token via UserDeviceTokens |

---

## IdSequences — Readable IDs

| PrefixCode | Format | Example | Padding |
|---|---|---|---|
| DON | DON-{YYYY}-{NNNNNN} | DON-2026-000001 | 6 digits |
| WDR | WDR-{YYYY}-{NNNN} | WDR-2026-0001 | 4 digits |
| REC | REC-{YYYY}-{NNNN} | REC-2026-0001 | 4 digits |

SP pattern: `SELECT ... FOR UPDATE` on IdSequences, increment, format, use in INSERT.

---

## Key Design Decisions

| Decision | Rationale |
|---|---|
| BIGINT on AuditLogs, SosLocationLogs, Notifications | Volume overflow risk at scale |
| Denormalized counts (LikeCount, MemberCount, RaisedAmount) | No COUNT() on hot read paths |
| Soft delete everywhere | Audit trail, dispute resolution, compliance |
| LookupValues FK not VARCHAR enums | Dynamic — add new values without code deploy |
| Settings table not appsettings.json | Dynamic — update config without restart |
| DynamicRow for 70% of display queries | SP adds column → JSON updates, zero C# change |
| IdSequences for readable IDs | DON-2026-000001 better than raw INT for receipts |
| SchemaVersions table | Track migration history |

---

*NGOConnect v4.0 — 47 Tables, 100 Stored Procedures, 44 LookupTypes*
