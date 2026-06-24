using Microsoft.AspNetCore.Mvc;
using NGOConnect.Core.Interfaces;
using NGOConnect.Core.Models.Common;
using NGOConnect.Core.Models.Lookup;

namespace NGOConnect.API.Controllers
{
    [ApiController]
    [Route("api/v1/[controller]")]
    [Produces("application/json")]
    public class LookupController : ControllerBase
    {
        private readonly ILookupDal _lookupDal;

        public LookupController(ILookupDal lookupDal)
        {
            _lookupDal = lookupDal;
        }

        /// <summary>Get all lookup type categories (GENDER, ORG_TYPE, etc.)</summary>
        [HttpGet("types")]
        [ProducesResponseType(typeof(ApiResponse<List<LookupTypeModel>>), 200)]
        public async Task<ApiResponse<List<LookupTypeModel>>> GetAllTypes()
            => await _lookupDal.GetAllTypesAsync();

        /// <summary>Get all values for a specific lookup type. Example: typeCode=GENDER</summary>
        [HttpGet("values/{typeCode}")]
        [ProducesResponseType(typeof(ApiResponse<List<LookupValueModel>>), 200)]
        public async Task<ApiResponse<List<LookupValueModel>>> GetValuesByType(string typeCode)
            => await _lookupDal.GetValuesByTypeCodeAsync(typeCode.ToUpper());

        /// <summary>Get a specific lookup value. Example: typeCode=GENDER, valueCode=MALE</summary>
        [HttpGet("values/{typeCode}/{valueCode}")]
        [ProducesResponseType(typeof(ApiResponse<LookupValueModel>), 200)]
        public async Task<ApiResponse<LookupValueModel>> GetValue(
            string typeCode, string valueCode)
            => await _lookupDal.GetValueByCodeAsync(typeCode.ToUpper(), valueCode.ToUpper());
    }
}
