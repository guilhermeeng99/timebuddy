# Android Release Signing

> **Steps 1 to 4 are already done.** The keystore exists at
> `android/timebuddy-release.jks` (gitignored), `android/key.properties` points
> at it, and its SHA-1 `44:E4:2A:6D:11:5B:92:72:17:FB:C8:4B:01:A4:D2:9E:8D:63:E1:68`
> is registered on the Firebase project alongside the debug one. A release APK
> was built and verified to carry that certificate.
>
> The keystore and its passphrase are in `~/Downloads/timebuddy-release-signing/`
> so they can be moved somewhere durable. **Step 5 is still open** and it is the
> one that breaks sign-in for real users.

The steps below are kept because they are what to do on a new machine, for a new
project, or if the key is ever rotated.

Until step 2 is done, `flutter build apk --release` still works: the Gradle
config falls back to the debug key so a fresh clone and CI keep building. That
fallback is a convenience and never a shipping path. An APK signed with the
debug key cannot be uploaded to the Play Store, and Google sign-in fails on it.

---

## Why this file exists

Google sign-in on Android does not check a package name alone. It checks the
**signing certificate** of the APK that is asking, against the SHA-1
fingerprints registered on the Firebase project. A fingerprint that is not
registered gets `ApiException: 10`, a developer error with no useful message.

The debug fingerprint is already registered, which is why sign-in works on a
build from this machine. Nothing else is.

---

## 1. Generate the keystore

Choose a password you can recover. **If this file is lost, the app can never be
updated on the Play Store again**: Google identifies your app by this key, and
there is no reset. Back it up somewhere that survives this machine dying, and
put the passwords in a password manager.

```bash
keytool -genkey -v -keystore android/timebuddy-release.jks -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias timebuddy
```

`android/.gitignore` already excludes `*.jks`, `*.keystore` and
`key.properties`, so none of this can be committed by accident.

## 2. Point the build at it

Copy `android/key.properties.example` to `android/key.properties` and fill in
the two passwords and the alias. `storeFile` is resolved relative to `android/`,
so a keystore created by the command above needs no change.

Then confirm the build picked it up:

```bash
flutter build appbundle
```

## 3. Read the fingerprint

```bash
keytool -list -v -alias timebuddy -keystore android/timebuddy-release.jks
```

Copy the `SHA1:` line. It looks like `AB:CD:EF:...`, twenty pairs.

## 4. Register it with Firebase

```bash
firebase apps:android:sha:create 1:193230138114:android:bf7d01bf886fbfa8d5701b <SHA-1> --project timebuddy-app-2026
```

Then regenerate the config, because enabling a new fingerprint mints a new OAuth
client and `google-services.json` has to carry it:

```bash
flutterfire configure --project=timebuddy-app-2026 --platforms=android,web --yes
```

Commit the regenerated `android/app/google-services.json`. It holds no secret:
these values identify the project, they do not authorise anything. The Firestore
rules are what authorise.

---

## 5. The step that catches people: Play App Signing

If you upload through Google Play (the default for new apps), **Google re-signs
your app with a key it holds**. The certificate on the device is then Google's,
not yours, so the fingerprint from step 3 is *not* the one the installed app
presents. Sign-in works in your local release build and fails for everyone who
installs from the Play Store, which is the worst possible time to find out.

After creating the app in the Play Console, go to
**Release, Setup, App signing** and copy the SHA-1 under **App signing key
certificate**. Register that one too, exactly as in step 4. You end up with
three fingerprints on the project, and all three are correct:

| Fingerprint | Which build presents it |
|---|---|
| Debug | `flutter run` from a developer machine |
| Upload key (steps 1 to 4) | The bundle you upload; Play verifies it is from you |
| Play app signing key | What users actually install |

## 6. Verify before you trust it

Sign in on a build installed the way a user would install it, not on
`flutter run`. An `ApiException: 10` means the presented fingerprint is not
registered; list what Firebase has and compare:

```bash
firebase apps:android:sha:list 1:193230138114:android:bf7d01bf886fbfa8d5701b --project timebuddy-app-2026
```
