# Product

<!-- impeccable:product-schema 1 -->

> Written from the owner's brief and hand-drawn flow diagram (October 2026). The owner was not available for an interview, so lines marked *(inferred)* are assumptions to confirm.

## Platform

android

Flutter with Material 3, shipped to Android and iOS. On iPhone it still honors iOS guarantees: safe areas, Reduce Motion, and a clear Cancel on modal tasks.

## Users

One person tracking money shared with friends: meals, trips, flatmate costs. They open the app right after paying, often standing at a counter, phone in one hand *(inferred)*. Friends never use the app and need no account.

## Product Purpose

Record who paid for what and who owes whom, then record money sent or received until balances reach zero. Success is logging an expense in a few seconds without thinking about syntax, and always knowing each friend's balance.

## Positioning

Private and local-first: every record stays on the device in SQLite. No accounts, sync, bank links, or messages sent on the user's behalf.

## Operating Context

Every action starts from a slash command (`/expense`, `/bill`, `/sent`, `/receive`, `/friend`). Once a command is chosen, the app asks one question at a time and fills in the record as the user answers. The owner rejected the previous design, which put every option on one Discord-style command line, as overwhelming.

## Capabilities and Constraints

- **Bill:** a named group of expenses, such as a trip or a dinner. A built-in bill called "General" always exists and is the default.
- **Expense:** a name, a bill, the amount paid, a quantity (default 1), the friends involved, who paid (you or one of them), and each person's share. Shares can be split equally, by quantity (only when quantity is above 1), by percentage, or by exact rupees.
- **Sent / received payments:** an amount, a friend, a bill (General by default, searchable) and an expense in that bill (searchable). Sent money reduces what you owe them. Received money reduces what they owe you.
- Money is stored as integer paise (INR). Splits always add up exactly to the total.
- Records can be corrected or deleted, and every change can be undone *(inferred: carried over from the previous app)*.
- Records saved by the previous version on a device must survive the update *(inferred)*.

## Brand Commitments

- Name: **Between**, lower-case wordmark "between".
- Established palette from the previous app: deep teal `#176B60` on a warm off-white `#FAFAF6`, with ink `#203B33` and muted `#66736D`.

## Evidence on Hand

No real user data, testimonials or metrics exist. Screens use synthetic names and amounts only.

## Product Principles

1. One question at a time. Never show an option before it matters.
2. Every answer has a sensible default, so a common expense takes a few taps.
3. Money is exact. Shares always add up to the total, and the app says what is left to assign.
4. Nothing interrupts saving. A save is instant and reversible with Undo; the only question the app asks is before throwing away answers that were never saved.
5. Private by default. Nothing leaves the device.

## Accessibility & Inclusion

Large system text sizes must not hide the current question, its input, or the Continue button. Touch targets are at least 48dp. Dark theme is supported *(inferred)*.
