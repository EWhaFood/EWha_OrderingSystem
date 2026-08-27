import {onCall, HttpsError, CallableRequest} from "firebase-functions/v2/https";
import {getFirestore} from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";

/**
 * 일반 사용자(B2C) 프로비저닝 (EWOS-53). 구글 최초 로그인 직후 호출한다.
 * users/{uid} 문서가 없으면 role='customer'로 생성한다(멱등). role은 서버만 설정한다.
 * 이미 문서가 있으면(운영자·거래처·기존 customer) 그대로 두고 role만 돌려준다.
 */
export const provisionCustomer = onCall(async (req: CallableRequest) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");

  const db = getFirestore();
  const ref = db.collection("users").doc(uid);
  const snap = await ref.get();
  if (snap.exists) {
    return {role: (snap.data()?.role ?? "customer") as string, created: false};
  }

  const email = (req.auth?.token?.email ?? "") as string;
  await ref.set({role: "customer", email, fcmTokens: []});
  logger.info("일반 사용자 프로비저닝", {uid, email});
  return {role: "customer", created: true};
});
