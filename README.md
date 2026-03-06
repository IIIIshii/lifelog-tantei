flutter + firebase
書き方わからないので適当

# デバッグ
## VS Codeから行う場合
・右下のバーからエミュレータデバイスを選択
・lib/main.dart ファイルを開いた状態で、キーボードの F5 キーを押す
    ・メニューからRun → Start Debugging でもいける

## Android Studioから行う場合

# Issue管理
・まずIssueを立ててからパッチする
・Issueに取り組む場合はassigneeに自分を追加するように注意

# 注意点
・pubspec.yamlで必要なパッケージ(?)とかを追加したあとは、必ずターミナルで
flutter get pub
を叩くこと

・.envにキーを入れる