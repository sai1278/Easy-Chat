# Release Gap Baseline

**Date**: July 30, 2026  
**Source of Truth**: `docs/reports/production-readiness-review.md`

## Baseline Metrics
- **Current Application ID**: `com.example.frontend`
- **Approved Production Application ID**: `com.nearbyconnect.app`
- **Release Signing Configuration**: `signingConfig = signingConfigs.debug` (DEBUG SIGNING IN RELEASE TYPE)
- **Minify / R8 Configuration**: Disabled (`minifyEnabled false`, ProGuard rules empty)
- **Secrets / Keystore Handling**: Missing `key.properties` structure and release keystore documentation
- **Store Listing / Privacy Metadata**: Needs explicit Privacy Policy link reference in app / Store docs
- **CI/CD Release Capability**: Automated build/test in GitHub Actions; needs environment-injected release signing credentials

---

## Technical Action Plan
1. **Phase 2**: Migrate package/applicationId namespace to `com.nearbyconnect.app`.
2. **Phase 3**: Implement secure `key.properties` release signing configuration without committing secrets.
3. **Phase 4**: Configure R8 / ProGuard rules cleanly for release builds.
4. **Phase 5**: Build and certify release APK / AAB artifact.
5. **Phase 6**: Conduct complete endpoint / environment safety audit.
6. **Phase 11**: Generate final release certification report (`docs/reports/android-production-release-certification.md`).
