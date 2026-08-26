# Firestore 보안 규칙 테스트 (EWOS-29)

`firestore.rules`의 역할 격리·위조 방지·비활성 거래처 차단을 에뮬레이터로 검증한다.

## 사전 요건
- Node 18+
- Java 11+ (Firestore 에뮬레이터 실행용). Android Studio 번들 JDK로도 됨:
  `JAVA_HOME` 미설정 시 `set JAVA_HOME="C:\Program Files\Android\Android Studio\jbr"`
- firebase-tools (`npm i -g firebase-tools`)

## 실행
```bash
cd firestore-tests
npm install           # 최초 1회
npm test              # 에뮬레이터 기동 → 규칙 테스트 → 종료
```
`npm test`는 리포지토리 루트에서 `firebase emulators:exec`를 돌린다(루트의 `firebase.json`·`firestore.rules` 사용).

## 커버리지 (완료 기준 체크리스트)
1. 거래처 A → 거래처 B 주문 조회 거부 / 자기 주문 허용
2. 거래처의 주문 status 변경은 '취소'만 허용, 그 외 거부 / 운영자는 허용
3. 타 partnerId 주문 생성 거부 / 자기 정상 주문 허용
4. items 비어있음·음수 금액 등 조작 주문 거부
5. users.role·partnerId 수정 거부 / fcmTokens 갱신 허용
6. secrets(카페24 토큰) 컬렉션 클라이언트 접근 전면 거부
7. 비활성(active=false) 거래처의 자기 데이터 접근 거부 (자기 partners 문서 read는 허용)
