# Releases

Run `./scripts/release-github.sh --version X.Y.Z --play` to publish the Android APK to GitHub and build the Google Play AAB locally. Upload the AAB and its mapping file through Play Console.

This project currently has no iOS target or App Store release configuration. The shared release entry point recognizes `--app-store` but rejects it with a configuration error before editing versions or building. An iOS app target, signing configuration and archive builder are required before App Store releases can be enabled.

For projects with iOS configured, `--app-store` builds the archive and IPA and uploads the archive after the GitHub release succeeds. A dry run never uploads. Review submission remains a separate step in App Store Connect.
