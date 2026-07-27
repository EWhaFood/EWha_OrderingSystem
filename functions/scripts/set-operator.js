/**
 * 운영자 계정 부트스트랩 스크립트 (Admin SDK, 로컬 실행 전용).
 *
 * 앱에는 운영자 가입 경로가 없다(redeemInvite는 거래처만 만든다). 첫 운영자와
 * 직원 운영자는 이 스크립트로 만든다. 서비스 계정 권한이 필요하므로 런타임(Functions)이
 * 아니라 개발자가 로컬에서 1회성으로 돌린다 — 권한 상승 API를 앱에 노출하지 않기 위함.
 *
 * 사용법:
 *   # 서비스 계정 키 경로 지정(둘 중 하나)
 *   set GOOGLE_APPLICATION_CREDENTIALS=C:\path\serviceAccountKey.json   (Windows)
 *   export GOOGLE_APPLICATION_CREDENTIALS=/path/serviceAccountKey.json  (bash)
 *
 *   # 기존 계정을 운영자로 승격
 *   node scripts/set-operator.js admin@efc.co.kr
 *
 *   # 새 계정을 만들며 운영자로 지정(비밀번호 6자 이상)
 *   node scripts/set-operator.js admin@efc.co.kr <password>
 */

const admin = require("firebase-admin");

async function main() {
  const email = process.argv[2];
  const password = process.argv[3];
  if (!email) {
    console.error("사용법: node scripts/set-operator.js <email> [password]");
    process.exit(1);
  }

  // GOOGLE_APPLICATION_CREDENTIALS(또는 functions/serviceAccountKey.json)로 인증한다.
  admin.initializeApp();

  const auth = admin.auth();
  const db = admin.firestore();

  let user;
  try {
    user = await auth.getUserByEmail(email);
    console.log(`기존 계정 사용: ${email} (${user.uid})`);
  } catch (e) {
    if (e.code !== "auth/user-not-found") throw e;
    if (!password) {
      console.error(`계정이 없습니다. 새로 만들려면 비밀번호를 함께 주세요: ${email} <password>`);
      process.exit(1);
    }
    user = await auth.createUser({email, password});
    console.log(`새 계정 생성: ${email} (${user.uid})`);
  }

  // role만 확정하고 나머지는 보존한다(merge). partnerId는 두지 않는다(운영자).
  // fcmTokens는 앱 첫 로그인 시 자동 생성되므로 여기서 만들지 않는다.
  await db.collection("users").doc(user.uid).set(
    {
      role: "operator",
      email,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    {merge: true},
  );
  console.log(`✅ 운영자로 설정 완료: ${email}`);
  process.exit(0);
}

main().catch((e) => {
  console.error("실패:", e);
  process.exit(1);
});
