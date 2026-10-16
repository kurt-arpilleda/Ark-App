import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'api_service.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'auto_update.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:mime/mime.dart';
import 'package:permission_handler/permission_handler.dart';

class SoftwareWebViewScreen extends StatefulWidget {
  final int linkID;

  SoftwareWebViewScreen({required this.linkID});

  @override
  _SoftwareWebViewScreenState createState() => _SoftwareWebViewScreenState();
}

class _SoftwareWebViewScreenState extends State<SoftwareWebViewScreen> with WidgetsBindingObserver {
  final ApiService apiService = ApiService();

  InAppWebViewController? webViewController;
  PullToRefreshController? pullToRefreshController;
  bool _isNavigating = false;
  Timer? _debounceTimer;
  String? _webUrl;
  bool _isLoading = true;
  double _progress = 0;
  bool _isDownloadDialogShowing = false;

  // Hides the "Install App Version" navbar inside the webview.
  // Runs at document start (no flash) and keeps watching for the navbar
  // in case the page adds it later.
  static const String _hideNavbarScript = """
(function() {
  var css = 'nav.navbar:has(.installBtn), nav.navbar:has(a[href*="arkApp.apk"]) { display: none !important; }';
  function addStyle() {
    if (document.getElementById('__hide_install_navbar_style')) return;
    var style = document.createElement('style');
    style.id = '__hide_install_navbar_style';
    style.textContent = css;
    (document.head || document.documentElement).appendChild(style);
  }

  function hideNavbar() {
    addStyle();
    var navs = document.querySelectorAll('nav.navbar');
    navs.forEach(function(nav) {
      if (nav.querySelector('.installBtn') || nav.querySelector('a[href*="arkApp.apk"]')) {
        nav.style.setProperty('display', 'none', 'important');
      }
    });
  }

  hideNavbar();

  var navObserver = new MutationObserver(function() {
    hideNavbar();
  });
  navObserver.observe(document.documentElement, { childList: true, subtree: true });
})();
""";

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _initializePullToRefresh();
    _fetchAndLoadUrl();
    _checkForUpdates();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    webViewController?.stopLoading();
    pullToRefreshController?.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!AutoUpdate.isUpdating) {
        _checkForUpdates();
      }
    }
  }

  void _initializePullToRefresh() {
    pullToRefreshController = PullToRefreshController(
      settings: PullToRefreshSettings(
        color: Colors.blue,
      ),
      onRefresh: () async {
        if (webViewController != null) {
          _fetchAndLoadUrl();
        }
      },
    );
  }

  Future<void> _checkForUpdates() async {
    try {
      await AutoUpdate.checkForUpdate(context);
    } catch (e) {
      debugPrint('Update check failed: $e');
    }
  }

  Future<void> _fetchAndLoadUrl() async {
    try {
      String url = await apiService.fetchSoftwareLink(widget.linkID);
      if (mounted) {
        setState(() {
          _webUrl = url;
          _isLoading = true;
        });
        if (webViewController != null) {
          await webViewController!.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
        }
      }
    } catch (e) {
      debugPrint("Error fetching link: $e");
    }
  }

  Future<bool> _onWillPop() async {
    if (webViewController != null && await webViewController!.canGoBack()) {
      webViewController!.goBack();
      return false;
    } else {
      return true;
    }
  }

  bool _isPdfUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;

    if (url.toLowerCase().endsWith('.pdf')) {
      return true;
    }

    final mimeType = lookupMimeType(url);
    if (mimeType == 'application/pdf') {
      return true;
    }

    if (uri.pathSegments.isNotEmpty && uri.pathSegments.last.toLowerCase().contains('pdf')) {
      return true;
    }

    return false;
  }

  Future<void> _launchInBrowser(String url) async {
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } else {
      Fluttertoast.showToast(
        msg: "Could not launch browser",
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
    }
  }

  void _showDownloadDialog(String url, bool isPdf) {
    SystemChannels.textInput.invokeMethod('TextInput.hide');
    if (_isDownloadDialogShowing) return;

    _isDownloadDialogShowing = true;

    final uri = Uri.parse(url);
    String fileName = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '';

    if (fileName.isEmpty || fileName.length > 50) {
      fileName = isPdf
          ? 'document_${DateTime.now().millisecondsSinceEpoch}.pdf'
          : 'file_${DateTime.now().millisecondsSinceEpoch}';
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: EdgeInsets.all(20),
        height: MediaQuery.of(context).size.height * 0.35,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            SizedBox(height: 20),
            Text(
              'Download',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 15),
            Text(
              'File name:',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
            SizedBox(height: 8),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[300]!),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                fileName,
                style: TextStyle(fontSize: 16),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Spacer(),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      'Cancel',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ),
                SizedBox(width: 15),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      Navigator.pop(context);
                      await _launchInBrowser(url);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      padding: EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      isPdf ? 'View' : 'Download',
                      style: TextStyle(fontSize: 16, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ).then((_) {
      _isDownloadDialogShowing = false;
    });
  }

  bool _isDownloadableUrl(String url) {
    final mimeType = lookupMimeType(url);
    if (mimeType == null) return false;

    const downloadableExtensions = [
      'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx',
      'zip', 'rar', '7z', 'tar', 'gz',
      'apk', 'exe', 'dmg', 'pkg',
      'jpg', 'jpeg', 'png', 'gif', 'bmp',
      'mp3', 'wav', 'ogg',
      'mp4', 'avi', 'mov', 'mkv',
      'txt', 'csv', 'json', 'xml'
    ];

    return downloadableExtensions.any((ext) => url.toLowerCase().contains('.$ext'));
  }

  Future<void> _debounceNavigation(String url) async {
    if (_isNavigating) return;

    _debounceTimer?.cancel();

    setState(() {
      _isNavigating = true;
    });

    _debounceTimer = Timer(Duration(milliseconds: 500), () async {
      try {
        await webViewController?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
      } catch (e) {
        debugPrint("Navigation error: $e");
      } finally {
        if (mounted) {
          setState(() {
            _isNavigating = false;
          });
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        body: SafeArea(
          child: Stack(
            children: [
              if (_webUrl != null)
                InAppWebView(
                  initialUrlRequest: URLRequest(url: WebUri(_webUrl!)),
                  initialUserScripts: UnmodifiableListView<UserScript>([
                    UserScript(
                      source: _hideNavbarScript,
                      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                    ),
                  ]),
                  initialSettings: InAppWebViewSettings(
                    mediaPlaybackRequiresUserGesture: false,
                    javaScriptEnabled: true,
                    useHybridComposition: true,
                    allowsInlineMediaPlayback: true,
                    allowContentAccess: true,
                    allowFileAccess: true,
                    cacheEnabled: true,
                    javaScriptCanOpenWindowsAutomatically: true,
                    allowUniversalAccessFromFileURLs: true,
                    allowFileAccessFromFileURLs: true,
                    useOnDownloadStart: true,
                    transparentBackground: true,
                    thirdPartyCookiesEnabled: true,
                    domStorageEnabled: true,
                    databaseEnabled: true,
                    hardwareAcceleration: true,
                    supportMultipleWindows: false,
                    useWideViewPort: true,
                    loadWithOverviewMode: true,
                    mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
                    verticalScrollBarEnabled: false,
                    horizontalScrollBarEnabled: false,
                    overScrollMode: OverScrollMode.NEVER,
                    forceDark: ForceDark.OFF,
                    forceDarkStrategy: ForceDarkStrategy.WEB_THEME_DARKENING_ONLY,
                    saveFormData: true,
                    userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/110.0.0.0 Safari/537.36",
                  ),
                  pullToRefreshController: pullToRefreshController,
                  onWebViewCreated: (controller) {
                    webViewController = controller;
                  },
                  onLoadStart: (controller, url) {
                    setState(() {
                      _isLoading = true;
                      _progress = 0;
                    });
                  },
                  onLoadStop: (controller, url) async {
                    pullToRefreshController?.endRefreshing();
                    setState(() {
                      _isLoading = false;
                      _progress = 1;
                    });

                    // Re-apply navbar hiding once the page is fully loaded (safety net).
                    try {
                      await controller.evaluateJavascript(source: _hideNavbarScript);
                    } catch (e) {
                      debugPrint("Error hiding navbar: $e");
                    }

                    String scrollScript = """
  function makeDialogScrollable() {
    const dialog = document.querySelector('.tbox');
    if (dialog) {
      const rect = dialog.getBoundingClientRect();
      const isOffScreen = rect.left < 0 || rect.top < 0 || 
                         rect.right > window.innerWidth || 
                         rect.bottom > window.innerHeight;
      
      if (isOffScreen) {
        const tinner = dialog.querySelector('.tinner');
        if (tinner) {
          tinner.style.overflow = 'auto';
          tinner.style.maxHeight = '80vh';
          tinner.style.maxWidth = '90vw';
        }
        
        const tcontent = dialog.querySelector('.tcontent');
        if (tcontent) {
          tcontent.style.overflow = 'auto';
          tcontent.style.maxHeight = '70vh';
        }
      }
    }
  }
  
  makeDialogScrollable();
  
  const observer = new MutationObserver(function(mutations) {
    makeDialogScrollable();
  });
  
  observer.observe(document.body, {
    childList: true,
    subtree: true,
    attributes: true
  });
  """;

                    try {
                      await controller.evaluateJavascript(source: scrollScript);
                    } catch (e) {
                      debugPrint("Error making dialog scrollable: $e");
                    }
                  },
                  onProgressChanged: (controller, progress) {
                    setState(() {
                      _progress = progress / 100;
                    });
                  },
                  onReceivedServerTrustAuthRequest: (controller, challenge) async {
                    return ServerTrustAuthResponse(action: ServerTrustAuthResponseAction.PROCEED);
                  },
                  onPermissionRequest: (controller, request) async {
                    List<Permission> permissionsToRequest = [];

                    if (request.resources.contains(PermissionResourceType.CAMERA)) {
                      permissionsToRequest.add(Permission.camera);
                    }
                    if (request.resources.contains(PermissionResourceType.MICROPHONE)) {
                      permissionsToRequest.add(Permission.microphone);
                    }

                    Map<Permission, PermissionStatus> statuses = await permissionsToRequest.request();
                    bool allGranted = statuses.values.every((status) => status.isGranted);

                    return PermissionResponse(
                      resources: request.resources,
                      action: allGranted ? PermissionResponseAction.GRANT : PermissionResponseAction.DENY,
                    );
                  },
                  shouldOverrideUrlLoading: (controller, navigationAction) async {
                    final url = navigationAction.request.url?.toString() ?? '';
                    final isPdf = _isPdfUrl(url);
                    if (_isDownloadableUrl(url)) {
                      await _launchInBrowser(url);
                      return NavigationActionPolicy.CANCEL;
                    }
                    if (isPdf || lookupMimeType(url) != null) {
                      _showDownloadDialog(url, isPdf);
                      return NavigationActionPolicy.CANCEL;
                    }

                    _debounceNavigation(url);
                    return NavigationActionPolicy.CANCEL;
                  },
                  onDownloadStartRequest: (controller, downloadStartRequest) async {
                    final url = downloadStartRequest.url.toString();
                    final isPdf = _isPdfUrl(url);
                    _showDownloadDialog(url, isPdf);
                  },
                ),
              if (_isLoading)
                LinearProgressIndicator(
                  value: _progress,
                  backgroundColor: Colors.grey[300],
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                ),
            ],
          ),
        ),
      ),
    );
  }
}