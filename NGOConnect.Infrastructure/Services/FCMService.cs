using FirebaseAdmin;
using FirebaseAdmin.Messaging;
using Google.Apis.Auth.OAuth2;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using NGOConnect.Core.Interfaces;
using Serilog;

namespace NGOConnect.Infrastructure.Services
{
    /// <summary>
    /// Firebase Cloud Messaging service — registered as Singleton.
    /// Reads credentials from Railway env var Firebase__CredentialsJson
    /// (the service-account JSON string — never committed to source control).
    /// Uses IServiceScopeFactory to resolve scoped INotificationDal for stale-token cleanup.
    /// </summary>
    public class FCMService : IFCMService
    {
        private readonly bool                 _ready;
        private readonly IServiceScopeFactory _scopeFactory;

        public FCMService(IConfiguration config, IServiceScopeFactory scopeFactory)
        {
            _scopeFactory = scopeFactory;
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
            int?    refId       = null,
            string? refType     = null,
            string? imageUrl    = null,
            string? deepLink    = null,
            string? actionLabel = null)
        {
            if (!_ready || string.IsNullOrWhiteSpace(token)) return false;

            try
            {
                var message = new Message
                {
                    Token = token,
                    // Android: data-only (no Notification object) so FCM does NOT auto-display.
                    // Our JS background/foreground handler calls notifee with Date.now() as
                    // the timestamp — this is what was showing a frozen wrong date when FCM
                    // auto-displayed using its own (often wrong) event_time default.
                    // iOS: APNS alert handles display natively (no JS involvement for background).
                    Data  = BuildData(notifType, refId, refType, deepLink, actionLabel, title, body, imageUrl),
                    Android = new AndroidConfig
                    {
                        Priority = Priority.High,
                        // No AndroidConfig.Notification — keeps Android data-only
                    },
                    Apns = new ApnsConfig
                    {
                        Aps = new Aps
                        {
                            Alert = new ApsAlert { Title = title, Body = body },
                            Sound = "default",
                            Badge = 1,
                        }
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
            int?    refId       = null,
            string? refType     = null,
            string? imageUrl    = null,
            string? deepLink    = null,
            string? actionLabel = null)
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
                var data          = BuildData(notifType, refId, refType, deepLink, actionLabel, title, body, imageUrl);
                var staleTokens   = new List<string>();
                var totalSuccess  = 0;

                for (int i = 0; i < tokenList.Count; i += batchSize)
                {
                    var batch = tokenList.Skip(i).Take(batchSize).ToList();
                    var multicast = new MulticastMessage
                    {
                        Tokens  = batch,
                        // Android: data-only — same as SendAsync; see comment there.
                        // iOS: APNS alert for native background display.
                        Data    = data,
                        Android = new AndroidConfig
                        {
                            Priority = Priority.High,
                            // No AndroidConfig.Notification — keeps Android data-only
                        },
                        Apns = new ApnsConfig
                        {
                            Aps = new Aps
                            {
                                Alert = new ApsAlert { Title = title, Body = body },
                                Sound = "default",
                                Badge = 1,
                            }
                        }
                    };

                    var result = await FirebaseMessaging.DefaultInstance.SendEachForMulticastAsync(multicast);
                    totalSuccess += result.SuccessCount;

                    if (result.FailureCount > 0)
                    {
                        Log.Warning("FCMService multicast: {Failed}/{Total} failed", result.FailureCount, batch.Count);
                        for (int j = 0; j < result.Responses.Count; j++)
                        {
                            var resp = result.Responses[j];
                            if (!resp.IsSuccess)
                            {
                                Log.Warning("FCMService token[{Index}] error: {Code} — {Msg}",
                                    j,
                                    resp.Exception?.MessagingErrorCode,
                                    resp.Exception?.Message);

                                // Collect stale tokens for cleanup
                                if (resp.Exception?.MessagingErrorCode == MessagingErrorCode.Unregistered)
                                    staleTokens.Add(batch[j]);
                            }
                        }
                    }
                }

                // Fire-and-forget stale token cleanup (scope needed — FCMService is Singleton)
                if (staleTokens.Count > 0)
                    _ = Task.Run(async () =>
                    {
                        try
                        {
                            using var scope = _scopeFactory.CreateScope();
                            var notif = scope.ServiceProvider.GetRequiredService<INotificationDal>();
                            foreach (var t in staleTokens)
                                await notif.DeleteStaleTokenAsync(t);
                            Log.Information("FCMService cleaned up {Count} stale token(s)", staleTokens.Count);
                        }
                        catch (Exception ex)
                        {
                            Log.Error(ex, "FCMService stale token cleanup failed");
                        }
                    });

                // v5.0 FIX: this used to unconditionally `return true` here regardless of
                // per-token delivery outcome — meaning a fully-failed multicast (every
                // token invalid/stale/mismatched) still reported success as long as the
                // Firebase Admin SDK call itself didn't throw. That made "Test send
                // completed" lie whenever every token failed silently. Now reflects
                // whether at least one message actually succeeded.
                return totalSuccess > 0;
            }
            catch (Exception ex)
            {
                Log.Error(ex, "FCMService.SendMulticastAsync failed");
                return false;
            }
        }

        // ── Helpers ──────────────────────────────────────────────────────────────

        // All display fields go into Data so our JS notifee handler controls the timestamp
        // (Date.now()) instead of FCM auto-displaying with a wrong/frozen event_time.
        // title/body/imageUrl are included so the JS handler can render the notification
        // identically to what we previously put in Message.Notification.
        private static Dictionary<string, string> BuildData(
            string  notifType,
            int?    refId       = null,
            string? refType     = null,
            string? deepLink    = null,
            string? actionLabel = null,
            string? title       = null,
            string? body        = null,
            string? imageUrl    = null)
        {
            var data = new Dictionary<string, string> { ["notifType"] = notifType };
            if (refId.HasValue)                          data["refId"]       = refId.Value.ToString();
            if (refType       != null)                   data["refType"]     = refType;
            if (!string.IsNullOrWhiteSpace(deepLink))    data["deepLink"]    = deepLink;
            if (!string.IsNullOrWhiteSpace(actionLabel)) data["actionLabel"] = actionLabel;
            if (!string.IsNullOrWhiteSpace(title))       data["title"]       = title;
            if (!string.IsNullOrWhiteSpace(body))        data["body"]        = body;
            if (!string.IsNullOrWhiteSpace(imageUrl))    data["imageUrl"]    = imageUrl;
            return data;
        }

        private static string MaskToken(string token) =>
            token.Length > 10 ? token[..8] + "..." : "***";
    }
}
