using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using NGOConnect.Core.Interfaces;
using NGOConnect.Core.Models.Common;
using NGOConnect.Core.Models.Community;
using System.Security.Claims;

namespace NGOConnect.API.Controllers
{
    [ApiController]
    [Route("api/v1/community")]
    [Produces("application/json")]
    public class CommunityController : ControllerBase
    {
        private readonly ICommunityDal _community;
        public CommunityController(ICommunityDal community) => _community = community;

        [HttpPost("post")] [Authorize]
        public async Task<ApiResponse<DynamicRow>> CreatePost([FromBody] CreateCommunityPostRequest request)
            => await _community.CreatePostAsync(GetUserId(), request);

        [HttpGet("feed")] [Authorize]
        public async Task<ApiResponse<PagedResult<DynamicRow>>> GetFeed(
            [FromQuery] int? orgId      = null,
            [FromQuery] int  pageNumber = 1,
            [FromQuery] int  pageSize   = 20)
            => await _community.GetFeedAsync(GetUserId(), orgId, pageNumber, pageSize);

        [HttpPost("post/{communityPostId:int}/acknowledge")] [Authorize]
        public async Task<ApiResponse> AcknowledgePost(int communityPostId)
            => await _community.AcknowledgePostAsync(communityPostId, GetUserId());

        [HttpPost("poll")] [Authorize]
        public async Task<ApiResponse<DynamicRow>> CreatePoll([FromBody] CreatePollRequest request)
            => await _community.CreatePollAsync(GetUserId(), request);

        [HttpPost("poll/{pollId:int}/vote")] [Authorize]
        public async Task<ApiResponse> Vote(int pollId, [FromBody] VoteRequest request)
            => await _community.VoteAsync(pollId, GetUserId(), request);

        [HttpPost("post/{communityPostId:int}/like")] [Authorize]
        public async Task<ApiResponse<DynamicRow>> LikePost(int communityPostId)
            => await _community.LikePostAsync(communityPostId, GetUserId());

        [HttpGet("post/{communityPostId:int}/comments")] [Authorize]
        public async Task<ApiResponse<List<DynamicRow>>> GetComments(int communityPostId)
            => await _community.GetCommentsAsync(communityPostId, GetUserId());

        [HttpPost("post/{communityPostId:int}/comment")] [Authorize]
        public async Task<ApiResponse<DynamicRow>> AddComment(int communityPostId, [FromBody] AddCommentRequest request)
            => await _community.AddCommentAsync(communityPostId, GetUserId(), request);

        [HttpPost("comment/{commentId:int}/like")] [Authorize]
        public async Task<ApiResponse<DynamicRow>> LikeComment(int commentId)
            => await _community.LikeCommentAsync(commentId, GetUserId());

        private int GetUserId()
        {
            var claim = User.FindFirst("uid") ?? User.FindFirst(ClaimTypes.NameIdentifier);
            return claim is not null && int.TryParse(claim.Value, out var id) ? id : 0;
        }
    }
}
