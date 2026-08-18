import {onCall, HttpsError, CallableRequest} from "firebase-functions/v2/https";
import {getFirestore, FieldValue} from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import {notifyOperators} from "./notifications";

/**
 * 입금 확인 요청 (거래처). 계좌이체 후 거래처가 이 요청을 보내면 발주를 'requested'로
 * 표시하고 운영자에게 푸시한다. 본인 발주만 요청 가능. 실제 확인은 운영자가 한다. EWOS-44
 */
export const requestPaymentConfirm = onCall(async (req: CallableRequest) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
  const orderId = (req.data?.orderId ?? "") as string;
  if (!orderId) throw new HttpsError("invalid-argument", "주문 정보가 없습니다.");

  const db = getFirestore();
  const partnerId =
    (await db.collection("users").doc(uid).get()).data()?.partnerId as
    | string
    | undefined;
  const orderRef = db.collection("orders").doc(orderId);
  const order = (await orderRef.get()).data();
  if (!order) throw new HttpsError("not-found", "발주를 찾을 수 없습니다.");
  if (!partnerId || order.partnerId !== partnerId) {
    throw new HttpsError("permission-denied", "본인 발주만 요청할 수 있습니다.");
  }
  if (order.paymentStatus === "paid") {
    throw new HttpsError("failed-precondition", "이미 결제완료된 발주입니다.");
  }

  await orderRef.update({
    paymentStatus: "requested",
    paymentRequestedAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  await notifyOperators(
    "입금 확인 요청",
    `${order.partnerName ?? "거래처"} · ${order.orderNo ?? ""} 입금 확인을 요청했습니다.`,
  );
  logger.info("입금 확인 요청", {orderId, partnerId});
  return {ok: true};
});
