using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using NGOConnect.Core.Interfaces;
using NGOConnect.Core.Models.Common;
using NGOConnect.Core.Models.Post;
using System.Security.Claims;

namespace NGOConnect.API.Controllers
{
    [ApiController]
    [Route("api/v1")]
    [Produces("application/json")]
    public class PostController : ControllerBase
    {
        private readonly IPostDal _post;
        public PostController(IPostDal post) => _post = post;

        [HttpPost("post")] [Authorize]
        public async Task<ApiResponse<DynamicRow>> Create([FromBody] CreatePostRequest request)
            => await _post.CreateAsync(GetUserId(), request);

        [HttpGet("feed")] [Authorize]
        public async Task<ApiResponse<PagedResult<DynamicRow>>> GetFeed(
            [FromQuery] int pageNumber = 1,
            [FromQuery] int pageSize   = 20)
            => await _post.GetFeedAsync(GetUserId(), pageNumber, pageSize);

        [HttpGet("post/{postId:int}")]
        public async Task<ApiResponse<DynamicRow>> GetById(int postId)
            => await _post.GetByIdAsync(postId, GetUserId());

        [HttpDelete("post/{postId:int}")] [Authorize]
        public async Task<ApiResponse> Delete(int postId)
            => await _post.DeleteAsync(postId, GetUserId());

        [HttpPost("post/{postId:int}/pin")] [Authorize]
        public async Task<ApiResponse> Pin(int postId)
            => await _post.PinAsync(postId, GetUserId());

        [HttpPost("post/{postId:int}/like")] [Authorize]
        public async Task<ApiResponse> Like(int postId)
            => await _post.LikeAsync(postId, GetUserId());

        [HttpDelete("post/{postId:int}/like")] [Authorize]
        public async Task<ApiResponse> Unlike(int postId)
            => await _post.UnlikeAsync(postId, GetUserId());

        [HttpPost("post/{postId:int}/comments")] [Authorize]
        public async Task<ApiResponse<DynamicRow>> AddComment(int postId, [FromBody] AddCommentRequest request)
            => await _post.AddCommentAsync(postId, GetUserId(), request);

        [HttpGet("post/{postId:int}/comments")]
        public async Task<ApiResponse<PagedResult<DynamicRow>>> GetComments(
            int postId,
            [FromQuery] int pageNumber = 1,
            [FromQuery] int pageSize   = 20)
            => await _post.GetCommentsAsync(postId, pageNumber, pageSize);

        [HttpPost("post/{postId:int}/report")] [Authorize]
        public async Task<ApiResponse> Report(int postId, [FromBody] ReportPostRequest request)
            => await _post.ReportAsync(postId, GetUserId(), request);

        private int GetUserId()
        {
            var claim = User.FindFirst("uid") ?? User.FindFirst(ClaimTypes.NameIdentifier);
            return claim is not null && int.TryParse(claim.Value, out var id) ? id : 0;
        }
    }
}
