import {setGlobalOptions} from "firebase-functions/v2";
import {initializeApp} from "firebase-admin/app";

// 카페24 외부 호출·FCM 발송을 서울 리전에서 처리한다.
setGlobalOptions({region: "asia-northeast3"});
initializeApp();

// 발주 알림 FCM 트리거 (EWOS-16)
export {onOrderCreated, onOrderStatusChanged} from "./notifications";

// 초대 코드 발급·가입 (EWOS-24)
export {issueInvite, redeemInvite} from "./invites";

// 카페24 OAuth 콜백·토큰 갱신·웹훅 수신 (EWOS-19) + 주문 폴링 (EWOS-21)
export {
  cafe24Install,
  cafe24OAuthCallback,
  refreshCafe24Tokens,
  cafe24Webhook,
  pollCafe24Orders,
} from "./cafe24";
