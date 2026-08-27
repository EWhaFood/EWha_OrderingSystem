import {onCall, HttpsError, CallableRequest} from "firebase-functions/v2/https";
import {defineSecret} from "firebase-functions/params";
import {getFirestore, FieldValue, Timestamp, Firestore}
  from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import {notifyOperators} from "./notifications";

// PortOne V2 API secret. 클라이언트에 노출 금지 — Functions 전용. (EWOS-52)
const PORTONE_API_SECRET = defineSecret("PORTONE_API_SECRET");

interface PaidItem {
  productId: string;
  name: string;
  qty: number;
  unitPrice: number;
  amount: number;
}

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

/** 서버 채번: 클라이언트 generateOrderNo와 동일 형식(YYYYMMDD-HHMMSSmmm, KST). */
function serverOrderNo(now: Date): string {
  const kst = new Date(now.getTime() + 9 * 3600 * 1000);
  const p = (n: number, l = 2): string => String(n).padStart(l, "0");
  const date =
    `${kst.getUTCFullYear()}${p(kst.getUTCMonth() + 1)}${p(kst.getUTCDate())}`;
  const time =
    `${p(kst.getUTCHours())}${p(kst.getUTCMinutes())}${p(kst.getUTCSeconds())}`;
  return `${date}-${time}${p(kst.getUTCMilliseconds(), 3)}`;
}

/** 담긴 품목을 products에서 다시 읽어 단가·합계를 서버가 재계산한다(클라 금액 불신). */
async function buildItems(
  db: Firestore,
  qtys: Record<string, number>,
): Promise<{items: PaidItem[]; total: number}> {
  const ids = Object.keys(qtys);
  const items: PaidItem[] = [];
  let total = 0;
  for (let i = 0; i < ids.length; i += 10) {
    const refs = ids.slice(i, i + 10)
      .map((id) => db.collection("products").doc(id));
    const snaps = await db.getAll(...refs);
    for (const d of snaps) {
      const p = d.data();
      if (!d.exists || !p) continue;
      if (p.enabled !== true) {
        throw new HttpsError(
          "failed-precondition", `${p.name ?? "품목"}이 발주 중지되었습니다.`);
      }
      const qty = qtys[d.id] ?? 0;
      if (qty <= 0) continue;
      const unitPrice = (p.price as number) ?? 0;
      const amount = unitPrice * qty;
      total += amount;
      items.push({productId: d.id, name: p.name ?? "", qty, unitPrice, amount});
    }
  }
  return {items, total};
}

interface PortonePayment { status: string; total: number; currency: string; }

/** PortOne V2 결제를 조회한다(상태·금액·통화). HTTP 오류 시에만 예외. */
async function fetchPortonePayment(
  paymentId: string,
  secret: string,
): Promise<PortonePayment> {
  const res = await fetch(
    `https://api.portone.io/payments/${encodeURIComponent(paymentId)}`,
    {headers: {Authorization: `PortOne ${secret}`}},
  );
  if (!res.ok) {
    throw new HttpsError("failed-precondition", `결제 조회 실패(${res.status})`);
  }
  const p = await res.json() as
    {status?: string; currency?: string; amount?: {total?: number}};
  return {
    status: p.status ?? "",
    total: p.amount?.total ?? -1,
    currency: p.currency ?? "",
  };
}

/**
 * 결제를 취소(환불)한다. 결제는 됐는데 주문을 못 만든 경우 돈이 묶이지 않도록 한다(EWOS-52).
 * best-effort: 실패해도 예외를 던지지 않고 로깅만 한다(원래의 실패 사유를 가리지 않도록).
 */
async function cancelPortonePayment(
  paymentId: string,
  reason: string,
  secret: string,
): Promise<void> {
  try {
    const res = await fetch(
      `https://api.portone.io/payments/${encodeURIComponent(paymentId)}/cancel`,
      {
        method: "POST",
        headers: {
          "Authorization": `PortOne ${secret}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({reason}),
      },
    );
    if (!res.ok) {
      logger.warn("PortOne 결제 취소 실패", {paymentId, status: res.status});
    } else {
      logger.info("PortOne 결제 취소(환불)", {paymentId, reason});
    }
  } catch (e) {
    logger.error("PortOne 결제 취소 예외", {paymentId, error: String(e)});
  }
}

/**
 * 간편결제(PortOne) 즉시결제 발주 생성 (EWOS-52).
 * 결제 성공 후 호출된다. 서버가 금액을 재계산하고 PortOne로 결제를 검증한 뒤에만
 * 주문을 만든다. paymentId 기준 멱등(중복 주문 방지).
 */
export const createPaidOrder = onCall(
  {secrets: [PORTONE_API_SECRET]},
  async (req: CallableRequest) => {
    const uid = req.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    const paymentId = String(req.data?.paymentId ?? "");
    const qtys = (req.data?.qtys ?? {}) as Record<string, number>;
    if (!paymentId) throw new HttpsError("invalid-argument", "결제 정보가 없습니다.");
    if (Object.keys(qtys).length === 0) {
      throw new HttpsError("invalid-argument", "담긴 품목이 없습니다.");
    }

    const db = getFirestore();
    const user = (await db.collection("users").doc(uid).get()).data();
    const partnerId = user?.partnerId as string | undefined;
    if (!partnerId) throw new HttpsError("permission-denied", "거래처 계정이 아닙니다.");
    const partner = (await db.collection("partners").doc(partnerId).get()).data();
    if (!partner || partner.active !== true) {
      throw new HttpsError("permission-denied", "비활성 거래처입니다.");
    }

    // 멱등성: 같은 결제로 이미 만든 주문이 있으면 그대로 반환.
    const dup = await db.collection("orders")
      .where("paymentId", "==", paymentId).limit(1).get();
    if (!dup.empty) {
      return {orderNo: dup.docs[0].data().orderNo as string, duplicated: true};
    }

    const secret = PORTONE_API_SECRET.value();
    const pay = await fetchPortonePayment(paymentId, secret);
    if (pay.status !== "PAID") {
      // 결제가 실제로 완료되지 않았으면 취소할 것도 없다.
      throw new HttpsError("failed-precondition", "결제가 완료되지 않았습니다.");
    }

    // 여기부터 결제는 완료 상태. 어떤 이유로든 주문을 못 만들면 결제를 취소(환불)한다.
    try {
      const {items, total} = await buildItems(db, qtys);
      if (items.length === 0) {
        throw new HttpsError("failed-precondition", "유효한 품목이 없습니다.");
      }
      if (pay.currency !== "KRW" || pay.total !== total) {
        throw new HttpsError(
          "failed-precondition", "결제 금액이 주문 금액과 일치하지 않습니다.");
      }
      const desired = req.data?.desiredDeliveryDate;
      const orderNo = serverOrderNo(new Date());
      const ref = await db.collection("orders").add({
        orderNo,
        source: "app",
        status: "new",
        partnerId,
        partnerName: partner.name ?? "",
        items,
        totalAmount: total,
        shippingAddress: (req.data?.shippingAddress ?? null) as string | null,
        memo: (req.data?.memo ?? null) as string | null,
        paymentStatus: "paid",
        paymentId,
        paidAmount: total,
        paidAt: FieldValue.serverTimestamp(),
        desiredDeliveryDate:
          desired ? Timestamp.fromMillis(Number(desired)) : null,
        history: [{status: "new", byUid: uid, at: Timestamp.now()}],
        createdAt: FieldValue.serverTimestamp(),
      });
      await notifyOperators(
        "새 발주 접수(결제완료)",
        `${partner.name ?? "거래처"} · ${orderNo} 간편결제 발주가 접수되었습니다.`,
      );
      logger.info("간편결제 주문 생성", {orderId: ref.id, paymentId, total});
      return {orderNo};
    } catch (e) {
      // 결제는 됐는데 주문을 못 만든 경우 → 자동 환불 후 원래 오류를 전달.
      const reason = e instanceof HttpsError ? e.message : "주문 생성 실패";
      await cancelPortonePayment(paymentId, reason, secret);
      throw e;
    }
  },
);
