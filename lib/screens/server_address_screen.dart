import 'package:flutter/material.dart';
import 'package:mfiles_app/theme/app_colors.dart';
import 'package:provider/provider.dart';

import '../services/mfiles_service.dart';

class ServerAddressScreen extends StatefulWidget {
  const ServerAddressScreen({super.key});

  @override
  State<ServerAddressScreen> createState() => _ServerAddressScreenState();
}

class _ServerAddressScreenState extends State<ServerAddressScreen> {
  final TextEditingController _addressController = TextEditingController();
  final FocusNode _addressFocusNode = FocusNode();
  String? _error;
  bool _loading = false;
  bool _showRecent = false;

  bool _helpPressed = false;

  List<String> _recentAddresses = [];

  @override
  void initState() {
    super.initState();
    _loadRecentAddresses();
    // Only react to focus being GAINED here. Hiding the recent-addresses
    // list is handled explicitly (on selection, on submit, on tapping the
    // background) rather than tied to blur — tapping the remove ("x")
    // button on a recent item also shifts focus away from the field, and
    // if that blur hid the list immediately, the button's own tap would
    // never complete because its parent had already been removed from
    // the tree mid-gesture.
    _addressFocusNode.addListener(() {
      if (_addressFocusNode.hasFocus) {
        setState(() => _showRecent = true);
      } else {
        setState(() {}); // repaint border color for the now-unfocused field
      }
    });
  }

  Future<void> _loadRecentAddresses() async {
    final service = context.read<MFilesService>();
    await service.loadRecentServerAddresses();
    if (!mounted) return;
    setState(() => _recentAddresses = service.recentServerAddresses);
  }

  @override
  void dispose() {
    _addressController.dispose();
    _addressFocusNode.dispose();
    super.dispose();
  }

  bool _looksLikeValidAddress(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  // Populates the field with a recent address and lets the user confirm
  // with Continue, instead of navigating right away.
  void _selectRecentAddress(String address) {
    _addressController.text = address;
    _addressController.selection = TextSelection.collapsed(
      offset: _addressController.text.length,
    );
    setState(() {
      _error = null;
      _showRecent = false;
    });
    _addressFocusNode.unfocus();
  }

  Future<void> _continue([String? overrideAddress]) async {
    final input = overrideAddress ?? _addressController.text.trim();

    if (input.isEmpty) {
      setState(() => _error = 'Please enter a server address');
      return;
    }
    if (!_looksLikeValidAddress(input)) {
      setState(() =>
          _error = 'Enter a full address including http:// or https://');
      return;
    }

    _addressFocusNode.unfocus();

    setState(() {
      _error = null;
      _loading = true;
      _showRecent = false;
    });

    await context.read<MFilesService>().setServerAddress(input);

    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/login');
  }

  Future<void> _removeRecent(String address) async {
    await context.read<MFilesService>().removeRecentServerAddress(address);
    if (!mounted) return;
    setState(() => _recentAddresses.remove(address));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: GestureDetector(
        onTap: () {
          FocusScope.of(context).unfocus();
          setState(() => _showRecent = false);
        },
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child:
                            Image.asset('assets/alignsysnew.png', height: 85),
                      ),
                    ),
                    const SizedBox(height: 22),
                    const Text(
                      'Connect to your server',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.15),
                            blurRadius: 20,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: _addressController,
                            focusNode: _addressFocusNode,
                            keyboardType: TextInputType.url,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _continue(),
                            onChanged: (_) {
                              if (_error != null) {
                                setState(() => _error = null);
                              }
                            },
                            decoration: InputDecoration(
                              labelText: 'Server address',
                              hintText:
                                  'https://alignsys.tech or http://192.168.2.100:8003',
                              hintStyle: TextStyle(
                                fontSize: 12.5,
                                color: Colors.grey.shade400,
                              ),
                              prefixIcon: Icon(
                                Icons.dns_outlined,
                                color: _addressFocusNode.hasFocus
                                    ? AppColors.primary
                                    : Colors.grey.shade500,
                              ),
                              errorText: _error,
                              errorMaxLines: 2,
                              filled: true,
                              fillColor: AppColors.surfaceLight,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide:
                                    BorderSide(color: Colors.grey.shade300),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide:
                                    BorderSide(color: Colors.grey.shade300),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                  color: AppColors.primary,
                                  width: 2,
                                ),
                              ),
                              errorBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide:
                                    BorderSide(color: Colors.red.shade400),
                              ),
                              focusedErrorBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: Colors.red.shade400,
                                  width: 2,
                                ),
                              ),
                            ),
                          ),

                          // ── RECENT ADDRESSES DROPDOWN ──
                          // Lives inside the same card, directly under the
                          // field, and only appears while the field has
                          // focus, collapsing the moment focus is lost or
                          // an entry is picked.
                          AnimatedSize(
                            duration: const Duration(milliseconds: 150),
                            curve: Curves.easeOut,
                            alignment: Alignment.topCenter,
                            child:
                                (_showRecent && _recentAddresses.isNotEmpty)
                                    ? ExcludeFocus(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            const SizedBox(height: 8),
                                            Container(
                                              constraints:
                                                  const BoxConstraints(
                                                      maxHeight: 168),
                                              decoration: BoxDecoration(
                                                color: AppColors.surfaceLight,
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                border: Border.all(
                                                    color:
                                                        Colors.grey.shade200),
                                              ),
                                              child: ListView.separated(
                                                shrinkWrap: true,
                                                padding: EdgeInsets.zero,
                                                itemCount:
                                                    _recentAddresses.length,
                                                separatorBuilder: (_, __) =>
                                                    Divider(
                                                  height: 1,
                                                  color: Colors.grey.shade200,
                                                ),
                                                itemBuilder: (context, i) =>
                                                    ListTile(
                                                  dense: true,
                                                  contentPadding:
                                                      const EdgeInsets.only(
                                                          left: 12, right: 4),
                                                  minLeadingWidth: 8,
                                                  leading: const Icon(
                                                    Icons.history,
                                                    color: AppColors.primary,
                                                    size: 18,
                                                  ),
                                                  title: Text(
                                                    _recentAddresses[i],
                                                    style: const TextStyle(
                                                        fontSize: 13.5),
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                  trailing: IconButton(
                                                    icon: Icon(
                                                      Icons.close,
                                                      size: 15,
                                                      color:
                                                          Colors.grey.shade400,
                                                    ),
                                                    padding: EdgeInsets.zero,
                                                    constraints:
                                                        const BoxConstraints(
                                                      minWidth: 28,
                                                      minHeight: 28,
                                                    ),
                                                    splashRadius: 16,
                                                    onPressed: () =>
                                                        _removeRecent(
                                                            _recentAddresses[
                                                                i]),
                                                  ),
                                                  onTap: _loading
                                                      ? null
                                                      : () =>
                                                          _selectRecentAddress(
                                                              _recentAddresses[
                                                                  i]),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                    : const SizedBox.shrink(),
                          ),

                          const SizedBox(height: 16),
                          _loading
                              ? const Center(
                                  child: CircularProgressIndicator())
                              : ElevatedButton(
                                  onPressed: _continue,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: const Text(
                                    'Continue',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    _buildHelpNote(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Bottom-center help note, rendered as a soft translucent pill so it
  // reads as a single tappable affordance rather than loose text on the
  // background. Tapping shows a tooltip with the full explanation.
  Widget _buildHelpNote() {
    return Tooltip(
      message: 'Paste the full server address your organization gave you, '
          'including http:// or https://. If you are not sure what to '
          'enter, contact your administrator.',
      triggerMode: TooltipTriggerMode.tap,
      preferBelow: false,
      textStyle: const TextStyle(fontSize: 12.5, color: Colors.white),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.85),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _helpPressed = true),
        onTapCancel: () => setState(() => _helpPressed = false),
        onTapUp: (_) => setState(() => _helpPressed = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          constraints: const BoxConstraints(maxWidth: 360),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(_helpPressed ? 0.20 : 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withOpacity(0.18),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                Icons.help_outline_rounded,
                size: 15,
                color: Colors.white.withOpacity(0.9),
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  'Need help? Contact your administrator',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withOpacity(0.92),
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}