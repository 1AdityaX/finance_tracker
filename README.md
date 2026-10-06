# Between

A Flutter app for tracking what you spend, alone or shared with friends, and who owes whom. Records live in a SQLite database on the device and work offline. Google sign-in is optional and backs records up to Firestore. There are no bank connections.

Platforms: Android and iOS.

## How it works

Every action is a slash command. Tap a shortcut above the command bar, or type `/` and pick one. The app asks one question per page.

| Command | Questions, in order |
| --- | --- |
| `/expense` | What was it for? · Which category? · Which bill? · How much? · How many units? · Who shared it? · Who paid? · How to split it |
| `/sent` | How much? · To whom? · Which bill? · Which expenses? |
| `/receive` | How much? · From whom? · Which bill? · Which expenses? |
| `/income` | How much? · Who gave it? · What's it for? (optional) |
| `/bill` | What's it called? |
| `/friend` | What's their name? |
| `/category` | What's it called? · Count it in your spending? |
| `/categories` | Opens the list of categories |
| `/spending` | Opens monthly spending |
| `/import` | Choose a file, check what it adds, then add it |
| `/undo` | Reverts the last change |

- Defaults: no category, bill General, quantity 1, payer you, equal split (by quantity when there is more than one unit), and no expenses for a payment (it goes to the overall balance).
- Questions that don't apply are skipped. Who paid and how to split are asked only once a friend is picked. Splitting by quantity appears only with more than one unit. A flow started from a bill's or friend's page fills that answer in and skips it.
- Answers so far show as chips at the top, e.g. `Pizza · in Goa trip · ₹1,200 · 4 units`. Tapping one goes back to that question, then on to the next question that needs an answer, or to the review.
- Back, including the system gesture, goes to the previous page and keeps answers. Closing a flow asks for confirmation only if answers would be lost.
- The review card shows each share, who will owe whom, and your spending for the month. The date defaults to today; tap it to change it.
- Every save can be undone from the snackbar or with `/undo`.
- Pickers can add a new friend, bill or category by typing a name. It is saved with the record, so cancelling adds nothing.

Tap an expense or payment to open its review card, where you can edit an answer or delete the record.

## Spending

`/spending`, or the "Spent in" row on home, shows one month:

- Total spent, compared with the previous month (the current month is compared with the same days of last month).
- Spending by category and by bill as bars. Uncategorised expenses come last, under "No category".
- Every expense you have a share in, largest first. Tap a category or bill to filter; tap an expense to edit it.

Spending is your share of each expense. Money you paid for friends is what they owe you, not spending, and payments between people never count.

There are no preset categories. Add them with `/category`, or by typing a name on the category question. Categories are listed on home and with `/categories`; each has a page with what it cost this month and in all, its expenses, an Add expense button that fills the category in, and Edit and Delete in its menu. Deleting a category leaves its expenses uncategorised.

A category can be excluded from spending by answering "No, leave it out" to "Count it in your spending?". Use this for large costs someone else paid for, like college fees. Its expenses are listed under "Not counted in spending" and the month's summary adds "Plus ₹1,00,000 not counted".

`/income` records money nobody owes back, such as pocket money or a gift. It doesn't change any balance; for a friend paying you back, use `/receive`. The spending page shows it under "Money in".

## Importing

`/import` adds records from a file, such as a bank statement sorted into expenses. Choose the file and the app shows what it would add: how many expenses, payments and money in, their dates, and any new friends, categories and bills. Nothing is saved until you tap "Add to my records", and Undo takes it back.

The file is a ledger in the same JSON format the app saves (see [Data](#data)), at any supported version. Importing:

- only adds; nothing you have is changed or removed.
- matches friends, categories and bills to yours by name, ignoring case, so it never makes a second friend with the same name.
- skips expenses, payments and money in whose id you already have, so importing a file twice adds nothing.
- refuses a file whose records don't add up, such as exact parts that don't total the amount or a payment toward an expense not in the file, and says which record. Nothing is saved.

## Cloud backup

Android only for now. After tapping **Back up to Google** on home and signing in:

- Changes are saved on the phone first, then copied to Firestore in the background. Offline changes are sent when the phone reconnects.
- After a reinstall or on a new phone, **Restore from Google** on the welcome screen (or **Back up to Google** on home) brings records back.
- Changes from another phone arrive the next time the app opens. Merging is per record: a record changed on one side takes that side's version. A record changed on both sides keeps this phone's version, and an edit wins over a deletion.
- Signing out keeps records on the phone and stops backing up.

Records are stored under `users/{uid}`, one document per record; security rules limit each user to their own. Without a Firebase config the app still builds and runs, and the backup row is hidden.

## Getting started

Requires Flutter 3.44 (stable, Dart 3.12) and an Android emulator or device, or Xcode with an iOS simulator.

```sh
flutter pub get
flutter run
```

For Firebase backup and release signing, see [CONTRIBUTING.md](CONTRIBUTING.md).

## Project structure

```
lib/
  main.dart              App entry: storage, cloud backup when set up, load-error screen
  theme.dart             Material 3 theme (light and dark), balance and chart colours
  data/
    money.dart           Paise formatting, parsing, and exact apportioning
    ledger.dart          Friend, Bill, Category, Expense, Payment, balance queries
    spending.dart        Your spending in a month, by category and by bill
    store.dart           Persistence (SQLite), undo, and upgrading old data
    cloud.dart           Syncing with a cloud copy: diffs, three-way merge, SyncedStorage
    import.dart          Adding records from a file, matched to yours by name
  cloud/
    firestore_cloud.dart The ledger in Firestore, one document per record
    account.dart         Google sign-in, and keeping the ledger in step with Firestore
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
    categories_screen.dart  The list of categories
    category_screen.dart One category: its expenses, editing and deleting it
    import_screen.dart   Choosing a file to import and previewing it
    backup.dart          The "Back up to Google" row and signing in
    widgets.dart         Shared rows, labels, and the undo snackbar
test/                    Unit tests for data, sync and flows, widget tests for every flow
```

### Adding or changing a question

A flow is plain Dart with no widgets. It holds its questions as `Ask` objects and lists the ones that currently apply in `asks`:

```dart
@override
List<Ask> get asks => [
  name, category, bill, amount, quantity, people,
  if (_shared) ...[payer, split],
];
```

`FlowScreen` shows the first question that is unanswered or invalid, so a conditional question is an `if` in that list. Each `Ask` has a `problem` (null when valid) and a `phrase` for its chip. `save()` turns the answers into a new `Ledger`, and `review` lists the review card lines. A flow that sets `date` gets a date picker on its review card. Flows are tested without widgets in `test/flows_test.dart`.

To add a command, subclass `CommandFlow` and add a `Command` to the list in `home_screen.dart`, or a `Command.screen` for one that opens a page.

## Money rules

- Money is stored as integer paise and shown with Indian digit grouping, e.g. ₹12,34,567.50.
- Shares always sum to the total. Equal, quantity and percentage splits hand out leftover paise by largest remainder, ties broken by person id, so rounding is deterministic.
- Percentages are stored as basis points, so 33.33% is exact.
- If exactly one share is left blank, it gets the remainder.
- A positive balance means the friend owes you; negative means you owe them. Expenses only between other people don't affect your balances.
- Money received lowers what a friend owes you; money sent lowers what you owe them. `/income` affects no balance.
- A payment can go toward several expenses. Ticked expenses are paid in the order ticked, each up to what is still open on it. For example, ₹31 toward ₹15 of lollipops then ₹17.50 of nachos pays the lollipops in full and ₹16 of the nachos, leaving ₹1.50 open. Any remainder goes to the overall balance. If the money runs out before a ticked expense, the page blocks until it is unticked or reordered. Nothing is counted twice.
- The part of a payment that goes to an expense counts in that expense's bill; the rest counts in the payment's bill, and a bill's page lists every payment with money in it. Opening a payment doesn't change its allocation unless you change the amount or the ticks.
- Deleting an expense keeps its payments; what they put toward it moves to the overall balance. Deleting a bill deletes its expenses and moves its payments to General.

## Data

The ledger is one JSON document in a single SQLite row (`shared_expenses.db`, table `tracker_state`), written in one statement per change. A failed save keeps the previous state; a failed load is reported without writing anything.

The document has a `version`, currently 5:

- 3 added categories.
- 4 lets a payment go toward several expenses (`settles`: expense id to paise, in order).
- 5 adds money in (`incomes`) and categories excluded from spending (`counted: false`).

Older data loads as is; a payment that named one expense puts its whole amount toward it. Version 1 data is upgraded on load with balances unchanged (see `decodeLedger` in `lib/data/store.dart`). Format changes must add an upgrade path, never reset data.

Undo keeps the last 50 changes, in memory only.

With backup on, `SyncedStorage` (`lib/data/cloud.dart`) wraps the SQLite storage. It writes locally first and sends each change to Firestore without waiting. It keeps the last known cloud state in `cloud_base.db` so it can tell what changed on each side. Merging is plain Dart, tested in `test/cloud_test.dart` against an in-memory cloud.

## Development

```sh
dart format lib test
flutter analyze
flutter test
```

`analysis_options.yaml` enables strict casts, inference and raw types, plus some extra lints.

### Manual device checks

Widget tests use a simulated keyboard. After changing a flow, check on a real device that:

- Moving between typed answers keeps the keyboard open.
- On iPhone, the amount keypad has no return key and Continue stays visible above it.
- At the largest system text size, the question, input and Continue are reachable.
- Android's back gesture steps back through questions and closes the flow from the first page.

## Releasing

**Application ID.** The app still uses the template IDs `com.example.finance_tracker` (Android) and `com.example.financeTracker` (iOS). Pick permanent ones before publishing; they can't change after release.

**Android signing.** Always sign releases with the same key. Android won't install an update signed with a different key, and uninstalling erases the app's records. Release builds read `android/key.properties` (gitignored; CONTRIBUTING.md shows how to make a key):

```properties
storePassword=<keystore password>
keyPassword=<key password>
keyAlias=upload
storeFile=<keystore path, absolute or relative to android/app>
```

Without it, release builds use debug signing so `flutter run --release` works locally. See [Build and release an Android app](https://docs.flutter.dev/deployment/android).

**iOS signing.** Set the development team and bundle identifier in `ios/Runner.xcworkspace` in Xcode.

## Not yet implemented

Receipt scanning, bank imports, budgets, notifications, live sync between phones, and cloud backup on iOS.
