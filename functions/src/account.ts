import {onCall, HttpsError, CallableRequest} from "firebase-functions/v2/https";
import {getFirestore, FieldValue} from "firebase-admin/firestore";
import {getAuth} from "firebase-admin/auth";
import * as logger from "firebase-functions/logger";

const REAUTH_MAX_AGE_SEC = 5 * 60; // 재인증 유효 시간 5분

/** 초대코드 문서에 남은 이메일(가입 시 usedEmail로 저장)을 제거해 PII 잔존을 없앤다. */
async function purgeEmailFromInvites(email: string): Promise<void> {
  if (!email) return;
  const db = getFirestore();
  const snap = await db.collection("inviteCodes")
    .where("usedEmail", "==", email).get();
  if (snap.empty) return;
  const batch = db.batch();
  for (const doc of snap.docs) {
    batch.update(doc.ref, {usedEmail: FieldValue.delete()});
  }
  await batch.commit();
}

/**
 * 계정 삭제(탈퇴) — 호출자 본인 계정만 삭제한다 (EWOS-40).
 *
 * 개인식별정보(users 문서: email·fcmTokens, inviteCodes.usedEmail)와 Auth 계정을
 * 제거한다. 발주 이력(orders)은 거래처(partnerId) 단위 감사 기록이며 개인식별정보를
 * 담지 않으므로 보존한다. 거래처 사업정보(partners)는 운영자 관리 자산이라 건드리지 않는다.
 *
 * 파괴적 작업이므로 서버에서 최근 인증(5분 이내)을 강제해 세션 탈취에 의한 삭제를 막는다.
 * Admin SDK로 삭제하므로 클라이언트 규칙(users delete 금지)도 우회한다.
 */
export const deleteAccount = onCall(async (req: CallableRequest) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");

  // 최근 인증 강제: 클라이언트가 재인증 후 토큰을 갱신해야 통과한다.
  const authTime = (req.auth?.token.auth_time as number | undefined) ?? 0;
  if (Date.now() / 1000 - authTime > REAUTH_MAX_AGE_SEC) {
    throw new HttpsError("failed-precondition", "재인증이 필요합니다. 다시 시도해 주세요.");
  }

  const db = getFirestore();
  const userSnap = await db.collection("users").doc(uid).get();
  const email = (userSnap.data()?.email ?? "") as string;

  // 1. 개인식별정보 제거: 초대코드 잔존 이메일 → users 문서 순으로 지운다.
  await purgeEmailFromInvites(email);
  await db.collection("users").doc(uid).delete();

  // 2. Auth 계정 삭제. 문서 삭제 뒤 수행해 중간 실패 시에도 재시도가 안전하다.
  try {
    await getAuth().deleteUser(uid);
  } catch (e) {
    logger.error("Auth 계정 삭제 실패", {uid, error: String(e)});
    throw new HttpsError("internal", "계정 삭제에 실패했습니다. 잠시 후 다시 시도해 주세요.");
  }

  logger.info("계정 삭제 완료", {uid});
  return {ok: true};
});
