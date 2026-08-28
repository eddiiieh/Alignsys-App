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

  List<String> _recentAddresses = [];

  bool _useHttps = true; // secure by default; user can opt into HTTP for on-prem
  String get _scheme => _useHttps ? 'https://' : 'http://';

  @override
  void initState() {
    super.initState();
    _loadRecentAddresses();
    _addressFocusNode.addListener(() {
      setState(() => _showRecent = _addressFocusNode.hasFocus);
    });

    // Pre-fill the scheme so the user only has to type the host, and
    // place the cursor right after it.
    _addressController.text = _scheme;
    _addressController.selection = TextSelection.collapsed(
      offset: _addressController.text.length,
    );
  }

  // Updates the scheme in the field when the user toggles the HTTPS switch.
  void _setUseHttps(bool value) {
    if (_useHttps == value) return;

    final current = _addressController.text;
    const http = 'http://';
    const https = 'https://';

    String updated;
    if (value && current.startsWith(http)) {
      updated = https + current.substring(http.length);
    } else if (!value && current.startsWith(https)) {
      updated = http + current.substring(https.length);
    } else if (current.startsWith(http) || current.startsWith(https)) {
      updated = current; // already matches
    } else {
      updated = (value ? https : http) + current;
    }

    setState(() {
      _useHttps = value;
      _addressController.text = updated;
      _addressController.selection =
          TextSelection.collapsed(offset: updated.length);
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
      _useHttps = address.startsWith('https://');
    });
    _addressFocusNode.unfocus();
  }

  Future<void> _continue([String? overrideAddress]) async {
    final input = overrideAddress ?? _addressController.text.trim();

    if (input.isEmpty || input == 'http://' || input == 'https://') {
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
        onTap: () => FocusScope.of(context).unfocus(),
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
                      child: Image.asset('assets/alignsysnew.png', height: 85),
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
                        // ── Scheme toggle ──
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceLight,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: _buildSchemeOption(
                                  label: 'HTTPS',
                                  icon: Icons.lock_rounded,
                                  selected: _useHttps,
                                  onTap: () => _setUseHttps(true),
                                ),
                              ),
                              Expanded(
                                child: _buildSchemeOption(
                                  label: 'HTTP',
                                  icon: Icons.lock_open_rounded,
                                  selected: !_useHttps,
                                  onTap: () => _setUseHttps(false),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (!_useHttps) ...[
                          const SizedBox(height: 8),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.info_outline_rounded,
                                  size: 14, color: Colors.orange.shade700),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'HTTP is unencrypted — only use this on a trusted local or on-prem network.',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: Colors.orange.shade800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 12),

                        TextField(
                          controller: _addressController,
                          focusNode: _addressFocusNode,
                          keyboardType: TextInputType.url,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _continue(),
                          decoration: InputDecoration(
                            labelText: 'Server address',
                            hintText: '192.168.2.100 or alignsys.tech',
                            prefixIcon: const Icon(Icons.dns_outlined,
                                color: AppColors.primary),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12)),
                            errorText: _error,
                            filled: true,
                            fillColor: AppColors.surfaceLight,
                          ),
                        ),

                        // ── RECENT ADDRESSES DROPDOWN ──
                        // Lives inside the same card, directly under the
                        // field, and only appears while the field has
                        // focus — collapses the moment focus is lost or
                        // an entry is picked.
                        AnimatedSize(
                          duration: const Duration(milliseconds: 150),
                          curve: Curves.easeOut,
                          alignment: Alignment.topCenter,
                          child: (_showRecent && _recentAddresses.isNotEmpty)
                              ? ExcludeFocus(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      const SizedBox(height: 8),
                                      Container(
                                        constraints: const BoxConstraints(
                                            maxHeight: 168),
                                        decoration: BoxDecoration(
                                          color: AppColors.surfaceLight,
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          border: Border.all(
                                              color: Colors.grey.shade200),
                                        ),
                                        child: ListView.separated(
                                          shrinkWrap: true,
                                          padding: EdgeInsets.zero,
                                          itemCount: _recentAddresses.length,
                                          separatorBuilder: (_, __) =>
                                              Divider(
                                            height: 1,
                                            color: Colors.grey.shade200,
                                          ),
                                          itemBuilder: (context, i) =>
                                              ListTile(
                                            dense: true,
                                            contentPadding: const EdgeInsets
                                                .only(left: 12, right: 4),
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
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            trailing: IconButton(
                                              icon: Icon(
                                                Icons.close,
                                                size: 15,
                                                color: Colors.grey.shade400,
                                              ),
                                              padding: EdgeInsets.zero,
                                              constraints:
                                                  const BoxConstraints(
                                                minWidth: 28,
                                                minHeight: 28,
                                              ),
                                              splashRadius: 16,
                                              onPressed: () => _removeRecent(
                                                  _recentAddresses[i]),
                                            ),
                                            onTap: _loading
                                                ? null
                                                : () => _selectRecentAddress(
                                                    _recentAddresses[i]),
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
                            ? const Center(child: CircularProgressIndicator())
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Builds one of the two scheme toggle buttons (HTTPS or HTTP).
  Widget _buildSchemeOption({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 15,
                color: selected ? Colors.white : Colors.grey.shade600),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}