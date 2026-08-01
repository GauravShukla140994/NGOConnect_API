# RippleHub Certificate Verify Page — Developer Spec

## URL Pattern
```
https://ripplehub.app/verify/{certCode}
```
Example: `https://ripplehub.app/verify/CERT-2026-000042`

---

## Purpose
Publicly accessible page that lets anyone (employer, NGO, donor) verify that a volunteer certificate
is authentic and was issued by RippleHub. No login required.

---

## API Call

```
GET https://api.ngoconnect.in/api/v1/certificates/{certCode}
Authorization: (none — endpoint is AllowAnonymous)
```

### Success Response
```json
{
  "isSuccess": 1,
  "message": "OK",
  "data": {
    "certificateId": 42,
    "certCode": "CERT-2026-000042",
    "issuedAt": "2026-07-15T10:30:00",
    "totalHours": 24.5,
    "userId": 101,
    "volunteerName": "Priya Sharma",
    "profilePhoto": "https://...",
    "projectId": 7,
    "projectName": "Tree Plantation Drive",
    "orgId": 3,
    "orgName": "GreenEarth Foundation",
    "orgLogoUrl": "https://...",
    "impactScore": 87,
    "skillRatings": "Communication:4.5|Leadership:4.0|Teamwork:5.0",
    "isDeleted": 0
  }
}
```

### Not Found / Revoked
```json
{ "isSuccess": 0, "message": "Certificate not found.", "errorCode": "NOT_FOUND" }
```

---

## Page States

### State 1 — Loading
Show a centered spinner with RippleHub logo above it and the text "Verifying certificate…"

### State 2 — Valid Certificate (`isSuccess === 1` AND `isDeleted === 0`)
Render the full certificate (use the same visual design as `ripplehub_volunteer_certificate_template.html`
in the Documents folder — it already has a `renderCertificate(data)` function).

Call `renderCertificate(data)` with the API response data object.

Below the certificate show a **trust badge strip**:
```
✅  Issued by RippleHub    |    🏛  {orgName}    |    📅 Verified {issuedAt formatted}
```

### State 3 — Not Found / Invalid Code
```
⚠️  Certificate Not Found
The certificate ID "{certCode}" does not exist in our records.
If you believe this is an error, contact support@ripplehub.app
```

### State 4 — Revoked (`isSuccess === 1` but `isDeleted === 1`)
```
🚫  Certificate Revoked
This certificate has been revoked by the issuing organisation.
Certificate ID: {certCode}
```

---

## Data Mapping (API response → certificate template)

| Template placeholder  | API field                          |
|-----------------------|------------------------------------|
| `{{CERT_ID}}`         | `certCode`                         |
| `{{ISSUED_DATE}}`     | `issuedAt` formatted as "15 Jul 2026" |
| `{{NGO_NAME}}`        | `orgName`                          |
| `{{VOLUNTEER_NAME}}`  | `volunteerName`                    |
| `{{PROJECT_NAME}}`    | `projectName`                      |
| `{{TOTAL_HOURS}}`     | `totalHours`                       |
| `{{IMPACT_SCORE}}`    | `impactScore`                      |
| `{{SKILL_CHIPS}}`     | Parse `skillRatings` string (pipe-separated `Name:Rating` pairs) |
| `{{VERIFY_LINK}}`     | Current page URL (`window.location.href`) |
| `{{COORDINATOR_NAME}}`| `orgName` coordinator (use "NGO Coordinator" as fallback) |

### Parsing `skillRatings`
```js
// "Communication:4.5|Leadership:4.0|Teamwork:5.0"
const skills = (data.skillRatings ?? '').split('|').filter(Boolean).map(pair => {
  const [name, rating] = pair.split(':');
  return { name, rating: parseFloat(rating) };
});
```

---

## Page Structure (HTML / React / Next.js)

```
<head>
  <!-- Open Graph for link previews -->
  <meta property="og:title" content="{volunteerName} — Volunteer Certificate" />
  <meta property="og:description" content="Issued by {orgName} via RippleHub for {projectName}" />
  <meta property="og:image" content="https://ripplehub.app/og-certificate.png" />

  <!-- Canonical -->
  <link rel="canonical" href="https://ripplehub.app/verify/{certCode}" />
</head>

<body>
  <!-- Minimal header: RippleHub logo + "Certificate Verification" label -->
  <header> ... </header>

  <!-- Certificate rendering area (iframe or inline) -->
  <main id="cert-container"> ... </main>

  <!-- Trust strip (shown only on valid certs) -->
  <div class="trust-strip"> ... </div>

  <!-- Minimal footer: "Powered by RippleHub" + support email -->
  <footer> ... </footer>
</body>
```

---

## Implementation Notes

- **Framework:** Next.js or plain HTML+JS (your call; page is static except for the fetch)
- **certCode from URL:** Use `useRouter().query.certCode` (Next.js) or `window.location.pathname.split('/').pop()`
- **Certificate HTML:** Embed `ripplehub_volunteer_certificate_template.html` as an `<iframe srcdoc="...">` OR inline the HTML+CSS directly — the template is self-contained
- **Print button:** Add a "Download / Print" button that calls `window.print()` — the template already has `@media print` styles
- **No auth required:** The API endpoint is public (`[AllowAnonymous]`)
- **Error handling:** Always handle network errors (show "Could not connect" if fetch fails)
- **Mobile responsive:** The certificate template already has responsive CSS; ensure page padding is minimal on mobile

---

## Security Considerations

- The certCode is opaque (CERT-2026-NNNNNN) — not guessable by sequential scan because numbers are sparse
- No PII beyond volunteerName and profilePhoto is exposed — this is intentional (public verify page)
- The API returns `isDeleted` flag — always check it and show "Revoked" state if true
- Do NOT cache the response locally (certificates can be revoked)
