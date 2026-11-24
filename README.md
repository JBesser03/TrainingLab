# TrainingLab

TrainingLab is a native workout tracker for iPhone and Apple Watch. It adapts workouts to how recovered you are, and all of its analysis runs on the device.

Website: <https://traininglab.besser-siegen.de>

## Features

- **Build or generate workouts.** Write your own workouts and multi-week plans, or generate them. The generator builds gym splits (Push, Pull, Legs and hybrids) around your equipment, and running plans with intervals. You can also describe a session in plain language, like "45-min upper body, dumbbells only".
- **Recovery-aware training.** A daily readiness score combines heart-rate variability, resting heart rate, sleep and recent training load. Suggestions favor your freshest muscle groups, and each workout gets a predicted difficulty.
- **Detailed logging.** Log sets and reps, supersets, warm-up and drop sets, reps in reserve, notes and a rest timer. After each workout you see your results and personal records, and progress charts track your weight or estimated one-rep max.
- **Apple Watch.** Workouts you start on the iPhone mirror to the watch in real time, with countdowns, pause from either device, rest periods and live heart rate, calories and distance.
- **System integration.** A Live Activity on the Lock Screen and Dynamic Island, a weekly goals widget, HealthKit, WorkoutKit and iCloud sync through CloudKit.
- **Private by design.** The intelligence features run on device through Apple's Foundation Models, and a deterministic fallback takes over where they're unavailable. The app has no account, no analytics and no server.
- **Six visual styles**, each with a matching app icon.
- **Localized** in English and German.

## Project layout

| Path | Contents |
| --- | --- |
| `TrainingLab.xcodeproj` | Xcode project |
| repo root, `Model/`, `Plans/`, `Workout/`, `Exercise/`, `iOS/` | iOS app (SwiftUI and SwiftData) |
| `Workout Watch App/` | watchOS app |
| `TrainingLabWidget-iOS/` | Widget and Live Activity extension |
| `WorkoutAppTests/`, `Tests iOS/` | iOS unit and UI tests (including the App Store screenshot tests) |
| `Workout Watch AppTests/`, `Workout Watch AppUITests/` | watchOS unit and UI tests |
| `Localizable.xcstrings`, `InfoPlist.xcstrings` | String catalogs (en, de) |
| `AppIcon*.icon` | App icons, one per style |

## Requirements

- Xcode 26 or later, Swift 6
- iOS 26.0 or later; watchOS 10.0 or later
- Readiness and workout data need a real device with Apple Health data. The on-device language model needs an Apple Intelligence–capable device; the Simulator uses the fallback.

## Building

1. Open `TrainingLab.xcodeproj`.
2. Under **Signing & Capabilities**, select your own development team for every target. Change the bundle identifiers (`Besser.Workout-Justus…`), the App Group (`group.Besser.Workout-Justus`) and the iCloud container (`iCloud.com.traininglab`) to identifiers your team owns. These are set in the build settings and in the `.entitlements` files.
3. Run the **Workout App (iOS)** scheme on an iPhone or simulator. The watch app is embedded in it. You can also run the **Workout Watch App** scheme on its own.

## Tests

```sh
xcodebuild test -project TrainingLab.xcodeproj -scheme "Workout App (iOS)" \
  -destination "platform=iOS Simulator,name=iPhone 17"

xcodebuild test -project TrainingLab.xcodeproj -scheme "Workout Watch App" \
  -destination "platform=watchOS Simulator,name=Apple Watch Series 9 (45mm)"
```

The UI tests accept the launch argument `-UITestSkipHealthKit`, which skips the HealthKit permission sheet and the first-run setup.

## Disclaimer

The readiness and recovery features give general fitness guidance. They are not medical advice.
