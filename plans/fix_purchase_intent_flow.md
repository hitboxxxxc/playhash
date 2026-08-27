# Fix Purchase Intent Flow

## Analysis Summary

1. **Runner Query**: The runner queries `purchaseIntents` collection with `where('status', '==', 'pending')` and orders by `createdAt`. This matches the client-created intent which sets status to 'pending'.

2. **Client MachineId**: The client passes `machine.id` from the `MachineCatalogModel`, which is the correct catalog ID (not display name).

3. **Client Listener**: The client does NOT currently listen to the purchase intent result after creating it in `pixel_sala_screen.dart`. It only shows a loading snackbar and reloads data.

4. **Runner Order**: The `processPurchaseIntents` processor is correctly positioned as the second processor in `runner.ts` (after `gameSessions`).

## Required Fixes

### 1. Add Intent Result Listener in pixel_sala_screen.dart
- After creating a purchase intent, listen to its result using `purchaseIntentService.watchResult(requestId)`
- Handle `isDone` (show success snackbar, reload data)
- Handle `isFailed` (show error snackbar with failure message)
- Handle timeout (show "processando..." message after 60s)

### 2. Ensure Proper Error Handling
- The service already maps failure codes to user-friendly messages via `PurchaseIntentService.failureMessage`

### 3. No Changes Needed Elsewhere
- Firestore rules already allow client to create intents with correct fields
- Runner validation logic is correct
- Order of processors is correct

## Implementation Steps

1. Modify `_onUnlockMachine` in `pixel_sala_screen.dart` to add intent result listener
2. Add similar listener to `_onUpgradeMachine` for upgrade intents
3. Ensure listener handles done/failed states and timeouts
4. Test with econ-cron workflow

## Files to Modify
- `lib/features/machines/pixel_sala_screen.dart`

## Verification
- Run `gh workflow run econ-cron.yml -f action=run`
- Verify intent status transitions from pending to done/failed
- Verify machine creation, power updates, wallet updates
- Verify UI updates appropriately