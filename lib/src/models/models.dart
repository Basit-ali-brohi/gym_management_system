class AuthUser {
  const AuthUser({
    required this.id,
    required this.fullName,
    required this.email,
    required this.roles,
    required this.tenantSlug,
  });

  final int id;
  final String fullName;
  final String email;
  final List<String> roles;
  final String tenantSlug;

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    final normalizedRoles = (json['roles'] as List<dynamic>? ?? [])
        .map((e) => e.toString().trim().toLowerCase().replaceAll(' ', '_'))
        .where((r) => r.isNotEmpty)
        .toSet()
        .toList();
    return AuthUser(
      id: (json['id'] as num).toInt(),
      fullName: json['fullName'] as String? ?? '',
      email: json['email'] as String? ?? '',
      roles: normalizedRoles,
      tenantSlug: json['tenantSlug'] as String? ?? '',
    );
  }
}

class Member {
  const Member({
    required this.id,
    required this.memberCode,
    required this.fullName,
    required this.phone,
    required this.email,
    required this.status,
    required this.joinDate,
    required this.branchName,
  });

  final int id;
  final String memberCode;
  final String fullName;
  final String? phone;
  final String? email;
  final String status;
  final String joinDate;
  final String? branchName;

  factory Member.fromJson(Map<String, dynamic> json) {
    return Member(
      id: (json['id'] as num).toInt(),
      memberCode: json['member_code']?.toString() ?? '',
      fullName: json['full_name']?.toString() ?? '',
      phone: json['phone']?.toString(),
      email: json['email']?.toString(),
      status: json['status']?.toString() ?? 'active',
      joinDate: json['join_date']?.toString() ?? '',
      branchName: json['branch_name']?.toString(),
    );
  }
}

class Plan {
  const Plan({
    required this.id,
    required this.name,
    required this.durationDays,
    required this.price,
    required this.admissionFee,
    required this.status,
  });

  final int id;
  final String name;
  final int durationDays;
  final num price;
  final num admissionFee;
  final String status;

  factory Plan.fromJson(Map<String, dynamic> json) {
    num parseNum(dynamic v) {
      if (v == null) return 0;
      if (v is num) return v;
      if (v is String) return num.tryParse(v) ?? 0;
      return 0;
    }

    return Plan(
      id: (json['id'] as num).toInt(),
      name: json['name']?.toString() ?? '',
      durationDays: parseNum(json['duration_days']).toInt(),
      price: parseNum(json['price']),
      admissionFee: parseNum(json['admission_fee']),
      status: json['status']?.toString() ?? 'active',
    );
  }
}

class AttendanceLog {
  const AttendanceLog({
    required this.id,
    required this.memberId,
    required this.memberCode,
    required this.fullName,
    required this.checkedInAt,
    required this.checkedOutAt,
  });

  final int id;
  final int memberId;
  final String memberCode;
  final String fullName;
  final String checkedInAt;
  final String? checkedOutAt;

  factory AttendanceLog.fromJson(Map<String, dynamic> json) {
    return AttendanceLog(
      id: (json['id'] as num).toInt(),
      memberId: (json['member_id'] as num).toInt(),
      memberCode: json['member_code']?.toString() ?? '',
      fullName: json['full_name']?.toString() ?? '',
      checkedInAt: json['checked_in_at']?.toString() ?? '',
      checkedOutAt: json['checked_out_at']?.toString(),
    );
  }
}

class Invoice {
  const Invoice({
    required this.id,
    required this.invoiceNo,
    required this.total,
    required this.status,
    required this.createdAt,
    required this.memberName,
  });

  final int id;
  final String invoiceNo;
  final num total;
  final String status;
  final String createdAt;
  final String memberName;

  factory Invoice.fromJson(Map<String, dynamic> json) {
    return Invoice(
      id: (json['id'] as num).toInt(),
      invoiceNo: json['invoice_no']?.toString() ?? '',
      total: json['total'] as num? ?? 0,
      status: json['status']?.toString() ?? '',
      createdAt: json['created_at']?.toString() ?? '',
      memberName: json['full_name']?.toString() ?? '',
    );
  }
}

class GymSettings {
  const GymSettings({
    required this.gymName,
    required this.currency,
    required this.defaultTaxPercent,
    required this.enableSounds,
    required this.enableAnimations,
    required this.address,
    required this.logoUrl,
    required this.websiteUrl,
    required this.facebookUrl,
    required this.instagramUrl,
    required this.whatsapp,
  });

  final String? gymName;
  final String currency;
  final double defaultTaxPercent;
  final bool enableSounds;
  final bool enableAnimations;
  final String? address;
  final String? logoUrl;
  final String? websiteUrl;
  final String? facebookUrl;
  final String? instagramUrl;
  final String? whatsapp;

  factory GymSettings.fromJson(Map<String, dynamic> json) {
    return GymSettings(
      gymName: json['gymName']?.toString(),
      currency: json['currency']?.toString() ?? 'PKR',
      defaultTaxPercent: (json['defaultTaxPercent'] as num?)?.toDouble() ?? 5,
      enableSounds: json['enableSounds'] == true,
      enableAnimations: json['enableAnimations'] == true,
      address: json['address']?.toString(),
      logoUrl: json['logoUrl']?.toString(),
      websiteUrl: json['websiteUrl']?.toString(),
      facebookUrl: json['facebookUrl']?.toString(),
      instagramUrl: json['instagramUrl']?.toString(),
      whatsapp: json['whatsapp']?.toString(),
    );
  }
}

class Payment {
  const Payment({
    required this.id,
    required this.invoiceId,
    required this.invoiceNo,
    required this.memberName,
    required this.memberCode,
    required this.amount,
    required this.method,
    required this.paidAt,
  });

  final int id;
  final int invoiceId;
  final String invoiceNo;
  final String memberName;
  final String memberCode;
  final num amount;
  final String method;
  final String paidAt;

  factory Payment.fromJson(Map<String, dynamic> json) {
    return Payment(
      id: (json['id'] as num).toInt(),
      invoiceId: (json['invoiceId'] as num).toInt(),
      invoiceNo: json['invoiceNo']?.toString() ?? '',
      memberName: json['memberName']?.toString() ?? '',
      memberCode: json['memberCode']?.toString() ?? '',
      amount: json['amount'] as num? ?? 0,
      method: json['method']?.toString() ?? '',
      paidAt: json['paidAt']?.toString() ?? '',
    );
  }
}

class Expense {
  const Expense({
    required this.id,
    required this.category,
    required this.amount,
    required this.expenseDate,
    required this.notes,
    required this.createdAt,
  });

  final int id;
  final String category;
  final num amount;
  final String expenseDate;
  final String? notes;
  final String createdAt;

  factory Expense.fromJson(Map<String, dynamic> json) {
    return Expense(
      id: (json['id'] as num).toInt(),
      category: json['category']?.toString() ?? '',
      amount: json['amount'] as num? ?? 0,
      expenseDate: json['expenseDate']?.toString() ?? '',
      notes: json['notes']?.toString(),
      createdAt: json['createdAt']?.toString() ?? '',
    );
  }
}

class Product {
  const Product({
    required this.id,
    required this.name,
    required this.sku,
    required this.price,
    required this.status,
    required this.onHand,
  });

  final int id;
  final String name;
  final String? sku;
  final num price;
  final String status;
  final int onHand;

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: (json['id'] as num).toInt(),
      name: json['name']?.toString() ?? '',
      sku: json['sku']?.toString(),
      price: json['price'] as num? ?? 0,
      status: json['status']?.toString() ?? 'active',
      onHand: (json['onHand'] as num?)?.toInt() ?? 0,
    );
  }
}

class StockMovement {
  const StockMovement({
    required this.id,
    required this.productId,
    required this.productName,
    required this.qty,
    required this.movementType,
    required this.reason,
    required this.createdAt,
  });

  final int id;
  final int productId;
  final String productName;
  final int qty;
  final String movementType;
  final String? reason;
  final String createdAt;

  factory StockMovement.fromJson(Map<String, dynamic> json) {
    return StockMovement(
      id: (json['id'] as num).toInt(),
      productId: (json['productId'] as num).toInt(),
      productName: json['productName']?.toString() ?? '',
      qty: (json['qty'] as num?)?.toInt() ?? 0,
      movementType: json['movementType']?.toString() ?? '',
      reason: json['reason']?.toString(),
      createdAt: json['createdAt']?.toString() ?? '',
    );
  }
}

class StaffUser {
  const StaffUser({
    required this.id,
    required this.email,
    required this.fullName,
    required this.status,
    required this.roles,
    required this.createdAt,
  });

  final int id;
  final String email;
  final String fullName;
  final String status;
  final List<String> roles;
  final String createdAt;

  factory StaffUser.fromJson(Map<String, dynamic> json) {
    return StaffUser(
      id: (json['id'] as num).toInt(),
      email: json['email']?.toString() ?? '',
      fullName: json['fullName']?.toString() ?? '',
      status: json['status']?.toString() ?? 'active',
      roles: (json['roles'] as List<dynamic>? ?? []).map((e) => e.toString()).toList(),
      createdAt: json['createdAt']?.toString() ?? '',
    );
  }
}

class Lead {
  const Lead({
    required this.id,
    required this.fullName,
    required this.phone,
    required this.source,
    required this.interest,
    required this.nextContactDate,
    required this.status,
    required this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String fullName;
  final String? phone;
  final String? source;
  final String? interest;
  final String? nextContactDate;
  final String status;
  final String? notes;
  final String createdAt;
  final String updatedAt;

  factory Lead.fromJson(Map<String, dynamic> json) {
    return Lead(
      id: (json['id'] as num).toInt(),
      fullName: json['fullName']?.toString() ?? '',
      phone: json['phone']?.toString(),
      source: json['source']?.toString(),
      interest: json['interest']?.toString(),
      nextContactDate: json['nextContactDate']?.toString(),
      status: json['status']?.toString() ?? 'new',
      notes: json['notes']?.toString(),
      createdAt: json['createdAt']?.toString() ?? '',
      updatedAt: json['updatedAt']?.toString() ?? '',
    );
  }
}
