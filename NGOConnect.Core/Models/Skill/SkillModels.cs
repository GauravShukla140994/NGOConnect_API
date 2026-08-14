using System.ComponentModel.DataAnnotations;

namespace NGOConnect.Core.Models.Skill
{
    // v5.1: TotalHours removed — SP now computes from ProjectAttendance (SUM HoursLogged where ATTENDED)
    public class IssueCertificateRequest
    {
        [Required] public int ProjectId { get; set; }
        [Required] public int UserId    { get; set; }
        [Required] public int OrgId     { get; set; }
    }


    public class AddSkillRatingRequest
    {
        [Required] public int    RatedUserId    { get; set; }
        [Required] public int    ProjectSkillId { get; set; }  // ProjectSkills.ProjectSkillId
        [Required][Range(1, 5)] public decimal Rating { get; set; }
        [MaxLength(500)] public string? Notes { get; set; }
        public int? ProjectId { get; set; }
        public int? OrgId     { get; set; }
    }

    public class AwardBadgeRequest
    {
        [Required] public int    UserId    { get; set; }
        [Required] public string BadgeCode { get; set; } = string.Empty;  // BADGE_TYPE ValueCode e.g. STAR_VOL
        public int? ProjectId  { get; set; }
        public int? SessionId  { get; set; } // v5.1: session context for RECURRING/FLEXIBLE (accepted by SP, not stored in UserBadges)
    }
}
