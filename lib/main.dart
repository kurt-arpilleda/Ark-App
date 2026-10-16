import 'package:flutter/material.dart';
import 'webview.dart';
import 'api_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ApiService.setupHttpOverrides();
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Ark App',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: SoftwareWebViewScreen(linkID: 43),
    );
  }
}