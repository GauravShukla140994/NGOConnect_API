# RippleHub — Server Setup Reference
*Generated: 2026-08-06 | Use this file to onboard a new session for all server/infrastructure work*

---

## 1. Project Identity

- **App Name:** RippleHub (formerly NGO Connect)
- **Domain:** ripplehub.app
- **API Domain:** api.ripplehub.app
- **Stack:** ASP.NET Core 8, C#, MySQL 8.0, Railway (staging), Hostinger VPS (production)
- **Target Market:** India-first, 0–10K users initially

---

## 2. Current Infrastructure State

### 2.1 Railway (Staging) ✅ Working
- API deployed on Railway (auto-deploy from GitHub)
- MySQL database on Railway
- Environment variables set on Railway service
- URL: (Railway-generated staging URL)
- **Keep Railway for staging only — not for production**

### 2.2 Hostinger VPS (Production) ⏳ Not set up yet
- **Plan:** KVM 2
- **Specs:** 2 vCPU, 8GB RAM, 100GB NVMe
- **OS to install:** Ubuntu 24.04 LTS
- **Status:** Purchased, OS not configured yet
- **Purpose:** Production API + MySQL database

### 2.3 AWS S3 ✅ Working
- **Region:** ap-south-1 (Mumbai) ← important for data residency
- **Public bucket:** `ripplehub-public` (user photos, org logos, project images, post media)
- **Private bucket:** `ripplehub-private` (documents, certificates, donation receipts, DB backups)
- **IAM User:** `ripplehub-s3-service`
- **Credentials:** Stored in Railway env vars (AWS__AccessKeyId, AWS__SecretAccessKey)

### 2.4 Email — Resend ✅ Working
- **Provider:** Resend.com (HTTPS API — not SMTP, not blocked by Railway/PaaS)
- **Domain verified:** ripplehub.app on Resend dashboard
- **DNS records added:** DKIM TXT, MX (send), SPF TXT — all Verified ✅
- **Railway env vars:** `EmailProvider = resend`, `Resend__ApiKey = re_xxx`
- **Why not SMTP:** Railway blocks outbound SMTP ports (587, 465, 25)
- **Why not AWS SES:** Production access request was rejected by AWS (new account, no sending history). Can reapply after 2–3 weeks of sandbox sending history.
- **Free tier:** 3,000 emails/month

### 2.5 SMS — Fast2SMS ⚠️ Blocked
- **Provider:** Fast2SMS
- **Current route:** Quick ("q") — NOW REQUIRES APPROVAL (TRAI regulation 2024)
- **Status:** SMS stuck in "Pending" on Fast2SMS dashboard — Quick route is effectively dead
- **Solution needed:** DLT (Distributed Ledger Technology) registration with TRAI
- **Railway env var:** `Sms__ApiKey` set, `Sms__Route = q`
- **For production:** Must switch to `Route = dlt` after DLT registration

---

## 3. Key Decisions & Concerns

### 3.1 Why Hostinger VPS for Production (not Railway)
1. **Latency:** Railway has no India region. US servers = 150–250ms for Indian users. Hostinger India DC = 10–20ms.
2. **Data Localization:** India's **DPDPA 2023** (Digital Personal Data Protection Act) requires personal data of Indian citizens to be processed with appropriate safeguards. Storing volunteer PII, donor details, donation transactions on US servers creates compliance risk.
3. **Cost:** Railway scales expensively. VPS is fixed cost.

### 3.2 Data Residency Requirements (DPDPA 2023)
- RippleHub stores: volunteer personal info, donor details, donation transactions, identity documents
- All this is personal + financial data of Indian citizens
- **Must stay in India:** MySQL database on Hostinger VPS (India DC)
- **Already correct:** AWS S3 in ap-south-1 (Mumbai) ✅
- **Action:** When setting up VPS, confirm Hostinger datacenter location is India (Mumbai/Chennai)

### 3.3 Deployment Philosophy
```
Dev (local) → Railway staging → Hostinger VPS (production)
```
- Never deploy untested code directly to production VPS
- GitHub Actions handles build + deploy automatically
- Push to `main` = auto deploy to Railway staging
- Push to `release` (or manual trigger) = deploy to production VPS

---

## 4. Planned Production Architecture

| Component | Service | Location | Status |
|---|---|---|---|
| API Server | Hostinger KVM 2 VPS | India | ⏳ Not set up |
| Database | MySQL 8.0 on VPS | India | ⏳ Not set up |
| Reverse Proxy | Nginx on VPS | India | ⏳ Not set up |
| SSL | Let's Encrypt (Certbot) | — | ⏳ Not set up |
| File Storage | AWS S3 (ap-south-1) | Mumbai | ✅ Working |
| Email | Resend.com | Cloud | ✅ Working |
| SMS OTP | Fast2SMS DLT | India | ⚠️ Pending DLT registration |
| Backups | MySQL dump → S3 private bucket | Mumbai | ⏳ Not set up |
| CI/CD | GitHub Actions | — | ⏳ Not set up |
| Monitoring | Sentry (already wired in code) | Cloud | ⚠️ DSN not configured |

---

## 5. VPS Setup Plan (To Execute in New Session)

### 5.1 One-Time Ubuntu Setup
```bash
# SSH as root, then:
apt update && apt upgrade -y
adduser deploy && usermod -aG sudo deploy
apt install -y dotnet-runtime-8.0
apt install -y nginx
apt install -y mysql-server && mysql_secure_installation
apt install -y certbot python3-certbot-nginx
apt install -y awscli  # for S3 backup uploads
```

### 5.2 MySQL Setup
```sql
CREATE DATABASE ngoconnect CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'ngoconnect'@'localhost' IDENTIFIED BY '<StrongPassword>';
GRANT ALL ON ngoconnect.* TO 'ngoconnect'@'localhost';
FLUSH PRIVILEGES;
-- Then import: mysql -u root -p ngoconnect < NGOConnect_Complete_Setup_v4.6.sql
```

### 5.3 systemd Service
```ini
# /etc/systemd/system/ripplehub-api.service
[Unit]
Description=RippleHub API
After=network.target mysql.service

[Service]
User=deploy
WorkingDirectory=/var/www/ripplehub-api
ExecStart=/usr/bin/dotnet NGOConnect.API.dll
Restart=always
RestartSec=10
Environment=ASPNETCORE_ENVIRONMENT=Production
EnvironmentFile=/etc/ripplehub/env.conf

[Install]
WantedBy=multi-user.target
```

### 5.4 Environment Variables File
```bash
# /etc/ripplehub/env.conf  (chmod 600, chown deploy:deploy)
ConnectionStrings__DefaultConnection=Server=localhost;Port=3306;Database=ngoconnect;User Id=ngoconnect;Password=<pwd>;CharSet=utf8mb4;SslMode=None;
Jwt__Key=<production-jwt-key-min-32-chars>
Jwt__Issuer=NGOConnect
Jwt__Audience=NGOConnectUsers
EmailProvider=resend
Resend__ApiKey=re_xxxxxxxxxx
Email__FromAddress=no-reply@ripplehub.app
Email__FromName=RippleHub
Email__SupportAddress=support@ripplehub.app
StorageProvider=awss3
AWS__Region=ap-south-1
AWS__PublicBucket=ripplehub-public
AWS__PrivateBucket=ripplehub-private
AWS__PublicBaseUrl=https://ripplehub-public.s3.ap-south-1.amazonaws.com
AWS__AccessKeyId=<iam-access-key>
AWS__SecretAccessKey=<iam-secret-key>
Sms__ApiKey=<fast2sms-api-key>
Sms__Route=dlt
Sms__SenderId=RPPLHB
Sms__TemplateId=<dlt-template-id>
Firebase__CredentialsJson=<firebase-service-account-json>
Sentry__Dsn=<sentry-dsn>
ASPNETCORE_URLS=http://localhost:5000
```

### 5.5 Nginx Configuration
```nginx
# /etc/nginx/sites-available/ripplehub-api
server {
    listen 80;
    server_name api.ripplehub.app;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    server_name api.ripplehub.app;

    # SSL managed by Certbot
    ssl_certificate     /etc/letsencrypt/live/api.ripplehub.app/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/api.ripplehub.app/privkey.pem;

    # Security headers
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains";

    location / {
        proxy_pass         http://localhost:5000;
        proxy_http_version 1.1;
        proxy_set_header   Upgrade $http_upgrade;
        proxy_set_header   Connection keep-alive;
        proxy_set_header   Host $host;
        proxy_set_header   X-Real-IP $remote_addr;
        proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
        proxy_read_timeout 120s;
        proxy_connect_timeout 10s;
        client_max_body_size 50M;  # For video uploads
    }
}
```

### 5.6 SSL Setup
```bash
certbot --nginx -d api.ripplehub.app
# Auto-renews via cron — verify with:
certbot renew --dry-run
```

---

## 6. GitHub Actions — CI/CD Workflow

### 6.1 GitHub Secrets Required
```
VPS_HOST        = <Hostinger VPS public IP>
VPS_SSH_KEY     = <deploy user private SSH key (RSA/Ed25519)>
```

### 6.2 Workflow File
```yaml
# .github/workflows/deploy-production.yml
name: Deploy to Production

on:
  push:
    branches: [release]   # or change to [main] if single branch

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup .NET 8
        uses: actions/setup-dotnet@v4
        with:
          dotnet-version: '8.0.x'

      - name: Build & Publish
        run: |
          dotnet restore
          dotnet publish NGOConnect.API/NGOConnect.API.csproj \
            -c Release -o ./publish --no-restore

      - name: Stop API service
        uses: appleboy/ssh-action@v1
        with:
          host: ${{ secrets.VPS_HOST }}
          username: deploy
          key: ${{ secrets.VPS_SSH_KEY }}
          script: sudo systemctl stop ripplehub-api

      - name: Copy build to VPS
        uses: appleboy/scp-action@v0.1.7
        with:
          host: ${{ secrets.VPS_HOST }}
          username: deploy
          key: ${{ secrets.VPS_SSH_KEY }}
          source: "./publish/*"
          target: "/var/www/ripplehub-api"
          rm: true

      - name: Start API service
        uses: appleboy/ssh-action@v1
        with:
          host: ${{ secrets.VPS_HOST }}
          username: deploy
          key: ${{ secrets.VPS_SSH_KEY }}
          script: |
            sudo systemctl start ripplehub-api
            sleep 5
            sudo systemctl is-active ripplehub-api
```

---

## 7. Automated Backup

### 7.1 Daily MySQL Backup to S3
```bash
# /home/deploy/backup.sh
#!/bin/bash
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="/tmp/ngoconnect_$DATE.sql.gz"

mysqldump -u ngoconnect -p'<password>' ngoconnect \
  | gzip > $BACKUP_FILE

aws s3 cp $BACKUP_FILE \
  s3://ripplehub-private/db-backups/ngoconnect_$DATE.sql.gz \
  --region ap-south-1

# Retain only last 30 backups
aws s3 ls s3://ripplehub-private/db-backups/ \
  | sort | head -n -30 \
  | awk '{print $4}' \
  | xargs -I{} aws s3 rm s3://ripplehub-private/db-backups/{}

rm -f $BACKUP_FILE
echo "Backup done: $DATE"
```

```bash
# /etc/cron.d/ripplehub-backup
0 2 * * * deploy /home/deploy/backup.sh >> /var/log/ripplehub-backup.log 2>&1
```

Also enable **Hostinger daily VPS snapshots** from Hostinger dashboard (covers OS + disk level backup).

---

## 8. Pending Actions Before Go-Live

### Must-do before production launch:
- [ ] Set up Ubuntu on Hostinger KVM 2
- [ ] Install Nginx + .NET 8 + MySQL on VPS
- [ ] Import `NGOConnect_Complete_Setup_v4.6.sql` into production MySQL
- [ ] Configure `/etc/ripplehub/env.conf` with all production secrets
- [ ] Point `api.ripplehub.app` DNS A record → VPS IP (in Hostinger DNS)
- [ ] Generate SSL certificate via Certbot
- [ ] Set up GitHub Actions workflow (deploy-production.yml)
- [ ] Add `VPS_HOST` + `VPS_SSH_KEY` to GitHub Secrets
- [ ] Set up MySQL backup cron to S3
- [ ] Enable Hostinger daily VPS snapshots
- [ ] Configure Sentry DSN for production error monitoring

### Should-do (parallel track):
- [ ] DLT registration on trueconnect.jio.com (₹5,900/year PE registration) for SMS OTP
- [ ] AWS SES production access reapplication (after 2–3 weeks of sandbox sending history)

---

## 9. DNS Records Reference (Hostinger DNS Panel)

| Type | Name | Value | Purpose |
|---|---|---|---|
| A | api | `<VPS IP>` | API server |
| TXT | resend._domainkey | `p=MIGf...` | Resend DKIM |
| MX | send | `feedback-smtp.[...].amazonses.com` | Resend bounce handling |
| TXT | send | `v=spf1 include[...] ~all` | Resend SPF |
| TXT | _dmarc | `v=DMARC1; p=none; rua=mailto:dmarc@ripplehub.app` | DMARC |
| MX | mail | `<value>` | Custom MAIL FROM (AWS SES) |
| TXT | mail | `v=spf1 include:amazonses.com ~all` | SPF for SES MAIL FROM |

---

## 10. Code Reference

### Email Provider Switching
`appsettings.json` → `EmailProvider` key:
- `"smtp"` → SmtpEmailService (local dev only — Railway blocks SMTP)
- `"resend"` → ResendEmailService (staging + production)
- `"awsses"` → AwsSesEmailService (future, after SES approval)

### Storage Provider Switching
`appsettings.json` → `StorageProvider` key:
- `"local"` → LocalFileService (local dev)
- `"cloudinary"` → CloudinaryBlobService (optional staging CDN)
- `"awss3"` → AwsS3BlobService (production)

### SMS Route Switching
`appsettings.json` → `Sms:Route` key:
- `"q"` → Quick route (dead — stuck in pending due to TRAI 2024)
- `"dlt"` → Production TRAI-registered route (requires DLT approval first)

---

## 11. Project File Locations

| File | Path |
|---|---|
| Setup SQL | `Documents/NGOConnect_Complete_Setup_v4.6.sql` |
| API Docs | `Documents/API_Documentation_v4.6.docx` |
| DB Docs | `Documents/Database_Documentation_v4.6.md` |
| Postman | `Documents/NGOConnect_Postman_Collection_v4.6.json` |
| Doc Guidelines | `Documents/DOCUMENTATION_GUIDELINES.md` |
| Service Extensions | `NGOConnect.API/Extensions/ServiceCollectionExtensions.cs` |
| Email Services | `NGOConnect.Infrastructure/Services/ResendEmailService.cs` |
| SMS Service | `NGOConnect.Infrastructure/Services/Fast2SmsService.cs` |
| Blob Services | `NGOConnect.Infrastructure/Services/AwsS3BlobService.cs` |
| Dev Config | `NGOConnect.API/appsettings.Development.json` (gitignored) |
| Base Config | `NGOConnect.API/appsettings.json` |
