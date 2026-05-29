// 探偵ロールのレジストリ。ロールの追加・差し替えはここと lib/roles/*.dart だけで完結する。
import 'role.dart';
import 'hardboiled.dart';
import 'novice.dart';
import 'alien.dart';
import 'psychologist.dart';

export 'role.dart';

// 選択キー → Role 定義。設定画面の一覧もこの順序・内容を参照する。
const Map<String, Role> kRoles = {
  'hardboiled': hardboiledRole,
  'novice': noviceRole,
  'alien': alienRole,
  'psychologist': psychologistRole,
};

// 未知のキー・null のときに使うデフォルトロール。
const String kDefaultRoleKey = 'hardboiled';

// 選択キーから Role を引く。未定義ならデフォルトロールを返す。
Role roleFor(String? key) => kRoles[key] ?? kRoles[kDefaultRoleKey]!;
