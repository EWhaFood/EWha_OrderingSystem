import {onCall, HttpsError, CallableRequest} from "firebase-functions/v2/https";
import {getFirestore} from "firebase-admin/firestore";
import {getAuth} from "firebase-admin/auth";
import * as logger from "firebase-functions/logger";

/**
 * 계정 삭제(탈퇴) — 호출자 본인 계정만 삭제한다 (EWOS-40).
 *
 * 개인식별정보(users 문서: email·fcmTokens)와 Auth 계정을 제거한다.
 * 발주 이력(orders)은 거래처(partnerId) 단위 감사 기록이며 개인식별정보를 담지
 * 않으므로 보존한다. 거래처 사업정보(partners)는 운영자 관리 자산이라 건드리지 않는다.
 *
 * 재인증은 클라이언트가 호출 전에 수행한다(민감 작업 보호). Admin SDK로 삭제하므로
 * requires-recent-login 제약 없이 동작하고, 클라이언트 규칙(users delete 금지)도 우회한다.
 */
export const deleteAccount = onCall(async (req: CallableRequest) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");

  const db = getFirestore();
  // 1. 개인식별정보 제거: users 문서(email·fcmTokens)를 먼저 지운다.
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
