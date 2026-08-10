import 'package:flutter/material.dart';

import '../../core/models/partner.dart';
import '../../core/services/standing_order_service.dart';
import '../settings/partner_settings_screen.dart';
import 'order_form_screen.dart';
import 'order_history_screen.dart';
import 'standing_order_list_screen.dart';

/// 거래처 홈. 발주 등록 / 발주 내역 / 정기발주 / 설정 탭으로 구성된다.
class PartnerHome extends StatefulWidget {
  const PartnerHome({super.key, required this.uid, required this.partner});

  final String uid;
  final Partner partner;

  /// 현재 선택된 탭.
  static final ValueNotifier<int> tab = ValueNotifier<int>(0);

  @override
  State<PartnerHome> createState() => _PartnerHomeState();
}

class _PartnerHomeState extends State<PartnerHome> {
  @override
  void initState() {
    super.initState();
    PartnerHome.tab.value = 0;
    PartnerHome.tab.addListener(_onTabChanged);
    
    // 앱 진입 시 정기발주 체크 (시뮬레이션)
    StandingOrderService.processStandingOrders(
      widget.partner.id,
      widget.partner.name,
      widget.uid,
    );
  }

  @override
  void dispose() {
    PartnerHome.tab.removeListener(_onTabChanged);
    super.dispose();
  }

  void _onTabChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final int index = PartnerHome.tab.value;
    return Scaffold(
      body: IndexedStack(
        index: index,
        children: <Widget>[
          OrderFormScreen(uid: widget.uid, partner: widget.partner),
          OrderHistoryScreen(uid: widget.uid, partnerId: widget.partner.id),
          StandingOrderListScreen(partner: widget.partner),
          PartnerSettingsScreen(uid: widget.uid, partner: widget.partner),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (int i) => PartnerHome.tab.value = i,
        destinations: const <NavigationDestination>[
          NavigationDestination(
              icon: Icon(Icons.add_shopping_cart_outlined), label: '발주 등록'),
          NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined), label: '내역'),
          NavigationDestination(
              icon: Icon(Icons.calendar_today_outlined), label: '정기발주'),
          NavigationDestination(
              icon: Icon(Icons.settings_outlined), label: '설정'),
        ],
      ),
    );
  }
}
