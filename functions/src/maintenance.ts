import {onCall, HttpsError, CallableRequest} from "firebase-functions/v2/https";
import {getFirestore, QueryDocumentSnapshot} from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import {assertOperator} from "./invites";

type KeepFn = (d: QueryDocumentSnapshot) => boolean;

/** 컬렉션에서 keepFn==true 문서는 보존, 나머지를 배치 삭제하고 삭제 건수를 돌려준다. */
async function purge(coll: string, keep?: KeepFn): Promise<number> {
  const db = getFirestore();
  const snap = await db.collection(coll).get();
  const targets = snap.docs.filter((d) => !(keep && keep(d)));
  for (let i = 0; i < targets.length; i += 400) {
    const batch = db.batch();
    targets.slice(i, i + 400).forEach((d) => batch.delete(d.ref));
    await batch.commit();
  }
  return targets.length;
}

/**
 * 테스트 데이터 삭제 (운영자 전용). 파일럿/테스트 단계에서만 쓰는 정리 도구.
 * settings/testMode.enabled==true 일 때만 동작한다(출시 후 false로 두면 잠김).
 * secrets·cafe24Status·운영자 계정은 절대 지우지 않는다.
 */
export const clearTestData = onCall(async (req: CallableRequest) => {
  await assertOperator(req);
  const db = getFirestore();
  const flag = await db.collection("settings").doc("testMode").get();
  if (flag.data()?.enabled !== true) {
    throw new HttpsError(
      "failed-precondition", "테스트 모드에서만 사용할 수 있습니다.");
  }
  const o = (req.data ?? {}) as {
    orders?: boolean; notifications?: boolean;
    favorites?: boolean; standingOrders?: boolean;
    products?: boolean; cafe24Products?: boolean;
    partners?: boolean; partnerUsers?: boolean;
  };
  // 선택한 항목만 삭제한다(기본은 아무것도 안 지움).
  const deleted: Record<string, number> = {};
  if (o.orders) deleted.orders = await purge("orders");
  if (o.notifications) deleted.notifications = await purge("notifications");
  if (o.favorites) deleted.favorites = await purge("favorites");
  if (o.standingOrders) deleted.standing_orders = await purge("standing_orders");
  // 상품: 수동/카페24를 각각 선택한 것만 삭제(선택 안 하면 보존).
  if (o.products || o.cafe24Products) {
    deleted.products = await purge("products",
      (d) => d.id.startsWith("cafe24_") ? !o.cafe24Products : !o.products);
  }
  if (o.partners) deleted.partners = await purge("partners");
  // 운영자는 항상 보존. role=='partner'만 삭제.
  if (o.partnerUsers) {
    deleted.users = await purge("users", (d) => d.data().role !== "partner");
  }
  logger.info("테스트 데이터 삭제", {by: req.auth?.uid, deleted});
  return {ok: true, deleted};
});
