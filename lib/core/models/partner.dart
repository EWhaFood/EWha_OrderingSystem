import 'package:cloud_firestore/cloud_firestore.dart';

/// 거래처 배송지.
class PartnerAddress {
  const PartnerAddress({
    required this.label,
    required this.address,
    this.isDefault = false,
  });

  final String label;
  final String address;
  final bool isDefault;

  PartnerAddress copyWith({String? label, String? address, bool? isDefault}) {
    return PartnerAddress(
      label: label ?? this.label,
      address: address ?? this.address,
      isDefault: isDefault ?? this.isDefault,
    );
  }

  factory PartnerAddress.fromMap(Map<String, dynamic> data) {
    return PartnerAddress(
      label: data['label'] as String? ?? '',
      address: data['address'] as String? ?? '',
      isDefault: data['isDefault'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'label': label,
      'address': address,
      'isDefault': isDefault,
    };
  }
}

/// 거래처. 운영자가 등록하며, cafe24MemberId로 몰 주문을 이 거래처에 연결한다.
class Partner {
  const Partner({
    required this.id,
    required this.name,
    this.manager,
    this.phone,
    this.cafe24MemberId,
    this.active = true,
    this.addresses = const <PartnerAddress>[],
  });

  final String id;
  final String name;
  final String? manager;
  final String? phone;

  /// 카페24 회원 ID. 몰 주문 매핑 키. 없으면 몰 주문은 미분류로 처리.
  final String? cafe24MemberId;

  /// false면 로그인 차단.
  final bool active;
  final List<PartnerAddress> addresses;

  PartnerAddress? get defaultAddress {
    for (final PartnerAddress a in addresses) {
      if (a.isDefault) return a;
    }
    return addresses.isEmpty ? null : addresses.first;
  }

  factory Partner.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final Map<String, dynamic> data = doc.data() ?? <String, dynamic>{};
    final List<dynamic> rawAddresses = data['addresses'] as List<dynamic>? ?? <dynamic>[];
    return Partner(
      id: doc.id,
      name: data['name'] as String? ?? '',
      manager: data['manager'] as String?,
      phone: data['phone'] as String?,
      cafe24MemberId: data['cafe24MemberId'] as String?,
      active: data['active'] as bool? ?? true,
      addresses: rawAddresses
          .map((dynamic a) => PartnerAddress.fromMap(a as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'name': name,
      'manager': manager,
      'phone': phone,
      'cafe24MemberId': cafe24MemberId,
      'active': active,
      'addresses': addresses.map((PartnerAddress a) => a.toMap()).toList(),
    };
  }
}
