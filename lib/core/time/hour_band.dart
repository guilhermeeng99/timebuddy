import 'package:timebuddy/core/time/working_hours.dart';

/// How reachable a person in a given zone is at a given local hour.
///
/// The band is always derived from the current preferences, never stored on an
/// entity (design_system, hour band rule), because the working window can
/// change at any moment and a cached band would outlive it.
enum HourBand { good, fair, poor, night }

/// Classifies [localHour] (`0..23`) against the user's [workingHours].
///
/// The order of the checks is part of the contract, not an implementation
/// detail. Working-hours membership is tested **before** the fixed night
/// window on purpose: a night-shift user with a `22:00-06:00` window is awake
/// and available at 23:00, so that hour must read [HourBand.good]. Letting the
/// 23:00-06:59 night window win first would paint their entire shift as
/// asleep, which is exactly the population this app must not get wrong.
///
/// ```dart
/// hourBandFor(23, const WorkingHours(startHour: 22, endHour: 6)); // good
/// hourBandFor(23, WorkingHours.defaultHours);                     // night
/// hourBandFor(8, WorkingHours.defaultHours);                      // fair
/// hourBandFor(19, WorkingHours.defaultHours);                     // poor
/// ```
HourBand hourBandFor(int localHour, WorkingHours workingHours) {
  if (workingHours.contains(localHour)) return HourBand.good;

  // The hour immediately before or after the window: reachable, at a cost.
  final isShoulder =
      workingHours.contains((localHour + 1) % 24) ||
      workingHours.contains((localHour + 23) % 24);
  if (isShoulder) return HourBand.fair;

  if (localHour >= 23 || localHour < 7) return HourBand.night;
  return HourBand.poor;
}
