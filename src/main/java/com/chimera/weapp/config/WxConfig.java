package com.chimera.weapp.config;

import com.wechat.pay.java.core.Config;
import com.wechat.pay.java.core.RSAPublicKeyConfig;
import com.wechat.pay.java.core.cipher.PrivacyDecryptor;
import com.wechat.pay.java.core.cipher.PrivacyEncryptor;
import com.wechat.pay.java.core.cipher.RSAPrivacyDecryptor;
import com.wechat.pay.java.core.cipher.RSAPrivacyEncryptor;
import com.wechat.pay.java.core.notification.NotificationConfig;
import com.wechat.pay.java.core.notification.RSACombinedNotificationConfig;
import com.wechat.pay.java.core.notification.RSAPublicKeyNotificationConfig;
import com.wechat.pay.java.core.util.PemUtil;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Primary;

import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.PrivateKey;
import java.security.PublicKey;

@Configuration
public class WxConfig {
    @Value("${wx-mini-program.mchid}")
    private String merchantId;
    @Value("${wx-mini-program.private-key-path}")
    private String privateKeyPath;
    @Value("${wx-mini-program.merchant-serial-number}")
    private String merchantSerialNumber;
    @Value("${wx-mini-program.api-v3-key}")
    private String apiV3Key;
    @Value("${wx-mini-program.wechatpay-public-key-path}")
    private String wechatPayPublicKeyPath;
    @Value("${wx-mini-program.wechatpay-public-key-id}")
    private String wechatPayPublicKeyId;
    @Value("${wx-mini-program.notification.use-combined-config:false}")
    private boolean useCombinedNotificationConfig;


    /**
     * 构建通用的 RSAPublicKeyConfig.Builder，用于减少重复代码
     */
    private RSAPublicKeyConfig.Builder getCommonBuilder() {
        return new RSAPublicKeyConfig.Builder()
                .merchantId(merchantId)
                .privateKeyFromPath(privateKeyPath)
                .merchantSerialNumber(merchantSerialNumber)
                .apiV3Key(apiV3Key)
                .publicKeyFromPath(wechatPayPublicKeyPath)
                .publicKeyId(wechatPayPublicKeyId);
    }

    private RSAPublicKeyNotificationConfig.Builder getPublicKeyNotificationBuilder() {
        return new RSAPublicKeyNotificationConfig.Builder()
                .publicKeyFromPath(wechatPayPublicKeyPath)
                .publicKeyId(wechatPayPublicKeyId)
                .apiV3Key(apiV3Key);
    }

    /**
     * 创建 NotificationConfig Bean
     */
    @Bean
    public NotificationConfig wechatPayNotificationConfig() {
        if (useCombinedNotificationConfig) {
            // 平滑切换期间需要同时支持平台证书和公钥验签
            return new RSACombinedNotificationConfig.Builder()
                    .merchantId(merchantId)
                    .privateKeyFromPath(privateKeyPath)
                    .merchantSerialNumber(merchantSerialNumber)
                    .publicKeyFromPath(wechatPayPublicKeyPath)
                    .publicKeyId(wechatPayPublicKeyId)
                    .apiV3Key(apiV3Key)
                    .build();
        }
        return getPublicKeyNotificationBuilder().build();
    }

    /**
     * 创建 Config Bean
     */
    @Bean
    @Primary
    public Config wechatPayConfig() {
        return getCommonBuilder().build();
    }

    @Bean
    public PrivacyEncryptor wechatPayPrivacyEncryptor() {
        return new RSAPrivacyEncryptor(loadWechatPayPublicKey(), wechatPayPublicKeyId);
    }

    @Bean
    public PrivacyDecryptor merchantPrivacyDecryptor() {
        return new RSAPrivacyDecryptor(loadMerchantPrivateKey());
    }

    private PublicKey loadWechatPayPublicKey() {
        return PemUtil.loadPublicKeyFromPath(wechatPayPublicKeyPath);
    }

    private PrivateKey loadMerchantPrivateKey() {
        return PemUtil.loadPrivateKeyFromPath(privateKeyPath);
    }
}
