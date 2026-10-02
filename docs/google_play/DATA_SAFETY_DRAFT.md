# Google Play Data Safety draft

Validate this draft against the production backend before submitting it in Play Console.

## Collected data

- Personal info: name, email address, user/account ID.
- Photos: inspection issue/fix evidence uploaded by authorized users.
- Other user-generated content: checklist answers, notes, signatures, approvals and corrective-action records.
- App info and performance: privacy-sanitized error type/message/stack, app version, build number and platform, linked to the authenticated user ID for operational troubleshooting.

## Use purposes

- App functionality and account management.
- Security, authorization and audit.
- Operational analytics and troubleshooting.
- Inspection reporting and corrective-action workflows.

## Sharing and security

- No advertising or marketing use.
- No sale of data.
- Data is sent to the organization’s configured Supabase service as a processor/service provider; verify the Play Console definition before declaring shared data.
- Data is encrypted in transit.
- Authentication credentials are handled by Supabase Auth; offline application data uses secure/local storage controls.

## Deletion

Entry and Viewer allow account creation. Users can start deletion from app settings and from:
https://inspection.alielhassan.com/delete-account.html

The privacy policy explains retention of inspection/audit records when a legitimate legal, security, or operational obligation applies.
