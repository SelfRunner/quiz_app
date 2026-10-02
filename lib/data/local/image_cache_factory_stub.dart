import 'dart:typed_data';

import 'package:hive_ce/hive_ce.dart';

import 'image_cache.dart';

LocalImageCache createPlatformImageCache(Box<Uint8List> webBox) =>
    HiveImageCache(webBox);
