import {setGlobalOptions} from "firebase-functions/v2";
import {onRequest} from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import {initializeApp} from "firebase-admin/app";

// 카페24 외부 호출·FCM 발송을 서울 리전에서 처리한다.
setGlobalOptions({region: "asia-northeast3"});
initializeApp();

/**
 * 배포·연동 확인용 헬스체크 (EWOS-8 완료 조건).
 * 배포 후 함수 URL 호출 시 OK 응답이면 Functions 파이프라인이 정상이다.
 *
 * ⚠️ 임시 함수. 인증 없는 public 엔드포인트이므로 프로덕션에 방치하지 말 것.
 * EWOS-16(FCM 트리거) 등 실제 함수가 추가되면 이 함수는 제거한다.
 * (지금은 export가 하나도 없으면 배포가 실패하므로 남겨둔다.)
 */
export const healthCheck = onRequest((req, res) => {
  logger.info("healthCheck 호출됨");
  res.status(200).json({
    service: "ewha-ordering-functions",
    status: "ok",
    time: new Date().toISOString(),
  });
});

// 이후 추가 예정:
// - onOrderCreated / onOrderStatusChanged: FCM 푸시 트리거 (EWOS-16)
// - cafe24OAuthCallback / refreshToken: 카페24 인증 (EWOS-19)
// - cafe24OrderWebhook: 주문 웹훅 수신·정규화 (EWOS-21)
