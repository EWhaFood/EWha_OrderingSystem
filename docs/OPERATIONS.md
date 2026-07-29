# 운영 가이드

## 운영자 계정 만들기

앱에는 운영자 가입 화면이 없다. 거래처는 초대 코드로 스스로 가입하지만(`redeemInvite`),
운영자 계정은 권한 상승이라 앱에 노출하지 않고 아래 방법으로 만든다.

### 방법 A — 스크립트 (권장)

서비스 계정 키가 필요하다. Firebase 콘솔 → 프로젝트 설정 → 서비스 계정 →
새 비공개 키 생성으로 JSON을 받는다. **이 키는 커밋하지 않는다.**

```bash
cd functions

# Windows (PowerShell)
$env:GOOGLE_APPLICATION_CREDENTIALS="C:\path\serviceAccountKey.json"
# macOS/Linux
export GOOGLE_APPLICATION_CREDENTIALS=/path/serviceAccountKey.json

# 기존 계정을 운영자로 승격
node scripts/set-operator.js admin@efc.co.kr

# 새 계정을 만들며 운영자로 지정 (비밀번호 6자 이상)
node scripts/set-operator.js staff@efc.co.kr <password>
```

스크립트는 `users/{uid}` 문서에 `role: 'operator'`를 설정한다(merge라 기존 값 보존).
`fcmTokens`는 해당 계정이 앱에 처음 로그인할 때 자동 생성된다.

### 방법 B — Firebase 콘솔 수동

1. Authentication → 사용자 → 사용자 추가 (이메일/비밀번호)
2. 생성된 사용자의 UID 복사
3. Firestore → `users` 컬렉션 → 문서 ID = 그 UID 로 문서 생성:
   ```
   role: "operator"   (string)
   email: "admin@efc.co.kr"  (string)
   ```
   `partnerId`는 넣지 않는다(운영자는 특정 거래처에 묶이지 않는다).

## 검증

두 역할이 각자 홈으로 분기하는지 확인한다.

- 운영자 로그인 → 발주 현황 화면(상단에 상품/거래처 관리 진입점)
- 거래처 로그인 → 발주 등록 / 내역 / 설정 탭

`users.role` 값에 따라 [app.dart](../lib/app.dart)의 `AuthGate`가 분기한다.
