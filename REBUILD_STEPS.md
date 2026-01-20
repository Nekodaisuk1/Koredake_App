# クリーンビルド手順

デバッグログが表示されない場合、以下の手順でクリーンビルドしてください：

## 方法1: Xcode UI から

1. Xcode のメニューバーで **Product** → **Clean Build Folder** をクリック
2. または **Shift + Command + K** を押す
3. 再度 **Command + R** でビルド＆実行

## 方法2: ターミナルから

```bash
cd /Users/tanna.iori/Desktop/Koredake_v3/Koredake
rm -rf ~/Library/Developer/Xcode/DerivedData/*
```

その後、Xcodeでビルドし直す

## 期待されるログ

編集画面を開いたとき（「編集」ボタンをタップ）:

```
📝 RouteDetailView: 編集ボタンタップ - segment: めし処萬やまびこ -> 神山...
🔄 RouteDetailView: showingEdit変更 - true, segment: めし処萬やまびこ -> 神山...
🟡 AddRouteView.init - 編集モード: めし処萬やまびこ -> 神山...
🟡 AddRouteView.init - 座標設定: from=true, to=true
🗺️ AddRouteView: MapPreview表示 - from: true, to: true
[MapPreview] body onAppear - taskKey: ...
[RoutePreviewMapView] makeUIView呼び出し
[MapPreview] mapKitPreview onAppear - from: true, to: true, route: false
[MapPreview] task開始 - taskKey: ...
[MapPreview] loadDetail開始 - from: XX.XXX, YY.YYY, to: XX.XXX, YY.YYY, mode: bike, showWeatherPoints: false
```

## トラブルシューティング

### ログが全く出ない場合
- シミュレーターを再起動
- Xcodeを再起動
- DerivedDataを削除

### コンパイルエラーが出る場合
- 構文エラーを修正
- Swift Packageの再解決（File → Packages → Reset Package Caches）
