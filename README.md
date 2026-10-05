# Between

A private, local-first Flutter app for tracking what you spend, on your own or shared with friends, and what's owed between you. Every record stays in a SQLite database on the device: no accounts, cloud sync, bank connections, or messages sent for you.

Target platforms: Android and iOS.

## How it works

Every action starts from a slash command. Tap one of the shortcuts above the command bar, or type `/` and pick one. The app then asks one question per page and builds the record as you answer.

| Command | Questions, in order |
| --- | --- |
| `/expense` | What was it for? · Which category? · Which bill? · How much? · How many units? · Who shared it? · Who paid? · How to split it |
| `/sent` | How much? · To whom? · Which bill? · Which expenses? |
| `/receive` | How much? · From whom? · Which bill? · Which expenses? |
| `/bill` | What's it called? |
| `/friend` | What's their name? |
| `/category` | What's it called? |
| `/spending` | Opens where your money went, month by month |
| `/undo` | Reverts the last change |

- **Defaults are filled in.** The category starts as none, the bill as General, the quantity as 1, the payer as you, the split as equal (or by quantity when there is more than one unit), and a payment's expenses as none (toward the overall balance). Accepting a default is one tap.
- **Questions that don't apply are skipped.** An expense nobody shared is just yours, so who paid and how to split it are only asked once you pick a friend. Splitting by quantity appears only when there is more than one unit. Started from a bill's or friend's page, that answer is filled in and skipped, but still shows as a chip.
- **Answers so far show as chips** at the top of every page, for example `Pizza · in Goa trip · ₹1,200 · 4 units`. Tap one to change it; the flow then returns to the first question that needs another look, or straight to the review.
- **Back goes to the previous page**, including the system back gesture, and keeps every answer. Closing a flow asks first only if answers would be lost.
- **A review card** shows each person's share, who will owe whom, and your spending for the month before you save. Its date is today; tap it to pick another day.
- **Every save can be undone** from the snackbar, or later with `/undo`.
- **New friends, bills and categories can be added from a picker** by typing a name. They are saved together with the record, so cancelling leaves nothing behind.

Tap any expense or payment to open it on its review card. Tap an answer to edit it, or use the bin icon to delete the record. A friend's page records money sent or received with the friend filled in, and a bill's page adds expenses to that bill.

## Spending

`/spending`, or the "Spent in" row on the home screen, shows one month at a time:

- What you spent, and how it compares with the month before. The current month is compared with the same days of last month.
- Your spending by category and by bill, as bars of each one's share. Expenses without a category are grouped last, under "No category".
- Every expense with your share in it, biggest first. Tap a category or bill to narrow the list; tap an expense to edit it.

Spending is your share of each expense: all of an expense that was just yours, your part of a split one. Money you paid for friends isn't spending, it's what they owe you, and payments between you never count.

Categories are your own; there is no preset list. Add them with `/category`, by typing a name on the category question, or from the tag icon on the spending page, where they can also be renamed and deleted. Deleting a category keeps its expenses, without a category.

## Getting started

Requirements: Flutter 3.44 (stable channel, Dart 3.12) and an Android emulator or device, or Xcode with an iOS simulator.

```sh
flutter pub get
flutter run
```

## Project structure

```
lib/
  main.dart              App entry, loading and load-error screens
  theme.dart             Material 3 theme (light and dark), balance and chart colours
  data/
    money.dart           Paise formatting, parsing, and exact apportioning
    ledger.dart          Friend, Bill, Category, Expense, Payment, balance queries
    spending.dart        Your spending in a month, by category and by bill
    store.dart           Persistence (SQLite), undo, and upgrading old data
  flows/
    ask.dart             Question types: text, amount, count, pick, multi-pick, split
    flows.dart           The command flows: expense, payment, bill, friend, category
  screens/
    flow_screen.dart     Runs a flow: step bar, answer chips, review, saving
    ask_views.dart       The input for each question type
    home_screen.dart     Balances, bills, recent activity, and the command bar
    friend_screen.dart   One friend's balance and history
    bill_screen.dart     One bill's expenses and balances
    spending_screen.dart A month of spending: total, comparison, bars, expenses
    categories_screen.dart  Adding, renaming and deleting categories
    widgets.dart         Shared rows, labels, and the undo snackbar
test/                    Unit tests for data and flows, widget tests for every flow
```

### Adding or changing a question

A flow is plain Dart with no widgets in it. It holds its questions as `Ask` objects and lists the ones that currently apply in `asks`:

```dart
@override
List<Ask> get asks => [
  name, category, bill, amount, quantity, people,
  if (_shared) ...[payer, split],
];
```

`FlowScreen` shows the first question that is unanswered or no longer valid, so a conditional question is just an `if` in that list. Each `Ask` reports its own `problem` (or null) and a short `phrase` for its chip. A flow's `save()` turns the answers into a new `Ledger`, and `review` lists the lines for its review card. Flows are tested directly in `test/flows_test.dart`, without pumping widgets.

A flow that keeps a date sets `date`; the review card then shows it and lets the user pick another day.

To add a command, write a `CommandFlow` subclass and add a `Command` to the list in `home_screen.dart`, or a `Command.screen` for one that opens a page.

## Money rules

- Money is stored as integer paise and shown with Indian digit grouping, for example ₹12,34,567.50.
- Shares always add up to the total. Equal, quantity, and percentage splits hand out leftover paise by largest remainder, breaking ties by person id, so a split always rounds the same way.
- Percentages are stored as basis points, so 33.33% is exact.
- If exactly one person's share is left blank, they get whatever is left.
- A positive balance means the friend owes you; negative means you owe them. Expenses solely between other people don't affect your balances.
- Money received lowers what a friend owes you. Money sent lowers what you owe them.
- One payment can pay toward several expenses. Tick them on "Which expenses?" and the amount goes to them in the order ticked, each taking up to what is still open on it: ₹31 for ₹15 of lollipops then ₹17.50 of nachos pays the lollipops in full and ₹16 of the nachos, leaving ₹1.50 open. Whatever the expenses don't take counts toward the overall balance. If the money runs out before a ticked expense, the page says so and won't continue until it is unticked or ticked earlier. The money is never counted twice.
- What a payment puts toward an expense counts in that expense's bill; the rest counts in the payment's bill. A bill's page lists every payment with money in it. Opening a payment never moves its money: it keeps its split until you change the amount or the ticks.
- Deleting an expense keeps its payments in the balance; what they put toward it counts toward the overall balance instead. Deleting a bill deletes its expenses and moves its payments to General.

## Data

The whole ledger is one JSON document in a single SQLite row (`shared_expenses.db`, table `tracker_state`), written in one statement on every change. A failed save leaves the previous state in place, and a failed load is reported without writing anything.

The document carries a `version`, now 4. Version 3 added categories, and version 4 lets a payment pay toward several expenses (`settles`: expense id to paise, in order); older data reads as is, with a payment that named an expense putting its whole amount toward it. Data saved by the first version of the app is upgraded on load, keeping every balance it showed (see `decodeLedger` in `lib/data/store.dart`). Future format changes must add an upgrade the same way rather than resetting data.

Undo history holds the last 50 changes, in memory only.

## Development

```sh
dart format lib test
flutter analyze
flutter test
```

`analysis_options.yaml` enables strict casts, inference and raw types, plus a few extra lints.

### Manual device checks

Widget tests drive a simulated keyboard, so check these by hand on a real device after changing a flow:

- Moving from one typed answer to the next keeps the keyboard open.
- On iPhone, the amount keypad has no return key; Continue stays visible above it.
- At the largest system text size, the question, its input, and Continue are all reachable.
- Android's back gesture steps back through the questions; on the first page it closes the flow.

## Releasing

**Application ID.** The app still uses the Flutter template identifiers `com.example.finance_tracker` (Android) and `com.example.financeTracker` (iOS). Choose permanent identifiers before publishing; they cannot change after release.

**Android signing.** Release builds read signing credentials from `android/key.properties`, which is gitignored:

```properties
storePassword=<keystore password>
keyPassword=<key password>
keyAlias=upload
storeFile=<keystore path, absolute or relative to android/app>
```

Without this file, release builds fall back to debug signing so `flutter run --release` still works locally. See [Build and release an Android app](https://docs.flutter.dev/deployment/android).

**iOS signing.** Open `ios/Runner.xcworkspace` in Xcode and set your development team and bundle identifier.

## Not yet implemented

Receipt scanning, bank imports, budgets, notifications, and cross-device sync.
