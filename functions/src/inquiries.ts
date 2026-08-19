import {onDocumentCreated} from "firebase-functions/v2/firestore";
import {getFirestore, FieldValue} from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import {collectTokens, sendAndPrune, TokenRef} from "./notifications";

/** 문의 메시지 생성 시 요약 업데이트 및 푸시 알림 전송 */
export const onMessageCreated = onDocumentCreated("inquiries/{orderId}/messages/{messageId}", async (event) => {
  const message = event.data?.data();
  if (!message) return;

  const orderId = event.params.orderId;
  const db = getFirestore();

  // 1. 발주 정보 조회 (거래처 ID 파악용)
  const orderSnap = await db.collection("orders").doc(orderId).get();
  if (!orderSnap.exists) {
    logger.error(`발주 문서를 찾을 수 없음: ${orderId}`);
    return;
  }
  const orderData = orderSnap.data()!;
  const partnerId = orderData.partnerId;
  const partnerName = orderData.partnerName ?? "거래처";
  const orderNo = orderData.orderNo ?? "";

  // 2. 수신자 결정 및 Inquiry 요약 업데이트
  const senderRole = message.senderRole;
  const isOperatorSender = senderRole === "operator";

  const updateData: Record<string, any> = {
    lastMessage: message.text,
    lastAt: message.createdAt,
  };

  let receiverRefs: TokenRef[] = [];
  let title = "";
  const body = message.text;

  if (isOperatorSender) {
    // 운영자가 보냄 -> 거래처에게 알림
    updateData.unreadCountPartner = FieldValue.increment(1);
    if (partnerId) {
      receiverRefs = await collectTokens("partnerId", partnerId);
      logger.info(`[채팅] 거래처 알림 대상(${partnerId}): ${receiverRefs.length}개 토큰 발견`);
    } else {
      logger.warn(`[채팅] 발주(${orderId})에 partnerId가 없어 알림을 보낼 수 없음`);
    }
    title = `[문의 답변] ${orderNo}`;
  } else {
    // 거래처가 보냄 -> 모든 운영자에게 알림
    updateData.unreadCountOperator = FieldValue.increment(1);
    receiverRefs = await collectTokens("role", "operator");
    logger.info(`[채팅] 운영자 알림 대상: ${receiverRefs.length}개 토큰 발견`);
    title = `[문의] ${partnerName} (${orderNo})`;
  }

  // 3. 요약 문서 업데이트
  await db.collection("inquiries").doc(orderId).set(updateData, {merge: true});

  // 4. 푸시 알림 발송
  if (receiverRefs.length > 0) {
    await sendAndPrune(receiverRefs, title, body, orderId);
  } else {
    logger.warn(`[채팅] 알림을 보낼 대상 토큰이 없음 (수신역할: ${isOperatorSender ? "partner" : "operator"})`);
  }
});
