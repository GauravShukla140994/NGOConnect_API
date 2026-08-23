namespace NGOConnect.Core.Models.Project;

/// <summary>
/// Returned by Project_GetCheckoutReminderTargets SP.
/// Represents a FLEXIBLE volunteer who is currently CHECKED_IN and approaching session end.
/// </summary>
public class CheckoutReminderTarget
{
    public int    UserId      { get; set; }
    public int    ProjectId   { get; set; }
    public string ProjectName { get; set; } = string.Empty;
    public string FcmToken    { get; set; } = string.Empty;
    public string EndTime     { get; set; } = string.Empty;
}
