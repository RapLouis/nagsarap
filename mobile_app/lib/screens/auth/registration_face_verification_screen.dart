import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../core/app_colors.dart';
import '../../services/registration_service.dart';
import '../../widgets/app_dialog.dart';
import 'auth_gate.dart';

class RegistrationFaceVerificationScreen extends StatefulWidget {
  const RegistrationFaceVerificationScreen({super.key});

  @override
  State<RegistrationFaceVerificationScreen> createState() =>
      _RegistrationFaceVerificationScreenState();
}

class _RegistrationFaceVerificationScreenState
    extends State<RegistrationFaceVerificationScreen> {
  WebViewController? _controller;

  bool _loading = true;
  bool _completed = false;

  String? _error;

  @override
  void initState() {
    super.initState();

    _startVerification();
  }

  /*
  |--------------------------------------------------------------------------
  | START EXISTING LARAVEL WEB VERIFICATION
  |--------------------------------------------------------------------------
  */

  Future<void> _startVerification() async {
    if (!mounted) {
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      /*
      |--------------------------------------------------------------------------
      | GET TEMPORARY SIGNED WEB URL
      |--------------------------------------------------------------------------
      */

      final url = await RegistrationService.instance.getWebVerificationUrl();

      if (!mounted) {
        return;
      }

      if (url == null) {
        setState(() {
          _loading = false;

          _error = 'Unable to start biometric verification.';
        });

        return;
      }

      if (url == 'ALREADY_VERIFIED') {
        await _finish();

        return;
      }

      debugPrint('Opening Laravel verification page: $url');

      /*
      |--------------------------------------------------------------------------
      | WEBVIEW
      |--------------------------------------------------------------------------
      */

      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.white)
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageStarted: (String url) {
              debugPrint('WEBVIEW START: $url');

              _checkForSuccess(url);
            },

            onPageFinished: (String url) {
              debugPrint('WEBVIEW FINISHED: $url');

              if (mounted) {
                setState(() {
                  _loading = false;
                });
              }

              _checkForSuccess(url);
            },

            onWebResourceError: (WebResourceError error) {
              debugPrint(
                'WEBVIEW ERROR: '
                '${error.errorCode} '
                '${error.description}',
              );
            },

            onNavigationRequest: (NavigationRequest request) {
              debugPrint(
                'WEBVIEW NAVIGATION: '
                '${request.url}',
              );

              _checkForSuccess(request.url);

              return NavigationDecision.navigate;
            },
          ),
        );

      /*
      |--------------------------------------------------------------------------
      | ANDROID WEBVIEW CAMERA PERMISSION
      |--------------------------------------------------------------------------
      |
      | Your existing verify-face.tsx calls:
      |
      | navigator.mediaDevices.getUserMedia(...)
      |
      | so Android WebView must grant the page camera permission.
      |
      */

      final platform = controller.platform;

      if (platform is AndroidWebViewController) {
        await AndroidWebViewController.enableDebugging(true);

        await platform.setMediaPlaybackRequiresUserGesture(false);

        await platform.setOnPlatformPermissionRequest((request) async {
          debugPrint(
            'WEBVIEW PERMISSION REQUEST: '
            '${request.types}',
          );

          await request.grant();
        });
      }

      _controller = controller;

      await controller.loadRequest(Uri.parse(url));

      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
      });
    } catch (e) {
      debugPrint('BIOMETRIC WEBVIEW START ERROR: $e');

      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;

        _error = 'Unable to open biometric verification.\n\n$e';
      });
    }
  }

  /*
  |--------------------------------------------------------------------------
  | EXISTING WEB FLOW SUCCESS
  |--------------------------------------------------------------------------
  |
  | verify-face.tsx posts:
  |
  | /register/verify-face
  |
  | FaceVerificationController then redirects the verified student to:
  |
  | /dashboard
  |
  | We intercept that URL and return to Flutter.
  |
  */

  void _checkForSuccess(String url) {
    if (_completed) {
      return;
    }

    final uri = Uri.tryParse(url);

    if (uri == null) {
      return;
    }

    if (uri.path == '/dashboard' || uri.path.endsWith('/dashboard')) {
      _finish();
    }
  }

  /*
  |--------------------------------------------------------------------------
  | FINISH
  |--------------------------------------------------------------------------
  */

  Future<void> _finish() async {
    if (_completed || !mounted) {
      return;
    }

    _completed = true;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AppDialog(
          type: AppDialogType.success,
          title: 'Identity Verified',
          message:
              'Your biometric registration has been completed successfully.',
          primaryText: 'Continue',
          primaryAction: () {
            Navigator.of(dialogContext).pop();
          },
        );
      },
    );

    if (!mounted) {
      return;
    }

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthGate()),
      (_) => false,
    );
  }

  /*
  |--------------------------------------------------------------------------
  | UI
  |--------------------------------------------------------------------------
  */

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Live Face Verification')),
      body: SafeArea(
        child: Stack(
          children: [
            _body(),

            if (_loading)
              Container(
                color: Colors.white.withValues(alpha: 0.85),
                alignment: Alignment.center,
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: AppColors.navy),
                    SizedBox(height: 14),
                    Text(
                      'Loading biometric verification...',
                      style: TextStyle(
                        color: AppColors.navy,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                size: 58,
                color: AppColors.error,
              ),

              const SizedBox(height: 16),

              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14),
              ),

              const SizedBox(height: 22),

              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _startVerification,
                  child: const Text('Try Again'),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final controller = _controller;

    if (controller == null) {
      return const SizedBox.expand();
    }

    return WebViewWidget(controller: controller);
  }
}
