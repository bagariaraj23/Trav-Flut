class ExpenseUser {
  final String id;
  final String? username;
  final String? name;
  final String? avatarUrl;

  const ExpenseUser({
    required this.id,
    this.username,
    this.name,
    this.avatarUrl,
  });

  factory ExpenseUser.fromJson(Map<String, dynamic> json) {
    return ExpenseUser(
      id: json['id'] as String? ?? json['userId'] as String? ?? '',
      username: json['username'] as String?,
      name: json['name'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
    );
  }
}

class ExpenseShare {
  final String userId;
  final int shareMinor;
  final int? weight;
  final ExpenseUser? user;

  const ExpenseShare({
    required this.userId,
    required this.shareMinor,
    this.weight,
    this.user,
  });

  factory ExpenseShare.fromJson(Map<String, dynamic> json) {
    return ExpenseShare(
      userId: json['userId'] as String,
      shareMinor: json['shareMinor'] as int,
      weight: json['weight'] as int?,
      user: json['user'] is Map<String, dynamic>
          ? ExpenseUser.fromJson(json['user'] as Map<String, dynamic>)
          : null,
    );
  }
}

class TripExpense {
  final String id;
  final String tripId;
  final String createdById;
  final String payerId;
  final String title;
  final String category;
  final int amountMinor;
  final String currency;
  final String splitMethod;
  final String? note;
  final DateTime createdAt;
  final ExpenseUser? createdBy;
  final ExpenseUser? payer;
  final List<ExpenseShare> shares;

  const TripExpense({
    required this.id,
    required this.tripId,
    required this.createdById,
    required this.payerId,
    required this.title,
    required this.category,
    required this.amountMinor,
    required this.currency,
    required this.splitMethod,
    this.note,
    required this.createdAt,
    this.createdBy,
    this.payer,
    this.shares = const [],
  });

  factory TripExpense.fromJson(Map<String, dynamic> json) {
    return TripExpense(
      id: json['id'] as String,
      tripId: json['tripId'] as String,
      createdById: json['createdById'] as String,
      payerId: json['payerId'] as String,
      title: json['title'] as String,
      category: json['category'] as String,
      amountMinor: json['amountMinor'] as int,
      currency: json['currency'] as String? ?? 'INR',
      splitMethod: json['splitMethod'] as String,
      note: json['note'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      createdBy: json['createdBy'] is Map<String, dynamic>
          ? ExpenseUser.fromJson(json['createdBy'] as Map<String, dynamic>)
          : null,
      payer: json['payer'] is Map<String, dynamic>
          ? ExpenseUser.fromJson(json['payer'] as Map<String, dynamic>)
          : null,
      shares: (json['shares'] as List<dynamic>? ?? [])
          .map((s) => ExpenseShare.fromJson(s as Map<String, dynamic>))
          .toList(),
    );
  }
}

class ExpenseMemberBalance {
  final String userId;
  final String? name;
  final String? username;
  final String? avatarUrl;
  final int netMinor;
  final int paidMinor;
  final int owedMinor;

  const ExpenseMemberBalance({
    required this.userId,
    this.name,
    this.username,
    this.avatarUrl,
    required this.netMinor,
    required this.paidMinor,
    required this.owedMinor,
  });

  factory ExpenseMemberBalance.fromJson(Map<String, dynamic> json) {
    return ExpenseMemberBalance(
      userId: json['userId'] as String,
      name: json['name'] as String?,
      username: json['username'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
      netMinor: json['netMinor'] as int,
      paidMinor: json['paidMinor'] as int,
      owedMinor: json['owedMinor'] as int,
    );
  }
}

class OpenTransfer {
  final String fromUserId;
  final String toUserId;
  final int amountMinor;
  final bool canMarkPaid;

  const OpenTransfer({
    required this.fromUserId,
    required this.toUserId,
    required this.amountMinor,
    required this.canMarkPaid,
  });

  factory OpenTransfer.fromJson(Map<String, dynamic> json) {
    return OpenTransfer(
      fromUserId: json['fromUserId'] as String,
      toUserId: json['toUserId'] as String,
      amountMinor: json['amountMinor'] as int,
      canMarkPaid: json['canMarkPaid'] as bool? ?? false,
    );
  }
}

class RecordedSettlement {
  final String id;
  final String fromUserId;
  final String toUserId;
  final int amountMinor;
  final String status;
  final DateTime createdAt;
  final ExpenseUser? fromUser;
  final ExpenseUser? toUser;
  final bool canUndo;

  const RecordedSettlement({
    required this.id,
    required this.fromUserId,
    required this.toUserId,
    required this.amountMinor,
    required this.status,
    required this.createdAt,
    this.fromUser,
    this.toUser,
    this.canUndo = false,
  });

  factory RecordedSettlement.fromJson(Map<String, dynamic> json) {
    return RecordedSettlement(
      id: json['id'] as String,
      fromUserId: json['fromUserId'] as String,
      toUserId: json['toUserId'] as String,
      amountMinor: json['amountMinor'] as int,
      status: json['status'] as String? ?? 'PAID',
      createdAt: DateTime.parse(json['createdAt'] as String),
      fromUser: json['fromUser'] is Map<String, dynamic>
          ? ExpenseUser.fromJson(json['fromUser'] as Map<String, dynamic>)
          : null,
      toUser: json['toUser'] is Map<String, dynamic>
          ? ExpenseUser.fromJson(json['toUser'] as Map<String, dynamic>)
          : null,
      canUndo: json['canUndo'] as bool? ?? false,
    );
  }
}

class PairwiseBalance {
  final String otherUserId;
  final int netMinor;
  final int sharedCount;
  final int youOweMinor;
  final int theyOweMinor;

  const PairwiseBalance({
    required this.otherUserId,
    required this.netMinor,
    required this.sharedCount,
    required this.youOweMinor,
    required this.theyOweMinor,
  });

  factory PairwiseBalance.fromJson(Map<String, dynamic> json) {
    return PairwiseBalance(
      otherUserId: json['otherUserId'] as String,
      netMinor: json['netMinor'] as int,
      sharedCount: json['sharedCount'] as int,
      youOweMinor: json['youOweMinor'] as int,
      theyOweMinor: json['theyOweMinor'] as int,
    );
  }
}

class ExpenseSummary {
  final String currency;
  final int totalSpendMinor;
  final int myNetMinor;
  final List<ExpenseMemberBalance> members;
  final List<OpenTransfer> openTransfers;
  final List<RecordedSettlement> recordedSettlements;
  final List<PairwiseBalance> pairwise;

  const ExpenseSummary({
    required this.currency,
    required this.totalSpendMinor,
    required this.myNetMinor,
    required this.members,
    required this.openTransfers,
    required this.recordedSettlements,
    required this.pairwise,
  });

  factory ExpenseSummary.fromJson(Map<String, dynamic> json) {
    return ExpenseSummary(
      currency: json['currency'] as String? ?? 'INR',
      totalSpendMinor: json['totalSpendMinor'] as int? ?? 0,
      myNetMinor: json['myNetMinor'] as int? ?? 0,
      members: (json['members'] as List<dynamic>? ?? [])
          .map((m) => ExpenseMemberBalance.fromJson(m as Map<String, dynamic>))
          .toList(),
      openTransfers: (json['openTransfers'] as List<dynamic>? ?? [])
          .map((t) => OpenTransfer.fromJson(t as Map<String, dynamic>))
          .toList(),
      recordedSettlements: (json['recordedSettlements'] as List<dynamic>? ?? [])
          .map((s) => RecordedSettlement.fromJson(s as Map<String, dynamic>))
          .toList(),
      pairwise: (json['pairwise'] as List<dynamic>? ?? [])
          .map((p) => PairwiseBalance.fromJson(p as Map<String, dynamic>))
          .toList(),
    );
  }
}

class ExpenseListPage {
  final List<TripExpense> items;
  final int page;
  final int limit;
  final int total;
  final bool hasNext;

  const ExpenseListPage({
    required this.items,
    required this.page,
    required this.limit,
    required this.total,
    required this.hasNext,
  });

  factory ExpenseListPage.fromJson(Map<String, dynamic> json) {
    return ExpenseListPage(
      items: (json['items'] as List<dynamic>? ?? [])
          .map((e) => TripExpense.fromJson(e as Map<String, dynamic>))
          .toList(),
      page: json['page'] as int? ?? 1,
      limit: json['limit'] as int? ?? 20,
      total: json['total'] as int? ?? 0,
      hasNext: json['hasNext'] as bool? ?? false,
    );
  }
}

class CreateExpenseRequest {
  final String title;
  final String category;
  final int amountMinor;
  final String payerId;
  final String splitMethod;
  final List<String> memberIds;
  final List<Map<String, dynamic>>? shares;
  final List<Map<String, dynamic>>? percentBps;
  final List<Map<String, dynamic>>? weights;
  final String? note;

  const CreateExpenseRequest({
    required this.title,
    required this.category,
    required this.amountMinor,
    required this.payerId,
    required this.splitMethod,
    required this.memberIds,
    this.shares,
    this.percentBps,
    this.weights,
    this.note,
  });

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'category': category,
      'amountMinor': amountMinor,
      'payerId': payerId,
      'splitMethod': splitMethod,
      'memberIds': memberIds,
      if (shares != null) 'shares': shares,
      if (percentBps != null) 'percentBps': percentBps,
      if (weights != null) 'weights': weights,
      if (note != null && note!.isNotEmpty) 'note': note,
    };
  }
}
