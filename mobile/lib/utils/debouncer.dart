import 'dart:async';

class Debouncer {
  final Duration delay;
  Timer? _timer;

  Debouncer({this.delay = const Duration(milliseconds: 300)});

  void run(Function action) {
    _timer?.cancel();
    _timer = Timer(delay, () => action());
  }

  void dispose() {
    _timer?.cancel();
  }
}
