# ChimeraCoffee

## WeChat Pay configuration

Ensure the following environment variables are set when deploying:

- `WECHATPAY_PUBLIC_KEY_PATH` - absolute path to the downloaded WeChat Pay public key.
- `WECHATPAY_PUBLIC_KEY_ID` - the corresponding WeChat Pay public key ID.
- `WECHATPAY_NOTIFICATION_USE_COMBINED` - set to `true` only during the transition period when callbacks must accept both platform certificates and public keys (defaults to `false`).

These variables complement the existing merchant certificate inputs so the service can build `RSAPublicKeyConfig` instances required by the 0.2.15+ Java SDK.
