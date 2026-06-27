using System.ComponentModel.DataAnnotations;

namespace NGOConnect.Core.Models.Skill
{
    public class AddSkillRatingRequest
    {
        [Required] public int    RatedUserId  { get; set; }
        [Required] public int    UserSkillId  { get; set; }
        [Required][Range(1, 5)] public int Rating { get; set; }
        [MaxLength(500)] public string? Review { get; set; }
        public int? ProjectId { get; set; }
    }

    public class AwardBadgeRequest
    {
        [Required] public int    UserId      { get; set; }
        [Required] public int    BadgeLkpId  { get; set; }
        public int? ProjectId { get; set; }
    }
}
