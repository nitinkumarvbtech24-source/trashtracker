import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:dio_cache_interceptor_hive_store/dio_cache_interceptor_hive_store.dart';

class MapCacheService {
  static late CacheStore store;

  static Future<void> init() async {
    if (kIsWeb) {
      store = MemCacheStore();
      return;
    }
    
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/map_tiles_cache';
    store = HiveCacheStore(path);
  }
}
