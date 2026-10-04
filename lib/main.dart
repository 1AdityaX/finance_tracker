import 'package:flutter/material.dart';

import 'theme.dart';

void main() => runApp(
  MaterialApp(
    title: 'Between',
    theme: buildTheme(Brightness.light),
    darkTheme: buildTheme(Brightness.dark),
    home: const Scaffold(body: Center(child: Text('between'))),
  ),
);
