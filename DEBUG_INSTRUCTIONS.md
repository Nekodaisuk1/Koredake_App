# MapPreview ポリライン・ピン表示不具合 修正指示

## 📋 現象
追加済みルートの編集画面でMapPreviewを表示した際、以下の問題が発生しています：
- ✅ 地図自体は表示される
- ✅ 表示範囲は正しく設定される（fromPlace/toPlace周辺）
- ❌ **ルートのポリライン（青い線）が表示されない**
- ❌ **出発地・到着地のピン（マーカー）が表示されない**

## 🔍 推定される原因
1. **ルート取得の失敗**
   - `MapKitRouteProvider.routes()` がエラーまたは空配列を返している
   - ネットワークエラー、タイムアウト、無効な座標など

2. **非同期処理のタイミング問題**
   - `.task(id: taskKey)` が正しく実行されていない
   - `onAppear`での座標設定とMapPreview初期化のタイミングのズレ

3. **MapKit Delegateの問題**
   - `rendererFor overlay` が呼ばれていない
   - `viewFor annotation` が呼ばれていない
   - Coordinatorの設定に問題がある

4. **座標データの問題**
   - `fromLatLng` / `toLatLng` がnilまたは無効な値
   - AddRouteViewの`onAppear`で正しく設定されていない

## 🐛 デバッグ手順

### 1. アプリを実行してログを確認
デバッグコードを追加済みなので、Xcodeのコンソールで以下のログを確認してください：

```
[MapPreview] loadDetail開始 - from: X.XXX, Y.YYY, to: X.XXX, Y.YYY, mode: bike, showWeatherPoints: false
[MapPreview] ルート取得完了 - 件数: N
[MapPreview] ルート設定成功 - ポイント数: XXX, 距離: XXXXm
[MapPreview] buildAnnotations - 基本アノテーション数: 2
[MapPreview] updateMap呼び出し - annotations: 2, route: true
[MapPreview] アノテーション追加: めし処萬やまびこ at (XX.XXX, XX.XXX)
[MapPreview] アノテーション追加: 神山... at (XX.XXX, XX.XXX)
[MapPreview] ルートオーバーレイ追加 - ポイント数: XXX
[MapPreview] 地図の表示領域をルートに合わせて設定
[MapPreview.Coordinator] rendererFor overlay呼び出し
[MapPreview.Coordinator] ポリラインレンダラー作成 - ポイント数: XXX
[MapPreview.Coordinator] viewFor annotation呼び出し: RoutePreviewMKAnnotation
[MapPreview.Coordinator] スタートマーカー作成: めし処萬やまびこ
[MapPreview.Coordinator] viewFor annotation呼び出し: RoutePreviewMKAnnotation
[MapPreview.Coordinator] ゴールマーカー作成: 神山...
```

### 2. ケース別の診断

#### Case A: `loadDetail開始`ログが出ない
→ `.task(id: taskKey)` が実行されていない
**修正箇所**: `AddRouteView.swift`
- `onAppear`で座標を設定した後、MapPreviewが再生成されているか確認
- `fromLatLng`と`toLatLng`が正しく`@State`として管理されているか確認

#### Case B: `座標がnil`ログが出る
→ fromPlace/toPlaceがnilのまま
**修正箇所**: `AddRouteView.swift` の`onAppear`
```swift
fromLatLng = segment.latLngFrom
toLatLng = segment.latLngTo
```
この部分で、`segment.latLngFrom`と`segment.latLngTo`の値を確認

#### Case C: `ルート取得完了 - 件数: 0`
→ MapKitがルートを返していない
**原因**:
- 座標が無効（例: 海上、ルート不可能な地点）
- MapKitがその移動手段でルートを見つけられない
- 距離が遠すぎる

**確認事項**:
- 座標が日本国内の有効な地点か
- `mode`（walk/bike/trainなど）が適切か
- `MapKitRouteProvider.swift`の`transportType`設定が正しいか

#### Case D: `エラー発生: ...`ログが出る
→ 例外が発生している
**対処**:
- エラーメッセージの内容を確認
- ネットワーク接続を確認
- MapKitのAPIキー・権限を確認

#### Case E: `updateMap呼び出し - annotations: 0, route: false`
→ データは取得できているが、渡されていない
**修正箇所**: `MapPreview.swift`の`mapKitPreview`
```swift
RoutePreviewMapView(
    fromPlace: fromPlace,
    toPlace: toPlace,
    fromName: fromName,
    toName: toName,
    route: detail?.route ?? route,  // ← この値を確認
    annotations: buildAnnotations()  // ← この値を確認
)
```

#### Case F: updateMapまでは正常だが、Coordinatorのログが出ない
→ MapKitのdelegateが正しく設定されていない
**修正箇所**: `RoutePreviewMapView.makeUIView`
```swift
mapView.delegate = context.coordinator  // ← この設定を確認
```

## 🔧 想定される修正内容

### 修正案1: ルート取得のリトライ処理追加
```swift
private func loadDetail() async {
    // ... 既存のコード
    
    do {
        if showWeatherPoints {
            // ...
        } else {
            var routes: [MKRoute] = []
            var retryCount = 0
            let maxRetries = 3
            
            while routes.isEmpty && retryCount < maxRetries {
                routes = try await routeProvider.routes(
                    from: CLLocationCoordinate2D(latitude: from.latitude, longitude: from.longitude),
                    to: CLLocationCoordinate2D(latitude: to.latitude, longitude: to.longitude),
                    mode: mode
                )
                
                if routes.isEmpty {
                    retryCount += 1
                    try await Task.sleep(nanoseconds: 500_000_000) // 0.5秒待機
                }
            }
            
            detail = nil
            route = routes.first
            if route == nil {
                errorMessage = "ルート情報取得不可（\(retryCount)回試行）"
            }
        }
    }
    // ...
}
```

### 修正案2: エラー表示の改善
現状、エラーメッセージが小さくて見えにくい可能性があります。

```swift
.overlay(alignment: .bottom) {  // bottomLeading → bottom
    if let errorMessage {
        VStack {
            Text("⚠️ マップエラー")
                .font(.headline)
                .foregroundColor(.white)
            Text(errorMessage)
                .font(.caption)
                .foregroundColor(.white)
        }
        .padding()
        .frame(maxWidth: .infinity)  // 幅いっぱいに表示
        .background(Color.red.opacity(0.8))  // 赤背景で目立たせる
        .cornerRadius(8)
        .padding(8)
    }
}
```

### 修正案3: fallback表示の追加
ルートが取得できない場合、直線で表示する：

```swift
private func updateMap(_ mapView: MKMapView) {
    // ... 既存のコード
    
    if let route {
        // 既存のルート表示
    } else if let from = fromPlace, let to = toPlace {
        // ルートが取得できない場合は直線で表示
        let coordinates = [
            CLLocationCoordinate2D(latitude: from.latitude, longitude: from.longitude),
            CLLocationCoordinate2D(latitude: to.latitude, longitude: to.longitude)
        ]
        let polyline = MKPolyline(coordinates: coordinates, count: 2)
        mapView.addOverlay(polyline)
        
        let rect = polyline.boundingMapRect
        mapView.setVisibleMapRect(rect, edgePadding: UIEdgeInsets(top: 40, left: 40, bottom: 40, right: 40), animated: false)
    } else {
        updateRegionFallback(mapView)
    }
}
```

### 修正案4: AddRouteViewでの初期化改善
座標設定のタイミングを早める：

```swift
init(store: SegmentStore, editingSegment: Segment? = nil) {
    self.store = store
    self.editingSegment = editingSegment
    
    // onAppearより前に設定
    if let segment = editingSegment {
        _fromLatLng = State(initialValue: segment.latLngFrom)
        _toLatLng = State(initialValue: segment.latLngTo)
        _fromPlace = State(initialValue: segment.fromPlace)
        _toPlace = State(initialValue: segment.toPlace)
        _mode = State(initialValue: segment.mode)
        // ... その他の初期値
    }
}
```

## ✅ 修正完了の確認方法
1. アプリを実行
2. 既存のルートを編集
3. 地図プレビューで以下が表示されることを確認：
   - ✅ 青いポリライン（ルート）
   - ✅ 青いピン（S）：出発地
   - ✅ 赤いピン（G）：到着地
4. コンソールログにエラーがないことを確認

## 📝 次のステップ
1. まず上記のデバッグ手順でログを確認
2. ケース別診断で原因を特定
3. 該当する修正案を適用
4. 動作確認
5. デバッグログを本番ビルドでは削除（またはDEBUGフラグで制御）

## 🚨 緊急対応が必要な場合
上記の修正が複雑な場合、暫定対応として：
- エラーメッセージを大きく表示
- ルート取得失敗時は直線表示（修正案3）
- 最低限、ピンだけでも表示されるようにする

---
作成日: 2026年1月20日
対象ファイル: 
- `UI/MapPreview.swift`
- `UI/AddRouteView.swift`
- `Services/RouteRiskEvaluator.swift` (MapKitRouteProvider)
