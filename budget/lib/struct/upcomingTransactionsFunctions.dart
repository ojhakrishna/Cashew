import 'package:budget/database/tables.dart';
import 'package:budget/functions.dart';
import 'package:budget/pages/addTransactionPage.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/globalSnackbar.dart';
import 'package:budget/struct/initializeNotifications.dart';
import 'package:budget/widgets/navigationFramework.dart';
import 'package:budget/widgets/openPopup.dart';
import 'package:budget/widgets/openSnackbar.dart';
import 'package:budget/widgets/framework/popupFramework.dart';
import 'package:budget/widgets/selectAmount.dart';

import 'package:budget/widgets/transactionEntry/transactionLabel.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:budget/widgets/openBottomSheet.dart';
import 'package:provider/provider.dart';

/// Helpers to mark transactions paid/skipped and to create predictable
/// follow-up transactions for subscriptions/repetitive entries.

Future<void> createNewSubscriptionTransaction(
    BuildContext context, Transaction transaction,
    {String? closelyRelatedPairedTransactionFk}) async {
  // If we've already created the next occurrence, do nothing.
  if (transaction.createdAnotherFutureTransaction == true) return;

  if (transaction.type != TransactionSpecialType.subscription &&
      transaction.type != TransactionSpecialType.repetitive) return;

  int yearOffset = 0;
  int monthOffset = 0;
  int dayOffset = 0;

  if (transaction.reoccurrence == BudgetReoccurence.yearly) {
    yearOffset = transaction.periodLength ?? 0;
  } else if (transaction.reoccurrence == BudgetReoccurence.monthly) {
    monthOffset = transaction.periodLength ?? 0;
  } else if (transaction.reoccurrence == BudgetReoccurence.weekly) {
    dayOffset = (transaction.periodLength ?? 0) * 7;
  } else if (transaction.reoccurrence == BudgetReoccurence.daily) {
    dayOffset = transaction.periodLength ?? 0;
  }

  final newDate = DateTime(
    transaction.dateCreated.year + yearOffset,
    transaction.dateCreated.month + monthOffset,
    transaction.dateCreated.day + dayOffset,
    transaction.dateCreated.hour,
    transaction.dateCreated.minute,
    transaction.dateCreated.second,
    transaction.dateCreated.millisecond,
  );

  // After end date
  if (transaction.endDate != null && transaction.endDate!.isBefore(newDate)) {
    final transactionName = await getTransactionLabel(transaction);
    openSnackbar(
      SnackbarMessage(
        title: 'end-date-reached'.tr(),
        description: '${'for'.tr().capitalizeFirst} $transactionName',
        icon: appStateSettings['outlinedIcons']
            ? Icons.event_available_outlined
            : Icons.event_available_rounded,
      ),
    );
    return;
  }

  // Goal reached
  if (transaction.objectiveFk != null && transaction.endDate == null) {
    final objective =
        await database.getObjectiveInstance(transaction.objectiveFk!);
    final totalSpentOfObjective = await database.getTotalTowardsObjective(
        Provider.of<AllWallets>(context, listen: false),
        transaction.objectiveFk!,
        objective.type);

    bool willBeOverObjective = (totalSpentOfObjective ?? 0) >=
        (objective.amount * (objective.income ? 1 : -1));

    if (objective.income == false) willBeOverObjective = !willBeOverObjective;

    if ((totalSpentOfObjective ?? 0) ==
        (objective.amount * (objective.income ? 1 : -1))) {
      willBeOverObjective = true;
    }

    if (willBeOverObjective) {
      openSnackbar(
        SnackbarMessage(
          title: 'goal-reached'.tr(),
          description: '${'for'.tr().capitalizeFirst} ${objective.name}',
          icon: appStateSettings['outlinedIcons']
              ? Icons.event_available_outlined
              : Icons.event_available_rounded,
        ),
      );
      return;
    }
  }

  final newTransaction = transaction.copyWith(
    paid: false,
    transactionPk: updatePredictableKey(transaction.transactionPk),
    dateCreated: newDate,
    // Use Value wrapper where the generated copyWith expects it (drift companions)
    createdAnotherFutureTransaction: Value(false),
    pairedTransactionFk: closelyRelatedPairedTransactionFk != null
        ? Value(updatePredictableKey(closelyRelatedPairedTransactionFk))
        : const Value(null),
  );

  await database.createOrUpdateTransaction(insert: false, newTransaction);

  final transactionName = await getTransactionLabel(transaction);

  openSnackbar(
    SnackbarMessage(
      title: (transaction.income ? 'deposited'.tr() : 'paid'.tr()) +
          ': ' +
          transactionName,
      description: 'created-new-for'.tr() +
          ' ' +
          getWordedDateShort(newDate, lowerCaseTodayTomorrow: true),
      icon: appStateSettings['outlinedIcons']
          ? Icons.event_repeat_outlined
          : Icons.event_repeat_rounded,
      onTap: () {
        pushRoute(
          context,
          AddTransactionPage(
            transaction: newTransaction,
            routesToPopAfterDelete: RoutesToPopAfterDelete.One,
          ),
        );
      },
    ),
  );
}

int? countTransactionOccurrences({
  required TransactionSpecialType? type,
  required BudgetReoccurence? reoccurrence,
  required int? periodLength,
  required DateTime dateCreated,
  required DateTime? endDate,
}) {
  if (type != TransactionSpecialType.subscription &&
      type != TransactionSpecialType.repetitive) {
    return null;
  }
  if (endDate == null ||
      reoccurrence == null ||
      reoccurrence == BudgetReoccurence.custom ||
      periodLength == null) return null;

  int yearOffset = 0;
  int monthOffset = 0;
  int dayOffset = 0;

  if (reoccurrence == BudgetReoccurence.yearly) {
    yearOffset = periodLength;
  } else if (reoccurrence == BudgetReoccurence.monthly) {
    monthOffset = periodLength;
  } else if (reoccurrence == BudgetReoccurence.weekly) {
    dayOffset = periodLength * 7;
  } else if (reoccurrence == BudgetReoccurence.daily) {
    dayOffset = periodLength;
  }

  DateTime currentDate = dateCreated;

  int occurrenceCount = 0;

  while (!endDate.isBefore(currentDate)) {
    occurrenceCount++;

    currentDate = DateTime(
      currentDate.year + yearOffset,
      currentDate.month + monthOffset,
      currentDate.day + dayOffset,
      currentDate.hour,
      currentDate.minute,
      currentDate.second,
      currentDate.millisecond,
    );

    if (endDate.isBefore(currentDate)) {
      break;
    } else if (occurrenceCount > 999) {
      return null; // too many occurrences, avoid infinite loop
    }
  }

  return occurrenceCount;
}

String updatePredictableKey(String originalKey) {
  if (originalKey.contains('::predict::')) {
    try {
      final parts = originalKey.split('::predict::');
      final currentNumber = int.parse(parts[1]);
      final newNumber = currentNumber + 1;
      return '${parts[0]}::predict::$newNumber';
    } catch (e) {
      debugPrint('Error creating predictable key: $e');
      return uuid.v4();
    }
  } else {
    return '$originalKey::predict::1';
  }
}

Future<void> openPayPopup(
  BuildContext context,
  Transaction transaction, {
  Function? runBefore,
}) async {
  final transactionName = await getTransactionLabel(transaction);
  final numberRepeats = transaction.createdAnotherFutureTransaction == true
      ? null
      : countTransactionOccurrences(
          type: transaction.type,
          reoccurrence: transaction.reoccurrence,
          periodLength: transaction.periodLength,
          dateCreated: transaction.dateCreated,
          endDate: transaction.endDate,
        );

  final repeatsLeftLabel = numberRepeats == null
      ? ''
      : '\n× ${numberRepeats.toString()} ${'remain'.tr()} ${'until'.tr()} ${getWordedDateShort(transaction.endDate ?? DateTime.now(), includeYear: transaction.endDate?.year != DateTime.now().year)}';

  await openPopup(
    context,
    icon: appStateSettings['outlinedIcons']
        ? Icons.check_circle_outlined
        : Icons.check_circle_rounded,
    title: (transaction.income ? 'deposit'.tr() : 'pay'.tr()) + '?',
    subtitle: transactionName,
    description: (transaction.income
            ? 'deposit-description'.tr()
            : 'pay-description'.tr()) +
        repeatsLeftLabel,
    onCancelLabel: 'cancel'.tr(),
    onCancel: () {
      popRoute(context, false);
    },
    onExtraLabel: 'skip'.tr(),
    onExtra: () async {
      if (runBefore != null) await runBefore();
      popRoute(context);
      await markAsSkipped(transaction: transaction);
    },
    onSubmitLabel: transaction.income ? 'deposit'.tr() : 'pay'.tr(),
    onSubmit: () async {
      if (runBefore != null) await runBefore();
      popRoute(context);
      await markAsPaid(transaction: transaction);
    },
  );
}

Future<void> markAsPaid({
  required Transaction transaction,
  // Avoid infinite recursion
  bool updatingCloselyRelated = false,
}) async {
  String? closelyRelatedPairedTransactionFk;
  if (!updatingCloselyRelated && transaction.categoryFk == '0') {
    final closelyRelatedTransferCorrectionTransaction = await database
        .getCloselyRelatedBalanceCorrectionTransaction(transaction);
    if (closelyRelatedTransferCorrectionTransaction != null) {
      await markAsPaid(
          transaction: closelyRelatedTransferCorrectionTransaction,
          updatingCloselyRelated: true);
      closelyRelatedPairedTransactionFk =
          closelyRelatedTransferCorrectionTransaction.transactionPk;
    }
  }

  final transactionNew = transaction.copyWith(
    paid: true,
    dateCreated:
        appStateSettings['markAsPaidOnOriginalDay'] ? null : DateTime.now(),
    createdAnotherFutureTransaction: Value(true),
    originalDateDue: Value(transaction.dateCreated),
  );

  await database.createOrUpdateTransaction(transactionNew);

  // Use navigatorKey context if available, otherwise fall back to passed context when calling earlier
  final ctx = navigatorKey.currentContext ?? null;
  await createNewSubscriptionTransaction(
      ctx ??
          navigatorKey.currentContext ??
          navigatorKey.currentContext ??
          navigatorKey.currentContext!,
      transaction,
      closelyRelatedPairedTransactionFk: closelyRelatedPairedTransactionFk);

  if (navigatorKey.currentContext != null)
    await setUpcomingNotifications(navigatorKey.currentContext!);
}

Future<void> markAsSkipped({
  required Transaction transaction,
  // Avoid infinite recursion
  bool updatingCloselyRelated = false,
}) async {
  String? closelyRelatedPairedTransactionFk;
  if (!updatingCloselyRelated && transaction.categoryFk == '0') {
    final closelyRelatedTransferCorrectionTransaction = await database
        .getCloselyRelatedBalanceCorrectionTransaction(transaction);
    if (closelyRelatedTransferCorrectionTransaction != null) {
      await markAsSkipped(
          transaction: closelyRelatedTransferCorrectionTransaction,
          updatingCloselyRelated: true);
      closelyRelatedPairedTransactionFk =
          closelyRelatedTransferCorrectionTransaction.transactionPk;
    }
  }

  final transactionNew = transaction.copyWith(
    skipPaid: true,
    dateCreated: DateTime.now(),
    createdAnotherFutureTransaction: Value(true),
  );

  await database.createOrUpdateTransaction(transactionNew);

  final ctx = navigatorKey.currentContext ?? null;
  await createNewSubscriptionTransaction(
      ctx ??
          navigatorKey.currentContext ??
          navigatorKey.currentContext ??
          navigatorKey.currentContext!,
      transaction,
      closelyRelatedPairedTransactionFk: closelyRelatedPairedTransactionFk);

  if (navigatorKey.currentContext != null)
    await setUpcomingNotifications(navigatorKey.currentContext!);
}

Future<void> openPayDebtCreditPopup(
  BuildContext context,
  Transaction transaction, {
  Function? runBefore,
}) async {
  final transactionName = await getTransactionLabel(transaction);
  await openPopup(
    context,
    icon: appStateSettings['outlinedIcons']
        ? Icons.check_circle_outlined
        : Icons.check_circle_rounded,
    title: (transaction.type == TransactionSpecialType.credit
            ? 'collect'.tr()
            : transaction.type == TransactionSpecialType.debt
                ? 'settled'.tr()
                : '') +
        '?',
    subtitle: transactionName,
    description: transaction.type == TransactionSpecialType.credit
        ? 'collect-description'.tr()
        : transaction.type == TransactionSpecialType.debt
            ? 'settle-description'.tr()
            : '',
    onCancelLabel: 'cancel'.tr(),
    onCancel: () {
      popRoute(context, false);
    },
    onSubmitLabel: transaction.type == TransactionSpecialType.credit
        ? 'collect-all'.tr()
        : transaction.type == TransactionSpecialType.debt
            ? 'settle-all'.tr()
            : '',
    onSubmit: () async {
      if (runBefore != null) await runBefore();
      final transactionNew = transaction.copyWith(
        // we don't want it to count towards the total - net is zero now
        paid: false,
      );
      popRoute(context, true);
      await database.createOrUpdateTransaction(transactionNew);
    },
    onExtraLabel2: transaction.type == TransactionSpecialType.credit
        ? 'partially-collect'.tr()
        : transaction.type == TransactionSpecialType.debt
            ? 'partially-settle'.tr()
            : '',
    onExtra2: () async {
      double selectedAmount = transaction.amount.abs();
      String selectedWalletFk = transaction.walletFk;

      final result = await openBottomSheet(
        context,
        fullSnap: true,
        PopupFramework(
          title: transaction.type == TransactionSpecialType.credit
              ? 'amount-collected'.tr()
              : transaction.type == TransactionSpecialType.debt
                  ? 'amount-settled'.tr()
                  : '',
          hasPadding: false,
          underTitleSpace: false,
          child: SelectAmount(
            amountPassed: selectedAmount.toString(),
            padding: EdgeInsetsDirectional.symmetric(horizontal: 18),
            onlyShowCurrencyIcon: true,
            selectedWalletPk: selectedWalletFk,
            walletPkForCurrency: selectedWalletFk,
            setSelectedWalletPk: (walletFk) {
              selectedWalletFk = walletFk;
            },
            allowZero: true,
            allDecimals: true,
            convertToMoney: true,
            setSelectedAmount: (amount, __) {
              selectedAmount = amount;
            },
            next: () {
              popRoute(context, true);
            },
            nextLabel: 'set-amount'.tr(),
            currencyKey: null,
            enableWalletPicker: true,
          ),
        ),
      );

      if (selectedAmount == 0 || result != true) return;

      popRoute(context, true);

      final category = await database.getCategory(transaction.categoryFk).$2;
      final transactionLabel = getTransactionLabelSync(transaction, category);
      final numberOfObjectives = (await database.getTotalCountOfObjectives(
              objectiveType: ObjectiveType.loan))[0] ??
          0;

      final rowId = await database.createOrUpdateObjective(
        Objective(
          amount: 0,
          income: !transaction.income,
          objectivePk: '-1',
          name: transactionLabel,
          order: numberOfObjectives,
          dateCreated: transaction.dateCreated,
          pinned: false,
          walletFk: transaction.walletFk,
          iconName: category.iconName,
          emojiIconName: category.emojiIconName,
          colour: category.colour,
          type: ObjectiveType.loan,
          archived: false,
        ),
        insert: true,
      );

      final objectiveJustAdded = await database.getObjectiveFromRowId(rowId);

      // Set up the initial amount
      await database.createOrUpdateTransaction(
        transaction.copyWith(
          type: const Value(null),
          objectiveLoanFk: Value(objectiveJustAdded.objectivePk),
          amount: transaction.amount,
          name: 'initial-record'.tr(),
        ),
      );

      // Add the first payment/record (inverse polarity)
      await database.createOrUpdateTransaction(
        transaction.copyWith(
          type: const Value(null),
          objectiveLoanFk: Value(objectiveJustAdded.objectivePk),
          income: !transaction.income,
          amount: selectedAmount * (!transaction.income ? 1 : -1),
          dateCreated: DateTime.now(),
          walletFk: selectedWalletFk,
        ),
        insert: true,
      );
    },
  );
}

Future<void> openRemoveSkipPopup(
  BuildContext context,
  Transaction transaction, {
  Function? runBefore,
}) async {
  final transactionName = await getTransactionLabel(transaction);
  await openPopup(
    context,
    icon: appStateSettings['outlinedIcons']
        ? Icons.unpublished_outlined
        : Icons.unpublished_rounded,
    title: 'remove-skip'.tr() + '?',
    subtitle: transactionName,
    description: 'remove-skip-description'.tr(),
    onCancelLabel: 'cancel'.tr(),
    onCancel: () {
      popRoute(context, false);
    },
    onSubmitLabel: 'remove'.tr(),
    onSubmit: () async {
      if (runBefore != null) await runBefore();

      final transactionNew = transaction.copyWith(skipPaid: false);
      popRoute(context, true);
      await database.createOrUpdateTransaction(transactionNew);
      if (navigatorKey.currentContext != null)
        await setUpcomingNotifications(navigatorKey.currentContext!);
    },
  );
}

Future<void> openUnpayPopup(
  BuildContext context,
  Transaction transaction, {
  Function? runBefore,
}) async {
  final transactionName = await getTransactionLabel(transaction);
  await openPopup(
    context,
    icon: appStateSettings['outlinedIcons']
        ? Icons.unpublished_outlined
        : Icons.unpublished_rounded,
    title: 'remove-payment'.tr() + '?',
    subtitle: transactionName,
    description: 'remove-payment-description'.tr(),
    onCancelLabel: 'cancel'.tr(),
    onCancel: () {
      popRoute(context, false);
    },
    onSubmitLabel: 'remove'.tr(),
    onSubmit: () async {
      if (runBefore != null) await runBefore();
      await database.deleteTransaction(transaction.transactionPk);
      final transactionNew = transaction.copyWith(
        paid: false,
        sharedKey: const Value(null),
        transactionOriginalOwnerEmail: const Value(null),
        sharedDateUpdated: const Value(null),
        sharedStatus: const Value(null),
      );
      popRoute(context, true);
      await database.createOrUpdateTransaction(transactionNew);
      if (navigatorKey.currentContext != null)
        await setUpcomingNotifications(navigatorKey.currentContext!);
    },
  );
}

Future<void> openUnpayDebtCreditPopup(
  BuildContext context,
  Transaction transaction, {
  Function? runBefore,
}) async {
  final transactionName = await getTransactionLabel(transaction);
  await openPopup(
    context,
    icon: appStateSettings['outlinedIcons']
        ? Icons.unpublished_outlined
        : Icons.unpublished_rounded,
    title: 'remove-payment'.tr() + '?',
    subtitle: transactionName,
    description: 'remove-payment-description'.tr(),
    onCancelLabel: 'cancel'.tr(),
    onCancel: () {
      popRoute(context, false);
    },
    onSubmitLabel: 'remove'.tr(),
    onSubmit: () async {
      if (runBefore != null) await runBefore();
      final transactionNew = transaction.copyWith(
        //we want it to count towards the total now - net is not zero
        paid: true,
      );
      popRoute(context, true);
      await database.createOrUpdateTransaction(transactionNew,
          updateSharedEntry: false);
    },
  );
}

Map<String, String?> findMatchingPairsPks(List<Transaction> subscriptions) {
  // TODO: Implement actual logic for finding matching pairs
  // For now, return an empty map
  return {};
}

Future<bool> markSubscriptionsAsPaid(BuildContext context,
    {int? iteration}) async {
  if (appStateSettings['automaticallyPaySubscriptions'] ||
      appStateSettings['automaticallyPayRepetitive']) {
    if (iteration != null && iteration > 50) return true;

    final subscriptions = <Transaction>[
      if (appStateSettings['automaticallyPaySubscriptions'])
        ...(await database.getAllSubscriptions()).$2 as Iterable<Transaction>,
      if (appStateSettings['automaticallyPayRepetitive'])
        ...(await database.getAllOverdueRepetitiveTransactions()).$2
            as Iterable<Transaction>,
    ];

    final relatedMatchingPairs = findMatchingPairsPks(subscriptions);

    bool hasUpdatedASubscription = false;
    for (final transaction in subscriptions) {
      if (transaction.createdAnotherFutureTransaction != true &&
          transaction.dateCreated
              .isBefore(DateTime.now().add(const Duration(minutes: 1)))) {
        hasUpdatedASubscription = true;
        final transactionNew = transaction.copyWith(
          paid: true,
          dateCreated: transaction.dateCreated,
          createdAnotherFutureTransaction: Value(true),
        );
        await database.createOrUpdateTransaction(transactionNew);
        if (transaction.categoryFk == '0' &&
            transaction.pairedTransactionFk != null &&
            relatedMatchingPairs[transaction.pairedTransactionFk] != null) {
          await createNewSubscriptionTransaction(context, transaction,
              closelyRelatedPairedTransactionFk:
                  relatedMatchingPairs[transaction.pairedTransactionFk]);
        } else {
          await createNewSubscriptionTransaction(context, transaction);
        }
      }
    }

    if (hasUpdatedASubscription) {
      await markSubscriptionsAsPaid(context, iteration: (iteration ?? 0) + 1);
    }

    debugPrint(
        'Automatically paid subscriptions with iteration: ${iteration ?? 0}');
  }
  return true;
}

Future<bool> markUpcomingAsPaid() async {
  if (appStateSettings['automaticallyPayUpcoming']) {
    final upcoming = (await database.getAllOverdueUpcomingTransactions()).$2;
    for (final transaction in (upcoming as Iterable<Transaction>)) {
      if (transaction.createdAnotherFutureTransaction != true &&
          transaction.dateCreated
              .isBefore(DateTime.now().add(const Duration(minutes: 1)))) {
        final transactionNew = transaction.copyWith(
          paid: true,
          dateCreated: transaction.dateCreated,
        );
        await database.createOrUpdateTransaction(transactionNew);
      }
    }
    debugPrint('Automatically paid upcoming transactions');
  }
  return true;
}
