/// Route names. Kept as plain strings so deep links and GetX agree.
abstract final class AppRoutes {
  static const String splash = '/';
  static const String onboarding = '/onboarding';
  static const String home = '/home';
  static const String search = '/search';
  static const String collections = '/collections';
  static const String settings = '/settings';
  static const String capture = '/capture';

  static String memory(String id) => '/memory/$id';

  /// Must match the registered `/collections/:id` page; a singular path here
  /// would fall through to no route at all.
  static String collection(String id) => '/collections/$id';
  static const String models = '/settings/models';
  static const String cloud = '/settings/cloud';
}
