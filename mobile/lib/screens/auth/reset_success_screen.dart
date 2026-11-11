import 'package:flutter/material.dart';
import 'package:tripthread/utils/app_layout.dart';
import 'package:tripthread/utils/app_theme.dart';

class ResetSuccessScreen extends StatelessWidget {
  const ResetSuccessScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('Password Reset'),
        ),
        body: AppLayout.authFormBody(
          context: context,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.check_circle_outline,
                color: AppTheme.live,
                size: 64,
              ),
              const SizedBox(height: 24),
              Text(
                'Password Reset Successful!',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                'Your password has been successfully reset. You can now log in with your new credentials.',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
