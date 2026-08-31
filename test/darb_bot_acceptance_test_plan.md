# Darb Bot Acceptance Tests

Run the focused automated test before manual testing:

```powershell
flutter test test\metro_station_schedule_test.dart
flutter analyze lib\screens\chat_bot_screen.dart lib\services\trip_analytics_service.dart lib\services\personal_trip_insights_service.dart
```

## Firebase Setup

Use three completed metro trips with this shape under separate user IDs. The
`finishedAt` values are required: incomplete trips must not be counted.

```json
{
  "App": {
    "TravelHistory": {
      "test-user-a": {
        "trip-a": {
          "mode": "metro",
          "startedAt": 1787520000000,
          "finishedAt": 1787522100000,
          "durationSeconds": 2100,
          "fromStation": "Aziziya",
          "toStation": "Al Wurud 2",
          "metroSegments": {
            "segment-a": {
              "fromStation": "Aziziya",
              "toStation": "Al Wurud 2",
              "lineKey": "blue",
              "seconds": 2100,
              "startedAt": 1787520000000,
              "finishedAt": 1787522100000
            }
          }
        }
      },
      "test-user-b": {
        "trip-b": {
          "mode": "metro",
          "startedAt": 1787523600000,
          "finishedAt": 1787525820000,
          "durationSeconds": 2220,
          "fromStation": "Aziziya",
          "toStation": "Al Wurud 2",
          "metroSegments": {
            "segment-b": {
              "fromStation": "Aziziya",
              "toStation": "Al Wurud 2",
              "lineKey": "blue",
              "seconds": 2220,
              "startedAt": 1787523600000,
              "finishedAt": 1787525820000
            }
          }
        }
      },
      "test-user-c": {
        "trip-c": {
          "mode": "metro",
          "startedAt": 1787527200000,
          "finishedAt": 1787529600000,
          "durationSeconds": 2400,
          "fromStation": "Aziziya",
          "toStation": "Al Wurud 2",
          "metroSegments": {
            "segment-c": {
              "fromStation": "Aziziya",
              "toStation": "Al Wurud 2",
              "lineKey": "blue",
              "seconds": 2400,
              "startedAt": 1787527200000,
              "finishedAt": 1787529600000
            }
          }
        }
      }
    },
    "Status": {
      "Lines": {
        "blue": {
          "state": "delay",
          "message": "Verified maintenance notice for testing.",
          "updatedAt": 1787520000000
        }
      }
    }
  }
}
```

Sign in as `test-user-a` when testing personal history. Add one unfinished
trip with no `finishedAt` and a deliberately different duration to verify that
it never affects the community average or personal history.

## Community Insights

| Prompt | Expected result |
| --- | --- |
| `How long do users usually take from Aziziya to Al Wurud 2?` | Community result based on 3 completed trips. Average rounds to `37 min`; range is `35-40 min`; Blue is a common line. |
| `كم تستغرق الرحلة من العزيزية إلى الورود 2؟` | Same historical result in Arabic. |
| `What is the fastest trip from Aziziya to Al Wurud 2?` | `35 min`, based on completed community trips. |
| `What is the longest trip from Aziziya to Al Wurud 2?` | `40 min`, based on completed community trips. |
| Add an unfinished fourth trip, then repeat the first prompt. | The result remains `37 min` from 3 samples. |
| Remove all completed matching trips. | Bot says no completed community data is available; it may show a clearly-labelled route-planning fallback only for the average request. |

## Personal History And Suggestions

| Prompt or action | Expected result |
| --- | --- |
| Open Darb Bot after signing in as `test-user-a`. | Smart suggestions include a route based on completed history after Firebase loads. |
| Open the bot between 5:00 AM and 11:00 AM. | A route-style morning suggestion is shown when frequent trip data exists. |
| `Show my last trip` | Shows the latest completed trip, route, duration, and completion time. |
| `How much time did I spend commuting this week?` | Sums completed trips whose finish time is this week; unfinished trips are excluded. |
| `What was my most-used line?` | Returns Blue for the fixture above. |
| Sign out, then ask a personal-history question. | Bot says it cannot find completed trips rather than exposing another user's data. |

## Station Intelligence And Arabic

| Prompt | Expected result |
| --- | --- |
| `Nearest station` with location permission granted. | Returns the nearest station and the map action. |
| `Station information for KAFD` | Shows line(s), direction-specific first/last service times, and interchange information where the station is shared by lines. |
| `Is KAFD wheelchair accessible?` | Does not invent an answer. It states that verified station-specific accessibility data is not in Darb yet. |
| `What line serves KAFD?` | Shows the line(s) from Darb station data. |
| `معلومات محطة عزيزيه` | Resolves the Saudi Arabic alias and returns an Arabic RTL answer. |
| `How long from العزيزية to Al Wurud 2?` | Resolves mixed Arabic/English station names. |

## Service Awareness

| Prompt | Expected result |
| --- | --- |
| `Is the metro open now?` | Displays the published current open/close state and no unverified service claim. |
| `What time does Blue Line close?` | Shows the earliest/latest listed Blue departures and explains they vary by station and direction. |
| `Blue Line service update` | Shows the fixture's verified maintenance notice. |
| Remove `App/Status/Lines/blue`, then repeat the previous prompt. | States that no verified update is available. |

## Notification Controls

Run these tests on a physical Android device with notification permission
granted. Start an active metro trip after each setting change when required.

| Prompt | Expected result |
| --- | --- |
| `Remind me before metro closes` | Closing reminders are enabled and the existing metro close scheduler is activated. |
| `Turn off transfer alerts` | Transfer alerts are disabled; destination alerts remain unchanged. |
| `Notify me when I am two stations away` | Destination alerts are enabled. During a trip, Darb sends the existing two-stations-remaining alert once. |
| `Turn off the two stations alert` | The two-stations-remaining alert does not appear on the next active trip. |
| Restart the application after each command. | The chosen setting persists because it is stored through `TripNotificationSettings`. |

## Regression Checks

| Scenario | Expected result |
| --- | --- |
| Existing route request: `from KAFD to STC` | Opens the existing map-routing action. |
| Existing location permission denied. | Nearest-station request shows a clear permission message. |
| Firebase is offline. | Personal, community, and service queries show a safe retry/fallback message; chat remains usable. |
| Arabic device locale. | Bot bubbles, station cards, prompts, and direction text render RTL. |
