using System.ComponentModel.DataAnnotations;

namespace NGOConnect.Core.Models.Skill
{
    public class IssueCertificateRequest
    {
        [Required] public int      ProjectId  { get; set; }
        [Required] public int      UserId     { get; set; }
        [Required] public int      OrgId      { get; set; }
        public decimal?            TotalHours { get; set; }
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
        [Required] public int    UserId      { get; set; }
        [Required] public int    BadgeLkpId  { get; set; }
        public int? ProjectId { get; set; }
    }
}
