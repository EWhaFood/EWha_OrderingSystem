import {setGlobalOptions} from "firebase-functions/v2";
import {initializeApp} from "firebase-admin/app";

// 카페24 외부 호출·FCM 발송을 서울 리전에서 처리한다.
setGlobalOptions({region: "asia-northeast3"});
initializeApp();

// 발주 알림 FCM 트리거 (EWOS-16)
export {onOrderCreated, onOrderStatusChanged} from "./notifications";

// 이후 추가 예정:
// - cafe24OAuthCallback / refreshToken: 카페24 인증 (EWOS-19)
// - cafe24OrderWebhook: 주문 웹훅 수신·정규화 (EWOS-21)
