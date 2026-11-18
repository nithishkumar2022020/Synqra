import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/smooth_page_route.dart';
import '../providers/settings_provider.dart';
import 'root_shell_screen.dart';

class ClearanceAuthScreen extends StatefulWidget {
  const ClearanceAuthScreen({super.key});

  @override
  State<ClearanceAuthScreen> createState() => _ClearanceAuthScreenState();
}

class _ClearanceAuthScreenState extends State<ClearanceAuthScreen> {
  bool _isSignUp =
      false; // false = Claim Clearance (Sign In), true = Issue Field Dossier (Sign Up)

  final TextEditingController _callSignController = TextEditingController(
    text: 'ARCH-9942',
  );
  final TextEditingController _passkeyController = TextEditingController(
    text: '••••••••••••',
  );
  final TextEditingController _researcherNameController = TextEditingController(
    text: 'Nithish R.',
  );
  final TextEditingController _emailController = TextEditingController(
    text: 'nithish@synqra.ai',
  );
  final TextEditingController _confirmationCodeController =
      TextEditingController();

  String _selectedClearance = 'Level-3 Architect';

  final List<String> _clearanceLevels = const [
    'Level-1 Reader',
    'Level-2 Analyst',
    'Level-3 Architect',
  ];

  @override
  void dispose() {
    _callSignController.dispose();
    _passkeyController.dispose();
    _researcherNameController.dispose();
    _emailController.dispose();
    _confirmationCodeController.dispose();
    super.dispose();
  }

  void _proceedToWorkspace() {
    Navigator.of(
      context,
    ).pushReplacement(SmoothPageRoute(page: const RootShellScreen()));
  }

  Future<void> _handleManagedLogin() async {
    final settingsProv = context.read<SettingsProvider>();
    settingsProv.clearAuthError();

    final success = await settingsProv.signInWithManagedLogin();
    if (!mounted) return;

    if (success) {
      _proceedToWorkspace();
    }
  }

  Future<void> _handleAuthenticate() async {
    final settingsProv = context.read<SettingsProvider>();
    settingsProv.clearAuthError();

    final bool success;
    if (_isSignUp) {
      success = await settingsProv.signUp(
        researcherName: _researcherNameController.text.trim(),
        callSign: _callSignController.text.trim(),
        clearanceLevel: _selectedClearance,
        passkey: _passkeyController.text,
        email: _emailController.text.trim(),
      );
    } else {
      success = await settingsProv.signIn(
        callSign: _callSignController.text.trim(),
        passkey: _passkeyController.text,
      );
    }

    if (!mounted) return;

    if (success) {
      _proceedToWorkspace();
    } else if (settingsProv.needsConfirmation) {
      _showConfirmationDialog();
    }
  }

  void _showConfirmationDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppTheme.nocturneText : AppTheme.parchmentText;
    final mutedText =
        isDark ? AppTheme.nocturneMutedText : AppTheme.parchmentMutedText;
    final vermilion =
        isDark ? AppTheme.nocturneVermilion : AppTheme.parchmentVermilion;
    final borderColor =
        isDark ? AppTheme.nocturneBorder : AppTheme.parchmentBorder;
    final surfaceColor =
        isDark ? AppTheme.nocturneSurface : AppTheme.parchmentSurface;
    final bg = isDark ? AppTheme.nocturneBg : AppTheme.parchmentBg;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final prov = context.watch<SettingsProvider>();

            return AlertDialog(
              backgroundColor: surfaceColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.zero,
                side: BorderSide(color: borderColor, width: 2),
              ),
              title: Text(
                'AWS COGNITO VERIFICATION',
                style: AppTheme.slabHeader(color: textColor, fontSize: 16),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'A verification code has been dispatched by AWS Cognito for user [${prov.pendingUsername}]. Enter the 6-digit confirmation code below:',
                    style: AppTheme.readingSerif(
                      color: mutedText,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: bg,
                      border: Border.all(color: borderColor, width: 1.5),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: TextField(
                      key: const Key('input_cognito_confirmation_code'),
                      controller: _confirmationCodeController,
                      style: AppTheme.monospace(
                        color: textColor,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText: 'e.g. 123456',
                        hintStyle: AppTheme.monospace(
                          color: mutedText,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                  if (prov.authError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      prov.authError!,
                      style: AppTheme.monospace(color: vermilion, fontSize: 10),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    prov.resetConfirmationState();
                    Navigator.of(dialogContext).pop();
                  },
                  child: Text(
                    'CANCEL',
                    style: AppTheme.monospace(color: mutedText, fontSize: 11),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    await prov.resendConfirmationCode();
                    setDialogState(() {});
                  },
                  child: Text(
                    'RESEND CODE',
                    style: AppTheme.monospace(color: vermilion, fontSize: 11),
                  ),
                ),
                GestureDetector(
                  onTap: () async {
                    final navigator = Navigator.of(dialogContext);
                    final confirmed = await prov.confirmSignUp(
                      confirmationCode: _confirmationCodeController.text.trim(),
                      passkeyToAutoSignIn: _passkeyController.text,
                    );
                    if (confirmed && mounted) {
                      navigator.pop();
                      _proceedToWorkspace();
                    }
                  },
                  child: Container(
                    color: vermilion,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Text(
                      'VERIFY & ENTER',
                      style: AppTheme.monospace(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _handleGuestBypass() async {
    final settingsProv = context.read<SettingsProvider>();
    await settingsProv.enterAsGuest();
    if (mounted) {
      _proceedToWorkspace();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppTheme.nocturneText : AppTheme.parchmentText;
    final mutedText =
        isDark ? AppTheme.nocturneMutedText : AppTheme.parchmentMutedText;
    final vermilion =
        isDark ? AppTheme.nocturneVermilion : AppTheme.parchmentVermilion;
    final borderColor =
        isDark ? AppTheme.nocturneBorder : AppTheme.parchmentBorder;
    final surfaceColor =
        isDark ? AppTheme.nocturneSurface : AppTheme.parchmentSurface;
    final bg = isDark ? AppTheme.nocturneBg : AppTheme.parchmentBg;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Archival Header Ledger Pill
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    color: vermilion,
                    child: Text(
                      'RESTRICTED PROTOCOL // AWS COGNITO',
                      style: AppTheme.monospace(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Consumer<SettingsProvider>(
                    builder:
                        (context, prov, _) => GestureDetector(
                          onTap: () => prov.toggleNocturneMode(),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: borderColor,
                                width: 1.5,
                              ),
                            ),
                            child: Text(
                              isDark ? '☀️ PARCHMENT' : '🌙 NOCTURNE',
                              style: AppTheme.monospace(
                                color: textColor,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Ledger Header Title
              Text(
                'ARCHIVAL CLEARANCE //\nIDENTITY VERIFICATION',
                style: AppTheme.slabHeader(
                  color: textColor,
                  fontSize: 24,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Identity verification powered by AWS Cognito User Pools. Authenticated RS256 Bearer access tokens are dispatched with all hybrid RAG streams and document uploads.',
                style: AppTheme.readingSerif(color: mutedText, fontSize: 12),
              ),
              const SizedBox(height: 20),

              // Cognito Managed Login CTA (Primary OAuth 2.0 PKCE Flow)
              Consumer<SettingsProvider>(
                builder: (context, prov, _) {
                  final isBusy = prov.isAuthenticating;

                  return GestureDetector(
                    key: const Key('cognito_managed_login_btn'),
                    behavior: HitTestBehavior.opaque,
                    onTap: isBusy ? null : _handleManagedLogin,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      alignment: Alignment.center,
                      decoration: AppTheme.brutalistDecoration(
                        bgColor: vermilion,
                        borderColor: borderColor,
                        borderWidth: 2,
                        shadowOffset: const Offset(4, 4),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (isBusy) ...[
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'CONNECTING TO AWS COGNITO...',
                              style: AppTheme.monospace(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ] else ...[
                            const Icon(
                              Icons.open_in_browser,
                              color: Colors.white,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'SIGN IN WITH COGNITO MANAGED LOGIN',
                              style: AppTheme.monospace(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Divider(
                      color: borderColor.withValues(alpha: 0.3),
                      height: 1,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text(
                      'OR USE DIRECT CLEARANCE FORM',
                      style: AppTheme.monospace(color: mutedText, fontSize: 10),
                    ),
                  ),
                  Expanded(
                    child: Divider(
                      color: borderColor.withValues(alpha: 0.3),
                      height: 1,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Tab Switcher: Sign In vs Sign Up
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      key: const Key('auth_tab_signin'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        context.read<SettingsProvider>().clearAuthError();
                        setState(() => _isSignUp = false);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: !_isSignUp ? surfaceColor : bg,
                          border: Border(
                            left: BorderSide(color: borderColor, width: 2),
                            top: BorderSide(color: borderColor, width: 2),
                            right: BorderSide(
                              color: borderColor,
                              width: !_isSignUp ? 2 : 1,
                            ),
                            bottom: BorderSide(
                              color: borderColor,
                              width: !_isSignUp ? 0 : 2,
                            ),
                          ),
                        ),
                        child: Text(
                          'CLAIM CLEARANCE\n(SIGN IN)',
                          textAlign: TextAlign.center,
                          style: AppTheme.monospace(
                            color: !_isSignUp ? vermilion : mutedText,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      key: const Key('auth_tab_signup'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        context.read<SettingsProvider>().clearAuthError();
                        setState(() => _isSignUp = true);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _isSignUp ? surfaceColor : bg,
                          border: Border(
                            left: BorderSide(
                              color: borderColor,
                              width: _isSignUp ? 2 : 1,
                            ),
                            top: BorderSide(color: borderColor, width: 2),
                            right: BorderSide(color: borderColor, width: 2),
                            bottom: BorderSide(
                              color: borderColor,
                              width: _isSignUp ? 0 : 2,
                            ),
                          ),
                        ),
                        child: Text(
                          'ISSUE FIELD DOSSIER\n(SIGN UP)',
                          textAlign: TextAlign.center,
                          style: AppTheme.monospace(
                            color: _isSignUp ? vermilion : mutedText,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              // Ledger Form Fields Box
              Container(
                decoration: BoxDecoration(
                  color: surfaceColor,
                  border: Border(
                    left: BorderSide(color: borderColor, width: 2),
                    right: BorderSide(color: borderColor, width: 2),
                    bottom: BorderSide(color: borderColor, width: 2),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: borderColor,
                      offset: const Offset(4, 4),
                      blurRadius: 0,
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Consumer<SettingsProvider>(
                      builder: (context, prov, _) {
                        if (prov.authError == null) {
                          return const SizedBox.shrink();
                        }
                        return Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 14),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: vermilion.withValues(alpha: 0.12),
                            border: Border.all(color: vermilion, width: 1.5),
                          ),
                          child: Text(
                            prov.authError!,
                            style: AppTheme.monospace(
                              color: vermilion,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        );
                      },
                    ),

                    if (_isSignUp) ...[
                      Text(
                        'RESEARCHER DESIGNATION',
                        style: AppTheme.monospace(
                          color: mutedText,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      _buildTextField(
                        key: const Key('input_researcher_name'),
                        controller: _researcherNameController,
                        hint: 'e.g. Dr. Nithish R.',
                        textColor: textColor,
                        mutedText: mutedText,
                        borderColor: borderColor,
                        bgColor: bg,
                      ),
                      const SizedBox(height: 14),

                      Text(
                        'COGNITO FIELD EMAIL',
                        style: AppTheme.monospace(
                          color: mutedText,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      _buildTextField(
                        key: const Key('input_email'),
                        controller: _emailController,
                        hint: 'e.g. researcher@synqra.ai',
                        textColor: textColor,
                        mutedText: mutedText,
                        borderColor: borderColor,
                        bgColor: bg,
                      ),
                      const SizedBox(height: 14),
                    ],

                    Text(
                      'CALL SIGN / CLEARANCE USERNAME',
                      style: AppTheme.monospace(
                        color: mutedText,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _buildTextField(
                      key: const Key('input_call_sign'),
                      controller: _callSignController,
                      hint: 'e.g. ARCH-9942',
                      textColor: textColor,
                      mutedText: mutedText,
                      borderColor: borderColor,
                      bgColor: bg,
                    ),
                    const SizedBox(height: 14),

                    if (_isSignUp) ...[
                      Text(
                        'SECURITY CLEARANCE TIER',
                        style: AppTheme.monospace(
                          color: mutedText,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: bg,
                          border: Border.all(color: borderColor, width: 1.5),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            key: const Key('dropdown_clearance_level'),
                            value: _selectedClearance,
                            isExpanded: true,
                            dropdownColor: surfaceColor,
                            style: AppTheme.monospace(
                              color: textColor,
                              fontSize: 12,
                            ),
                            items:
                                _clearanceLevels.map((level) {
                                  return DropdownMenuItem(
                                    value: level,
                                    child: Text(level),
                                  );
                                }).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() => _selectedClearance = val);
                              }
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],

                    Text(
                      'SECURITY PASSKEY',
                      style: AppTheme.monospace(
                        color: mutedText,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _buildTextField(
                      key: const Key('input_passkey'),
                      controller: _passkeyController,
                      hint: 'Enter cryptographic passkey',
                      isPassword: true,
                      textColor: textColor,
                      mutedText: mutedText,
                      borderColor: borderColor,
                      bgColor: bg,
                    ),
                    const SizedBox(height: 20),

                    // Authenticate & Enter Submit CTA
                    Consumer<SettingsProvider>(
                      builder: (context, prov, _) {
                        final isBusy = prov.isAuthenticating;

                        return GestureDetector(
                          key: const Key('auth_submit_btn'),
                          behavior: HitTestBehavior.opaque,
                          onTap: isBusy ? null : _handleAuthenticate,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            alignment: Alignment.center,
                            decoration: AppTheme.brutalistDecoration(
                              bgColor: isBusy ? borderColor : vermilion,
                              borderColor: borderColor,
                              borderWidth: 2,
                              shadowOffset: const Offset(4, 4),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (isBusy) ...[
                                  const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    'AUTHENTICATING WITH AWS COGNITO...',
                                    style: AppTheme.monospace(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ] else ...[
                                  const Icon(
                                    Icons.verified_user_outlined,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _isSignUp
                                        ? 'REGISTER IN COGNITO & PROCEED'
                                        : 'AUTHENTICATE & ENTER',
                                    style: AppTheme.monospace(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Guest / Offline Observer Option
              Center(
                child: GestureDetector(
                  key: const Key('auth_guest_btn'),
                  behavior: HitTestBehavior.opaque,
                  onTap: _handleGuestBypass,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: borderColor, width: 1.5),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.remove_red_eye_outlined,
                          color: textColor,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'ENTER AS GUEST / OFFLINE OBSERVER ➔',
                          style: AppTheme.monospace(
                            color: textColor,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required Key key,
    required TextEditingController controller,
    required String hint,
    required Color textColor,
    required Color mutedText,
    required Color borderColor,
    required Color bgColor,
    bool isPassword = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        border: Border.all(color: borderColor, width: 1.5),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: TextField(
        key: key,
        controller: controller,
        obscureText: isPassword,
        style: AppTheme.monospace(color: textColor, fontSize: 13),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: AppTheme.monospace(color: mutedText, fontSize: 12),
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
        ),
      ),
    );
  }
}
