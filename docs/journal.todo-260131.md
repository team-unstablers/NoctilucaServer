# Journal & TODOs - 2026. 01. 31 (Sat)

## 💭 Thoughts & Reflections
- **Survival in the AI Era**: 대기업의 부품화된 개발자가 아닌, 밑바닥부터 훑을 수 있는 "Wild" 풀스택 개발자(Geek)로서의 정체성 확인.
- **GDD (감-Driven Development)**: AI가 흉내 낼 수 없는 직관과 경험의 가치.
- **SwiftUI vs UIKit**: SwiftUI는 아직 시스템 깊은 곳을 건드리기엔 부족함. UIKit("흑마법")과 적절히 섞어 쓰는 것이 현실적이고 영리한 생존 전략임을 인정하기.

## 🛠️ Refactoring Tasks

### 1. `RootViewController` 다이어트 (Priority: High)
- **목표**: `RootViewController`가 뷰모델 생성까지 담당하는 "짬통" 역할에서 벗어나기.
- **방법**: 의존성 주입(DI) 패턴 적용.
    - `MobileUIMainSceneDelegate`에서 `MobileUIMainViewModel`, `MainWindowViewModel` 생성.
    - `RootViewController` 초기화 시 주입(`init(viewModel:...)`) 받도록 변경.

### 2. Naming Cleanup (Priority: Medium)
Xcode 리팩토링 기능 한계로 방치된 "구린 네이밍" 청산.

| 기존 이름 (Old) | 변경할 이름 (New) | 비고 |
| :--- | :--- | :--- |
| `MainWindowMainPhaseContentView` | **`RemoteSessionView`** | 원격 제어 메인 화면 |
| `MainWindowConnectingPhaseContentView` | **`ConnectingSessionView`** | 연결 중 화면 |
| `MainWindowNewConnectionPhaseContentView` | **`NewConnectionView`** | 새 연결/연락처 목록 |
| `MobileUIMainViewModel` | **`AppNavigationViewModel`** | 앱 전체 네비게이션 관리 |
| `MobileUIMainView` | **`AppRootView`** | 최상위 뷰 |

## 📝 Notes
- 작업 순서: `RootViewController` DI 리팩토링 → 파일/심볼 리네임 순으로 진행 추천.
- 멘탈 관리: 억지로 SwiftUI만 고집하다 스트레스 받지 말고, 필요하면 언제든 UIKit/AppKit 카드를 꺼내 들 것.
