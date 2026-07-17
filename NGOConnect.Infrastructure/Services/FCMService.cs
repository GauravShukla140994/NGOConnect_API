using FirebaseAdmin;
using FirebaseAdmin.Messaging;
using Google.Apis.Auth.OAuth2;
using Microsoft.Extensions.Configuration;
using NGOConnect.Core.Interfaces;
using Serilog;

namespace NGOConnect.Infrastructure.Services
{
    /// <summary>
    /// Firebase Cloud Messaging service.
    /// Reads credentials from Railway env var FIREBASE_CREDENTIALS_JSON
    /// (the service-account JSON string — never committed to source control).
    /// </summary>
    public class FCMService : IFCMService
    {
        private readonly bool _ready;

        public FCMService(IConfiguration config)
        {
            try
            {
                // Already initialised (singleton — only runs once across DI lifetime)
                if (FirebaseApp.DefaultInstance != null)
                {
                    _ready = true;
                    return;
                }

                var credJson = config["Firebase:CredentialsJson"];
                if (string.IsNullOrWhiteSpace(credJson))
                {
                    Log.Warning("FCMService: Firebase:CredentialsJson not configured — push notifications disabled.");
                    return;
                }

                FirebaseApp.Create(new AppOptions
                {
                    Credential = GoogleCredential.FromJson(credJson)
                });

                _ready = true;
                Log.Information("FCMService initialised.");
            }
            catch (Exception ex)
            {
                Log.Error(ex, "FCMService failed to initialise.");
            }
        }

        public async Task<bool> SendAsync(
            string token,
            string title,
            string body,
            string notifType,
            int?   refId    = null,
            string? refType = null)
        {
            if (!_ready || string.IsNullOrWhiteSpace(token)) return false;

            try
            {
                var message = new Message
                {
                    Token        = token,
                    Notification = new Notification { Title = title, Body = body },
                    Data         = BuildData(notifType, refId, refType),
                    Android      = new AndroidConfig
                    {
                        Priority         = Priority.High,
                        Notification     = new AndroidNotification
                        {
                            Sound        = "default",
                            ChannelId    = "ngoconnect_default"
                        }
                    },
                    Apns = new ApnsConfig
                    {
                        Aps = new Aps { Sound = "default", Badge = 1 }
                    }
                };

                await FirebaseMessaging.DefaultInstance.SendAsync(message);
                return true;
            }
            catch (FirebaseMessagingException fex) when (
                fex.MessagingErrorCode is MessagingErrorCode.Unregistered
                                       or MessagingErrorCode.InvalidArgument)
            {
                // Stale token — safe to ignore; token cleanup can run via a job
                Log.Warning("FCMService.SendAsync stale token removed: {ErrorCode}", fex.MessagingErrorCode);
                return false;
            }
            catch (Exception ex)
            {
                Log.Error(ex, "FCMService.SendAsync failed token={Token}", MaskToken(token));
                return false;
            }
        }

        public async Task<bool> SendMulticastAsync(
            IEnumerable<string> tokens,
            string title,
            string body,
            string notifType,
            int?   refId    = null,
            string? refType = null)
        {
            if (!_ready) return false;

            var tokenList = tokens
                .Where(t => !string.IsNullOrWhiteSpace(t))
                .Distinct()
                .ToList();

            if (tokenList.Count == 0) return false;

            try
            {
                // Firebase limits multicast to 500 tokens per call
                const int batchSize = 500;
                var data = BuildData(notifType, refId, refType);

                for (int i = 0; i < tokenList.Count; i += batchSize)
                {
                    var batch = tokenList.Skip(i).Take(batchSize).ToList();
                    var multicast = new MulticastMessage
                    {
                        Tokens       = batch,
                        Notification = new Notification { Title = title, Body = body },
                        Data         = data,
                        Android      = new AndroidConfig
                        {
                            Priority     = Priority.High,
                            Notification = new AndroidNotification
                            {
                                Sound     = "default",
                                ChannelId = "ngoconnect_default"
                            }
                        },
                        Apns = new ApnsConfig
                        {
                            Aps = new Aps { Sound = "default", Badge = 1 }
                        }
                    };

                    var result = await FirebaseMessaging.DefaultInstance.SendEachForMulticastAsync(multicast);
                    if (result.FailureCount > 0)
                    {
                        Log.Warning("FCMService multicast: {Failed}/{Total} failed", result.FailureCount, batch.Count);
                        for (int j = 0; j < result.Responses.Count; j++)
                        {
                            var resp = result.Responses[j];
                            if (!resp.IsSuccess)
                                Log.Warning("FCMService token[{Index}] error: {Code} — {Msg}",
                                    j,
                                    resp.Exception?.MessagingErrorCode,
                                    resp.Exception?.Message);
                        }
                    }
                }

                return true;
            }
            catch (Exception ex)
            {
                Log.Error(ex, "FCMService.SendMulticastAsync failed");
                return false;
            }
        }

        // ── Helpers ──────────────────────────────────────────────────────────────

        private static Dictionary<string, string> BuildData(string notifType, int? refId, string? refType)
        {
            var data = new Dictionary<string, string> { ["notifType"] = notifType };
            if (refId.HasValue) data["refId"]   = refId.Value.ToString();
            if (refType != null) data["refType"] = refType;
            return data;
        }

        private static string MaskToken(string token) =>
            token.Length > 10 ? token[..8] + "..." : "***";
    }
}
