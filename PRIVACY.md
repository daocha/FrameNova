# FrameNova privacy policy

Last updated: 8 November 2026

This policy covers FrameNova for Android and iOS, including the Google Play, App Store and GitHub Android releases.

FrameNova is a multi-track video editor. Your projects and media are processed on your device and are not sent to the developer. The app has no account, analytics, advertising or tracking, and does not sell personal data. The referral program described below uses a device identifier.

## Your photos, videos and audio

FrameNova reads the photos, videos and audio you choose to show, edit and export them. Projects, imported copies and temporary working files stay on your device. Exports and batch results are saved only to the places you choose.

- **Android:** media-library browsing requests the permissions needed for your Android version. Where supported, you can grant access to selected photos and videos rather than your whole library. Files selected through a system picker, such as audio and subtitle files, are accessed through that picker. Saving to a folder uses the system folder picker.
- **iOS:** browsing photos and videos requests access to your Photos library, which you can limit to selected items. Saving exports and batch results to Photos requests add-only access. Audio and other files are selected through the system file picker.
- **Microphone:** used only while you record a voiceover. The recording is saved in your project.
- **Notifications (Android):** show progress and completion of exports and batch tasks. Denying the permission does not stop the work.

You can manage permissions in your device's settings. If you select media from a cloud-backed library or file provider, the operating system or provider may download it. If you save or share an export to a cloud-backed location or another app, that service handles it under its own privacy policy. FrameNova does not operate a media-upload service.

## Network and updates

- **Fonts:** Traditional Chinese and some other fonts download once, only when you ask for them, from a public font repository on GitHub, and are then kept on your device. GitHub receives ordinary connection information, including your IP address and the font file requested, and handles it under its own privacy policy.
- **Google Play Android version:** Google Play handles updates. Besides the fonts above, the app contacts only the referral service below.
- **App Store iOS version:** Apple handles App Store and TestFlight distribution. The app asks Apple's public App Store lookup service whether a newer version exists, sending the app's bundle ID and no media or settings. It also contacts the referral service below.
- **GitHub Android version:** connects to GitHub to check for updates and download an update when you choose. These requests contain none of your media or app settings. GitHub receives ordinary connection information, including your IP address, and handles it under its own privacy policy. The app also contacts the referral service below.

Apple, Google and any file or sharing providers you choose operate independently of FrameNova. Their services are governed by their respective privacy policies and your account settings.

## Referral program

The referral program lets you invite friends and unlock batch processing. In versions with the program enabled, the app contacts the developer's referral service automatically on first launch, whether or not you use referrals. If that request fails, the app tries again on later launches until it succeeds.

- **What is sent on first launch:** the app's package or bundle ID and a device identifier. The identifier is a SHA-256 hash made from the app's ID and your device's Android ID or iOS identifier for vendor. The raw device ID is not sent. Your referral code is derived from this hash.
- **What else is sent when you use the program:** any referral or unlock code you submit, and a security proof from your device. The proof comes from Android Key Attestation or Apple App Attest, and on iOS, Apple's service is involved in producing it.
- **What the service stores:** the device identifier and when it was registered, your referral code, which code you entered, how many devices entered yours, your unlocks, unlock code redemptions, and security records such as device key bindings and short-lived challenges.
- **What it is used for:** making your code valid for friends, crediting referrals, restoring your referral code and unlocks after you clear app data or reinstall, and preventing abuse. It is not used for advertising or to track you across apps.
- **Connection information:** the service limits requests by IP address, keeping those counts briefly in memory. The server or hosting provider may also keep ordinary connection logs.
- **How long it is kept:** these records have no automatic expiry, because they keep each referral permanent and enforce limits. Clearing app data or uninstalling does not delete them, and your device identifier normally stays the same afterwards.
- **Removing your records:** open an issue at the address below and include your referral code, shown in Settings. Removal can take away restored unlocks and referral credit.

The identifier is pseudonymous, not anonymous: it is persistent and tied to your device. Anyone who knows your full device identifier could read your referral progress from the service, but it does not contain your name or contact details.

When you tap **Invite**, the invite text is copied to your clipboard and the system share sheet opens. The app you choose handles the text under its own privacy policy. The invite contains your referral code, and each person who enters it adds to your count.

## Settings and saved files

Projects, language, theme, editing preferences and your saved referral state are stored on your device. The developer has no access to the copy on your device; the referral service keeps its own records as described above. Deleting a project removes it from the app, and removing the app removes its projects and settings. You control the original media and exported copies; removing the app does not remove files saved to Photos, shared storage, other apps or cloud providers. Delete those copies from their respective locations if you no longer want them.

Batch tools work on one file at a time and leave your originals unchanged. On iOS, files copied in for a batch are temporary and are removed when the batch finishes or is cancelled.

## Developer tools

Developer tools are hidden and off until you unlock them by tapping the version number in Settings ten times. They are meant for reporting problems.

While they are on, the app keeps a log on your device, which can include the names of your files. A saved log is a copy of your data. Nothing is sent to the developer unless you choose to share it. Logs are saved or shared only when you tap the button for it, through the system save dialog or share sheet, and stay wherever you put them until you delete them.

## Children

FrameNova is not directed at children and does not knowingly collect children's personal information. It provides no advertising or tracking. The app does not ask for anyone's age, so the device identifier described above is handled the same way for every install.

## Changes and contact

Changes to this policy are published in this file with an updated date. For questions, open an issue at https://github.com/daocha/FrameNova/issues. GitHub issues are public: do not include private media or other sensitive information. Information you voluntarily include in a support request is visible to its recipients and is handled by the support platform under its own privacy policy.
