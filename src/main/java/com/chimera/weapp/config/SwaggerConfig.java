package com.chimera.weapp.config;

import io.swagger.v3.oas.models.ExternalDocumentation;
import io.swagger.v3.oas.models.OpenAPI;
import io.swagger.v3.oas.models.info.Info;
import io.swagger.v3.oas.models.info.License;
import io.swagger.v3.oas.models.servers.Server;
import io.swagger.v3.oas.models.media.StringSchema;
import org.bson.types.ObjectId;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Primary;

import java.util.Collections;

@Configuration
public class SwaggerConfig {

    @Value("${app.url:https://www.chimeracoffee.top}")
    private String appUrl;

    @Bean
    @Primary
    public OpenAPI customOpenAPI() {
        // 定义服务器信息 - 使用环境变量配置的URL
        Server server = new Server();
        server.setUrl(appUrl);
        server.setDescription("API Server");

        return new OpenAPI()
                .info(new Info()
                        .title("Chimera Coffee API")
                        .description("Chimera Coffee Shop Management API")
                        .version("v0.0.1")
                        .license(new License().name("Apache 2.0").url("http://springdoc.org")))
                .servers(Collections.singletonList(server))
                .externalDocs(new ExternalDocumentation()
                        .description("Documentation")
                        .url("https://github.com/your-org/chimera-coffee"))
                .components(new io.swagger.v3.oas.models.Components()
                        .addSchemas(ObjectId.class.getSimpleName(), new StringSchema()));
    }
}
