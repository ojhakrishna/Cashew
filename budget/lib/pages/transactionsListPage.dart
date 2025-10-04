import 'package:budget/pages/transactionFilters.dart';
import 'package:budget/pages/upcomingOverdueTransactionsPage.dart';
import 'package:budget/struct/defaultPreferences.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/button.dart';
import 'package:budget/widgets/framework/popupFramework.dart';
import 'package:budget/widgets/navigationSidebar.dart';
import 'package:budget/widgets/openBottomSheet.dart';
import 'package:budget/widgets/scrollbarWrap.dart';
import 'package:budget/database/tables.dart';
import 'package:budget/functions.dart';
import 'package:budget/pages/transactionsSearchPage.dart';
import 'package:budget/widgets/selectedTransactionsAppBar.dart';
import 'package:budget/widgets/monthSelector.dart';
import 'package:budget/widgets/framework/pageFramework.dart';
import 'package:budget/widgets/settingsContainers.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:budget/widgets/transactionEntries.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sliver_tools/sliver_tools.dart';
import 'package:budget/widgets/util/sliverPinnedOverlapInjector.dart';
import 'package:budget/widgets/util/multiDirectionalInfiniteScroll.dart';
import 'package:budget/widgets/sliverStickyHeaderIfTall.dart';
import 'package:budget/widgets/changePagesArrows.dart';

class TransactionsListPage extends StatefulWidget {
  const TransactionsListPage({Key? key}) : super(key: key);

  @override
  State<TransactionsListPage> createState() => TransactionsListPageState();
}

class TransactionsListPageState extends State<TransactionsListPage>
    with TickerProviderStateMixin {
  final pageId = "Transactions";
  final ScrollController _scrollController = ScrollController();
  final PageController _pageController = PageController(initialPage: 1000000);
  List<int> selectedTransactionIDs = [];
  GlobalKey<MonthSelectorState> monthSelectorStateKey = GlobalKey();
  SearchFilters searchFilters = SearchFilters();

  void refreshState() {
    setState(() {});
  }

  void scrollToTop({int duration = 1200}) {
    if (_scrollController.offset <= 0) {
      pushRoute(context, const TransactionsSearchPage());
    } else {
      _scrollController.animateTo(0,
          duration: Duration(
              milliseconds: (getPlatform() == PlatformOS.isIOS
                      ? duration * 0.2
                      : duration)
                  .round()),
          curve: getPlatform() == PlatformOS.isIOS
              ? Curves.easeInOut
              : Curves.elasticOut);
    }
  }

  @override
  void initState() {
    super.initState();
    searchFilters.loadFilterString(
      appStateSettings["transactionsListPageSetFiltersString"],
      skipDateTimeRange: true,
      skipSearchQuery: true,
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> selectFilters(BuildContext context) async {
    await openBottomSheet(
      context,
      PopupFramework(
        title: "filters".tr(),
        hasPadding: false,
        child: TransactionFiltersSelection(
          setSearchFilters: setSearchFilters,
          searchFilters: searchFilters,
          clearSearchFilters: clearSearchFilters,
        ),
      ),
    );
    Future.delayed(const Duration(milliseconds: 250), () {
      updateSettings(
        "transactionsListPageSetFiltersString",
        searchFilters.getFilterString(),
        updateGlobalState: false,
      );
      setState(() {});
    });
  }

  void setSearchFilters(SearchFilters searchFilters) {
    this.searchFilters = searchFilters;
  }

  void clearSearchFilters() {
    searchFilters.clearSearchFilters();
    updateSettings("transactionsListPageSetFiltersString", null,
        updateGlobalState: false);
    setState(() {});
  }

  void changePage(int difference) {
    _pageController.animateToPage(
      (_pageController.page ?? _pageController.initialPage).round() +
          difference,
      duration: const Duration(milliseconds: 1000),
      curve: Curves.easeInOutCubicEmphasized,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PageFramework(
      title: "transactions".tr(),
      listID: pageId,
      scrollController: _scrollController,
      selectedTransactionsAppBar: SelectedTransactionsAppBar(pageID: pageId),
      scrollbar: false,
      actions: [
        IconButton(
          tooltip: "filters".tr(),
          onPressed: () {
            selectFilters(context);
          },
          padding: const EdgeInsetsDirectional.all(15 - 8),
          icon: SelectedIconForIconButton(
            iconData: appStateSettings["outlinedIcons"]
                ? Icons.filter_alt_outlined
                : Icons.filter_alt_rounded,
            isSelected: searchFilters.isClear() == false,
          ),
        ),
        IconButton(
          padding: const EdgeInsetsDirectional.all(15),
          tooltip: "search-transactions".tr(),
          onPressed: () {
            pushRoute(context, const TransactionsSearchPage());
          },
          icon: Icon(
            appStateSettings["outlinedIcons"]
                ? Icons.search_outlined
                : Icons.search_rounded,
          ),
        ),
      ],
      customScrollViewBuilder: (_, scrollPhysics, sliverAppBar) {
        return ValueListenableBuilder(
          valueListenable: cancelParentScroll,
          builder: (context, value, widget) {
            return NestedScrollView(
              controller: _scrollController,
              physics:
                  value ? const NeverScrollableScrollPhysics() : scrollPhysics,
              headerSliverBuilder:
                  (BuildContext contextHeader, bool innerBoxIsScrolled) {
                return <Widget>[
                  SliverOverlapAbsorber(
                    handle: NestedScrollView.sliverOverlapAbsorberHandleFor(
                        contextHeader),
                    sliver: MultiSliver(
                      children: [
                        sliverAppBar,
                        SliverStickyHeaderIfTall(
                          child: MonthSelector(
                            key: monthSelectorStateKey,
                            setSelectedDateStart:
                                (DateTime currentDateTime, int index) {
                              if (((_pageController.page ?? 0) -
                                          index -
                                          _pageController.initialPage)
                                      .abs() ==
                                  1) {
                                _pageController.animateToPage(
                                  _pageController.initialPage + index,
                                  duration: const Duration(milliseconds: 1000),
                                  curve: Curves.easeInOutCubicEmphasized,
                                );
                              } else {
                                _pageController.jumpToPage(
                                  _pageController.initialPage + index,
                                );
                              }
                            },
                          ),
                        ),
                        const SliverToBoxAdapter(child: SizedBox(height: 5)),
                        SliverToBoxAdapter(
                          child: AppliedFilterChips(
                            searchFilters: searchFilters,
                            openFiltersSelection: () {
                              selectFilters(context);
                            },
                            clearSearchFilters: clearSearchFilters,
                            padding: const EdgeInsetsDirectional.symmetric(
                                vertical: 5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ];
              },
              body: ChangePagesArrows(
                onArrowLeft: () => changePage(-1),
                onArrowRight: () => changePage(1),
                child: Builder(
                  builder: (contextPageView) {
                    return PageView.builder(
                      controller: _pageController,
                      onPageChanged: (int index) {
                        final int pageOffset =
                            index - _pageController.initialPage;
                        DateTime startDate = DateTime.now()
                            .firstDayOfMonth()
                            .justDay(monthOffset: pageOffset);
                        monthSelectorStateKey.currentState
                            ?.setSelectedDateStart(startDate, pageOffset);
                        double middle = -(MediaQuery.sizeOf(context).width -
                                    getWidthNavigationSidebar(context)) /
                                2 +
                            100 / 2;
                        monthSelectorStateKey.currentState
                            ?.scrollTo(middle + (pageOffset - 1) * 100 + 100);
                      },
                      itemBuilder: (BuildContext context, int index) {
                        final int pageOffset =
                            index - _pageController.initialPage;
                        DateTime startDate = DateTime.now()
                            .firstDayOfMonth()
                            .justDay(monthOffset: pageOffset);

                        return ScrollbarWrap(
                          child: CustomScrollView(
                            slivers: [
                              SliverPinnedOverlapInjector(
                                handle: NestedScrollView
                                    .sliverOverlapAbsorberHandleFor(
                                        contextPageView),
                              ),
                              TransactionEntries(
                                searchFilters: searchFilters,
                                renderType: appStateSettings["appAnimations"] !=
                                        AppAnimations.all.index
                                    ? TransactionEntriesRenderType
                                        .sliversNotSticky
                                    : TransactionEntriesRenderType
                                        .implicitlyAnimatedSlivers,
                                startDate,
                                DateTime(startDate.year, startDate.month + 1,
                                    startDate.day - 1),
                                listID: pageId,
                                noResultsMessage:
                                    "${"no-transactions-for".tr()} ${getMonth(startDate, includeYear: startDate.year != DateTime.now().year)}.",
                                showTotalCashFlow: true,
                                enableSpendingSummary: true,
                                showSpendingSummary: appStateSettings[
                                    "showTransactionsMonthlySpendingSummary"],
                                onLongPressSpendingSummary: () {
                                  openBottomSheet(
                                    context,
                                    PopupFramework(
                                      hasPadding: false,
                                      child: Column(
                                        children: [
                                          Padding(
                                            padding: const EdgeInsetsDirectional
                                                .symmetric(horizontal: 8),
                                            child: TextFont(
                                              text:
                                                  "enabled-in-settings-at-any-time"
                                                      .tr(),
                                              fontSize: 14,
                                              maxLines: 5,
                                              textAlign: TextAlign.center,
                                            ),
                                          ),
                                          const SizedBox(height: 5),
                                          const ShowTransactionsMonthlySpendingSummarySettingToggle(),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                              const SliverToBoxAdapter(
                                child: SizedBox(
                                  height: 40,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class TransactionsSettings extends StatelessWidget {
  const TransactionsSettings({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        AutoPayTransactionsSetting(),
        MarkAsPaidOnDaySetting(),
        NetSpendingDayTotalSetting(),
        ShowTransactionsMonthlySpendingSummarySettingToggle(),
        ShowTransactionsBalanceTransferTabSettingToggle(),
      ],
    );
  }
}

class AutoPayTransactionsSetting extends StatelessWidget {
  const AutoPayTransactionsSetting({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsContainer(
      title: "auto-mark-transactions".tr(),
      description: "auto-mark-transactions-description".tr(),
      icon: appStateSettings["outlinedIcons"]
          ? Icons.check_circle_outlined
          : Icons.check_circle_rounded,
      onTap: () {
        openBottomSheet(
          context,
          PopupFramework(
            hasPadding: false,
            child: const UpcomingOverdueSettings(),
          ),
        );
      },
    );
  }
}

class ShowTransactionsMonthlySpendingSummarySettingToggle
    extends StatelessWidget {
  const ShowTransactionsMonthlySpendingSummarySettingToggle({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsContainerSwitch(
      title: "monthly-spending-summary".tr(),
      description: "monthly-spending-summary-description".tr(),
      onSwitched: (value) {
        updateSettings("showTransactionsMonthlySpendingSummary", value,
            updateGlobalState: false, pagesNeedingRefresh: [1]);
      },
      initialValue: appStateSettings["showTransactionsMonthlySpendingSummary"],
      icon: appStateSettings["outlinedIcons"]
          ? Icons.balance_outlined
          : Icons.balance_rounded,
    );
  }
}

class ShowTransactionsBalanceTransferTabSettingToggle extends StatelessWidget {
  const ShowTransactionsBalanceTransferTabSettingToggle({super.key});

  @override
  Widget build(BuildContext context) {
    if (Provider.of<AllWallets>(context).indexedByPk.keys.length <= 1) {
      return const SizedBox.shrink();
    }
    return SettingsContainerSwitch(
      title: "show-balance-transfer-tab".tr(),
      description: "show-balance-transfer-tab-description".tr(),
      onSwitched: (value) {
        updateSettings("showTransactionsBalanceTransferTab", value,
            updateGlobalState: false);
      },
      initialValue: appStateSettings["showTransactionsBalanceTransferTab"],
      icon: appStateSettings["outlinedIcons"]
          ? Icons.compare_arrows_outlined
          : Icons.compare_arrows_rounded,
    );
  }
}

class NetSpendingDayTotalSetting extends StatelessWidget {
  const NetSpendingDayTotalSetting({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsContainerDropdown(
      title: "date-banner-total".tr(),
      icon: appStateSettings["outlinedIcons"]
          ? Icons.playlist_add_outlined
          : Icons.playlist_add_rounded,
      initial: appStateSettings["netSpendingDayTotal"].toString(),
      items: const ["false", "true"],
      onChanged: (value) async {
        updateSettings("netSpendingDayTotal", value == "true" ? true : false,
            updateGlobalState: true, pagesNeedingRefresh: [1]);
      },
      getLabel: (item) {
        if (item == "false") return "day-total".tr().capitalizeFirst;
        if (item == "true") return "net-total".tr().capitalizeFirst;
      },
    );
  }
}
