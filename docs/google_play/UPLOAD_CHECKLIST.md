# Google Play upload checklist

- [ ] Production main includes the 1.3.6 (13) Play-readiness changes.
- [ ] Quality Gate passes when GitHub Actions billing is restored.
- [ ] Final AABs are rebuilt from the exact release commit.
- [ ] targetSdkVersion is 36+ and minSdkVersion is 24.
- [ ] APK proxy checks pass 16 KB zip alignment and 64-bit arm64-v8a support.
- [ ] Upload certificate fingerprint matches the existing Play app upload key, if these package IDs already exist in Play Console.
- [ ] Privacy-policy and account-deletion URLs are publicly reachable over HTTPS.
- [ ] Dedicated reviewer accounts are active and App access instructions are entered in Play Console.
- [ ] Data Safety answers are reviewed against the production configuration.
- [ ] Content rating, target audience, ads declaration and organization declarations are completed accurately.
- [ ] Store icon, feature graphic and phone screenshots are uploaded for Arabic and/or English listings.
- [ ] Upload to Internal testing first; install from Google Play and complete a smoke test before Production.
