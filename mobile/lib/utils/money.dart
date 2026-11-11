import 'package:intl/intl.dart';

const kSupportedExpenseCurrencies = [
  'INR',
  'USD',
  'EUR',
  'AED',
  'GBP',
  'SGD',
  'AUD',
  'CAD',
];

String currencySymbol(String currency) {
  switch (currency) {
    case 'INR':
      return '₹';
    case 'USD':
      return '\$';
    case 'EUR':
      return '€';
    case 'GBP':
      return '£';
    case 'AED':
      return 'AED ';
    default:
      return '$currency ';
  }
}

String formatMoneyMinor(int minor, {String currency = 'INR'}) {
  final value = minor / 100.0;
  final symbol = currencySymbol(currency);
  final digits = minor % 100 == 0 ? 0 : 2;
  return NumberFormat.currency(
    locale: 'en_IN',
    symbol: symbol,
    decimalDigits: digits,
  ).format(value);
}

int rupeesToMinor(double amount) {
  return (amount * 100).round();
}

double? parseRupees(String input) {
  final cleaned = input.replaceAll(',', '').replaceAll('₹', '').trim();
  if (cleaned.isEmpty) return null;
  return double.tryParse(cleaned);
}

String categoryLabel(String category) {
  switch (category) {
    case 'FOOD':
      return 'Food';
    case 'STAY':
      return 'Stay';
    case 'TRANSPORT':
      return 'Transport';
    case 'ACTIVITIES':
      return 'Activities';
    case 'SHOPPING':
      return 'Shopping';
    default:
      return 'Other';
  }
}
