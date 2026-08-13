import {onDocumentCreated, onDocumentUpdated} from "firebase-functions/v2/firestore";
import {getFirestore, FieldValue, DocumentData} from "firebase-admin/firestore";
import {getMessaging, BatchResponse} from "firebase-admin/messaging";
import * as logger from "firebase-functions/logger";

/** 토큰과 그 소유자 uid. 무효 토큰을 어느 users 문서에서 지울지 알기 위해 uid를 함께 들고 다닌다. */
interface TokenRef {
  uid: string;
  token: string;
}

/** 거래처용 상태 라벨. 앱(order_status.dart)의 partnerLabel과 문구를 맞춘다. */
function statusLabel(status: string): string {
  const map: Record<string, string> = {
    new: "접수됨",
    hold: "접수됨",
    processing: "준비중",
    shipping: "배송중",
    done: "완료",
    canceled: "취소됨",
  };
  return map[status] ?? status;
}

function won(amount: number): string {
  return `${amount.toLocaleString("ko-KR")}원`;
}

function orderSummary(order: DocumentData): string {
  const items = (order.items as Array<{name: string}> | undefined) ?? [];
  const first = items[0]?.name ?? "발주";
  return items.length > 1 ? `${first} 외 ${items.length - 1}건` : first;
}

/** field==value 인 users의 FCM 토큰을 uid와 함께 모은다. */
async function collectTokens(
  field: "role" | "partnerId",
  value: string,
): Promise<TokenRef[]> {
  const snap = await getFirestore()
    .collection("users").where(field, "==", value).get();
  const refs: TokenRef[] = [];
  for (const doc of snap.docs) {
    const tokens = (doc.data().fcmTokens as string[] | undefined) ?? [];
    for (const token of tokens) refs.push({uid: doc.id, token});
  }
  return refs;
}

/** 발송 실패 중 등록 해제된 토큰을 해당 users.fcmTokens에서 제거한다. */
async function pruneInvalid(refs: TokenRef[], res: BatchResponse): Promise<void> {
  const db = getFirestore();
  const jobs: Promise<unknown>[] = [];
  res.responses.forEach((r, i) => {
    const code = r.error?.code ?? "";
    if (!r.success && code.includes("registration-token-not-registered")) {
      const {uid, token} = refs[i];
      jobs.push(db.collection("users").doc(uid)
        .update({fcmTokens: FieldValue.arrayRemove(token)}));
    }
  });
  await Promise.all(jobs);
}

/** 멀티캐스트 발송 + 무효 토큰 정리. notification(백그라운드 표시)과 data(라우팅)를 함께 보낸다. */
async function sendAndPrune(
  refs: TokenRef[],
  title: string,
  body: string,
  orderId?: string,
): Promise<void> {
  if (refs.length === 0) return;
  const res = await getMessaging().sendEachForMulticast({
    tokens: refs.map((r) => r.token),
    notification: {title, body},
    android: {
      priority: "high",
      notification: {channelId: "orders"},
    },
    data: {
      title, body,
      ...(orderId ? {orderId} : {}),
    },
  });
  logger.info(`FCM ${title}: ${res.successCount}/${refs.length} 성공`);
  await pruneInvalid(refs, res);

  // Firestore에 알림 이력 기록
  if (refs.length > 0) {
    const db = getFirestore();
    const batch = db.batch();
    for (const ref of refs) {
      const notiRef = db.collection("notifications").doc();
      batch.set(notiRef, {
        uid: ref.uid,
        title,
        body,
        orderId: orderId ?? null,
        isRead: false,
        createdAt: FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }
}

/** 운영자들에게 긴급 장애/시스템 알림을 보낸다. */
export async function notifyOperators(
  title: string,
  body: string,
): Promise<void> {
  const refs = await collectTokens("role", "operator");
  const time = new Date().toLocaleString("ko-KR", {timeZone: "Asia/Seoul"});
  const summary = `[${time}] ${body}`;
  await sendAndPrune(refs, title, summary);
}

/** 신규 발주(앱·카페24 공통) → 모든 운영자에게 알림. */
export const onOrderCreated = onDocumentCreated("orders/{orderId}", async (event) => {
  const order = event.data?.data();
  if (!order) return;
  const refs = await collectTokens("role", "operator");
  const count = (order.items as unknown[] | undefined)?.length ?? 0;
  const body = `${order.partnerName ?? "거래처"} · ${count}개 품목 · ${won(order.totalAmount ?? 0)}`;
  await sendAndPrune(refs, "새 발주 접수", body, event.params.orderId);
});

/** 발주 상태 변경 → 해당 거래처에게만 알림. 상태 외 필드 수정에는 발송하지 않는다. */
export const onOrderStatusChanged = onDocumentUpdated("orders/{orderId}", async (event) => {
  const before = event.data?.before.data();
  const after = event.data?.after.data();
  if (!before || !after || before.status === after.status) return;
  const partnerId = after.partnerId as string | undefined;
  if (!partnerId) return;

  // 1. 상태가 canceled인 경우 운영자에게 알림 (거래처 취소 대응)
  if (after.status === "canceled") {
    const operatorRefs = await collectTokens("role", "operator");
    const title = "발주 취소 알림";
    const body = `${after.partnerName ?? "거래처"}에서 발주를 취소했습니다: ${orderSummary(after)}`;
    await sendAndPrune(operatorRefs, title, body, event.params.orderId);
  }

  // 2. 해당 거래처 유저들에게 상태 변경 알림
  const refs = await collectTokens("partnerId", partnerId);
  const body = `${orderSummary(after)} → ${statusLabel(after.status as string)}`;
  await sendAndPrune(refs, "발주 상태 변경", body, event.params.orderId);
});
